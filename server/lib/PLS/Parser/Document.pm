package PLS::Parser::Document;

use strict;
use warnings;

use feature 'state';

use Digest::SHA;
use Encode;
use ExtUtils::Installed;
use List::Util qw(first any);
use Module::CoreList;
use PPI;
use PPI::Find;
use PPR;
use Perl::Tidy;
use Scalar::Util qw(blessed);
use Time::Seconds;
use URI;
use URI::file;

use PLS::Parser::Element;
use PLS::Parser::Element::Constant;
use PLS::Parser::Element::Package;
use PLS::Parser::Element::Subroutine;
use PLS::Parser::Element::VariableStatement;
use PLS::Parser::Index;
use PLS::Parser::Pod::ClassMethod;
use PLS::Parser::Pod::Method;
use PLS::Parser::Pod::Package;
use PLS::Parser::Pod::Subroutine;
use PLS::Parser::Pod::Variable;

my %FILES;
my %VERSIONS;

=head1 NAME

PLS::Parser::Document

=head1 DESCRIPTION

This is a class that represents a text document. It has methods
for parsing and manipulating the document using L<PPI> and L<PPR>.

=head1 METHODS

=head2 new

This creates a new L<PLS::Parser::Document> object.
It takes named parameters.

Either C<uri> or C<path> must be passed.

C<line> with a line number may be passed, which indicates that only one line
of the document should be parsed. This greatly enhances performance for completion items.

=cut

sub new
{
    my ($class, %args) = @_;

    my ($path, $uri);

    if (length $args{uri})
    {
        $path       = URI->new($args{uri})->file;
        $args{path} = $path;
        $uri        = $args{uri};
    } ## end if (length $args{uri})
    elsif (length $args{path})
    {
        $path      = $args{path};
        $uri       = URI::file->new($path)->as_string;
        $args{uri} = $uri;
    } ## end elsif (length $args{path}...)
    return unless (length $path and length $uri);

    my $self = bless {
                      path => $path,
                      uri  => $uri
                     }, $class;

    $self->{index} = PLS::Parser::Index->new();
    my $document = $self->_get_ppi_document(%args);
    return unless (ref $document eq 'PPI::Document');
    $self->{document} = $document;

    return $self;
} ## end sub new

=head2 go_to_definition

This finds the definition of a symbol located at a given line and column number.

=cut

sub go_to_definition
{
    my ($self, $line_number, $column_number) = @_;

    my @matches = $self->find_elements_at_location($line_number, $column_number);

    return $self->search_elements_for_definition($line_number, $column_number, @matches);
} ## end sub go_to_definition

=head2 find_current_list

This finds the nearest list structure that surrounds the current column on the current line.
This is useful for finding which parameter the cursor is on when calling a function.

=cut

sub find_current_list
{
    my ($self, $line_number, $column_number) = @_;

    my @elements = $self->find_elements_at_location($line_number, $column_number);
    my $find     = PPI::Find->new(sub { $_[0]->isa('PPI::Structure::List') });

    # Find the nearest list structure that completely surrounds the column.
    return first { $_->lsp_column_number < $column_number and $column_number < $_->lsp_column_number + length($_->content) }
      sort { abs($column_number - $a->lsp_column_number) - abs($column_number - $b->lsp_column_number) }
      map  { PLS::Parser::Element->new(element => $_, document => $self->{document}, file => $self->{path}) }
      map  { $find->in($_->element) } @elements;
} ## end sub find_current_list

=head2 go_to_definition_of_closest_subroutine

Given a list of elements, this finds the closest subroutine call to the current line and column.

=cut

sub go_to_definition_of_closest_subroutine
{
    my ($self, $list, $line_number, $column_number) = @_;

    return if (not blessed($list) or not $list->isa('PLS::Parser::Element') and $list->type eq 'PPI::Structure::List');

    # Try to find the closest word before the list - this is the function name.
    my $word = $list;

    while (blessed($word) and $word->isa('PLS::Parser::Element') and not $word->element->isa('PPI::Token::Word'))
    {
        $word = $word->previous_sibling;
    }

    return if (not blessed($word) or not $word->isa('PLS::Parser::Element') or not $word->element->isa('PPI::Token::Word'));

    my $fully_qualified = $word->name;
    my @parts           = split /::/, $fully_qualified;
    my $subroutine      = pop @parts;

    my $definitions;

    if (scalar @parts and $parts[-1] ne 'SUPER')
    {
        my $package = join '::', @parts;
        $definitions = $self->{index}->find_package_subroutine($package, $subroutine);
    }
    else
    {
        $definitions = $self->{index}->find_subroutine($subroutine);
    }

    return $definitions, $word if wantarray;
    return $definitions;
} ## end sub go_to_definition_of_closest_subroutine

=head2 search_elements_for_definition

This tries to find the definition in a list of elements, and returns the first definition found.

=cut

sub search_elements_for_definition
{
    my ($self, $line_number, $column_number, @matches) = @_;

    my $this_files_package;
    my @this_files_subroutines;

    if (ref $self->{index} ne 'PLS::Parser::Index')
    {
        ($this_files_package) = @{$self->get_packages()};
        @this_files_subroutines = (@{$self->get_subroutines()}, @{$self->get_constants()});
    }

    foreach my $match (@matches)
    {
        if (my ($package, $subroutine) = $match->subroutine_package_and_name())
        {
            if ($match->cursor_on_package($column_number))
            {
                if (ref $self->{index} eq 'PLS::Parser::Index')
                {
                    return $self->{index}->find_package($package);
                }
                else
                {
                    return [{uri => $self->{uri}, range => $this_files_package->range}] if (ref $this_files_package eq 'PLS::Parser::Element::Package' and $this_files_package->name eq $package);

                    my $external = $self->find_external_package($package);
                    return [$external] if (ref $external eq 'HASH');
                } ## end else [ if (ref $self->{index}...)]
            } ## end if ($match->cursor_on_package...)

            if (length $package)
            {
                if (ref $self->{index} eq 'PLS::Parser::Index')
                {
                    my $results = $self->{index}->find_package_subroutine($package, $subroutine);
                    return $results if (ref $results eq 'ARRAY' and scalar @{$results});
                }
                else
                {
                    if (ref $this_files_package eq 'PLS::Parser::Element::Package' and $this_files_package->name eq $package)
                    {
                        my $found = first { $_->name eq $subroutine } @this_files_subroutines;
                        return {uri => $self->{uri}, range => $found->range} if (blessed($found) and $found->isa('PLS::Parser::Element'));
                    }
                } ## end else [ if (ref $self->{index}...)]

                my $external = $self->find_external_subroutine($package, $subroutine);
                return [$external] if (ref $external eq 'HASH');
            } ## end if (length $package)

            if (ref $self->{index} eq 'PLS::Parser::Index')
            {
                my $results = $self->{index}->find_subroutine($subroutine);
                return $results if (ref $results eq 'ARRAY' and scalar @{$results});

                @this_files_subroutines = (@{$self->get_subroutines()}, @{$self->get_constants()});
            } ## end if (ref $self->{index}...)

            my $found = first { $_->name eq $subroutine } @this_files_subroutines;
            return {uri => $self->{uri}, range => $found->range} if (blessed($found) and $found->isa('PLS::Parser::Element'));
        } ## end if (my ($package, $subroutine...))
        if (my ($class, $method) = $match->class_method_package_and_name())
        {
            if (ref $self->{index} eq 'PLS::Parser::Index')
            {
                my $results = $self->{index}->find_package_subroutine($class, $method);

                # fall back to treating as a method instead of class method
                return $results if (ref $results eq 'ARRAY' and scalar @$results);
            } ## end if (ref $self->{index}...)
            else
            {
                my $found = first { $_->name eq $method } @this_files_subroutines;
                return {uri => $self->{uri}, range => $found->range} if (blessed($found) and $found->isa('PLS::Parser::Element'));
            }

            my $external = $self->find_external_subroutine($class, $method);
            return [$external] if (ref $external eq 'HASH');
        } ## end if (my ($class, $method...))
        if (my $method = $match->method_name())
        {
            if (ref $self->{index} eq 'PLS::Parser::Index')
            {
                return $self->{index}->find_subroutine($method);
            }
            else
            {
                my $found = first { $_->name eq $method } @this_files_subroutines;
                return {uri => $self->{uri}, range => $found->range} if (blessed($found) and $found->isa('PLS::Parser::Element'));
            }
        } ## end if (my $method = $match...)
        if (my ($package, $import) = $match->package_name($column_number))
        {
            if (length $import)
            {
                if (ref $self->{index} eq 'PLS::Parser::Index')
                {
                    return $self->{index}->find_package_subroutine($package, $import);
                }
                else
                {
                    my $external = $self->find_external_subroutine($package, $import);
                    return [$external] if (ref $external eq 'HASH');
                }
            } ## end if (length $import)
            else
            {
                if (ref $self->{index} eq 'PLS::Parser::Index')
                {
                    return $self->{index}->find_package($package);
                }
                else
                {
                    my $external = $self->find_external_package($package);
                    return [$external] if (ref $external eq 'HASH');
                }
            } ## end else [ if (length $import) ]
        } ## end if (my ($package, $import...))
        if (my $variable = $match->variable_name())
        {
            return $self->go_to_variable_definition($variable, $match, $line_number, $column_number);
        }
    } ## end foreach my $match (@matches...)

    # If all else fails, see if we're on a POD link.
    if (my $link = $self->pod_link($line_number, $column_number))
    {
        my @pieces          = split /::/, $link;
        my $subroutine_name = pop @pieces;
        my $package_name    = join '::', @pieces;

        if (ref $self->{index} eq 'PLS::Parser::Index')
        {
            my $package = $self->{index}->find_package($link);
            return $package if (ref $package eq 'ARRAY' and scalar @{$package});

            return $self->{index}->find_package_subroutine($package_name, $subroutine_name) if (length $package_name);
            return $self->{index}->find_subroutine($subroutine_name);
        } ## end if (ref $self->{index}...)
        else
        {
            my $external = $self->find_external_package($link);
            return [$external] if (ref $external eq 'HASH');

            $external = $self->find_external_subroutine($package_name, $subroutine_name);
            return [$external] if (ref $external eq 'HASH');
        } ## end else [ if (ref $self->{index}...)]

    } ## end if (my $link = $self->...)

    return;
} ## end sub search_elements_for_definition

=head2 pod_link

This determines if the line and column are within a POD LE<lt>E<gt> code,
and returns the contents of the link if so.

=cut

sub pod_link
{
    my ($self, $line_number, $column_number) = @_;

    $line_number++;

    my $find = PPI::Find->new(
        sub {
            my ($element) = @_;
            return 0 unless $element->isa('PPI::Token::Pod');
            return 0 if $element->line_number > $line_number;
            return 0 if $element->line_number + scalar($element->lines) < $line_number;
            return 1;
        }
    );

    return unless (scalar $find->in($self->{document}));

    open my $fh, '<', $self->get_full_text() or return;

    while (my $line = <$fh>)
    {
        next unless $. == $line_number;
        chomp $line;

        while (
            $line =~ m{
                L< # starting L<
                (?:
                    <+ # optional additional <
                    \s+ # spaces required if any additional <
                )?
                (.+?) # the actual link content
                (?:
                    \s+ # spaces required if any additional >
                    +>+ # optional additional >
                )?
                > # final closing >
            }gx
          )
        {
            my $start = $-[1];
            my $end   = $+[1];
            my $link  = $1;

            next if ($start > $column_number or $column_number > $end);

            # Get just the name - remove the text and section parts
            $link =~ s/^[^<]*\|//;
            $link =~ s/\/[^>]*$//;
            return $link;
        } ## end while ($line =~ m{ ) (})

        last;
    } ## end while (my $line = <$fh>)

    return;
} ## end sub pod_link

=head2 find_pod

This attempts to find POD for the symbol at the given location.

=cut

sub find_pod
{
    my ($self, $uri, $line_number, $column_number) = @_;

    my @elements = $self->find_elements_at_location($line_number, $column_number);

    foreach my $element (@elements)
    {
        my ($package, $subroutine, $variable, $import);

        if (($package, $import) = $element->package_name($column_number))
        {
            my %args       = (index => $self->{index}, element => $element, package => $package);
            my $class_name = 'PLS::Parser::Pod::Package';

            if (length $import)
            {
                if ($import =~ /^[\$\@\%]/)
                {
                    $args{variable} = $import;
                    $class_name = 'PLS::Parser::Pod::Variable';
                }
                else
                {
                    $args{subroutine} = $import;
                    $args{packages}   = [$package];
                    delete $args{package};
                    $class_name = 'PLS::Parser::Pod::Subroutine';
                } ## end else [ if ($import =~ /^[\$\@\%]/...)]
            } ## end if (length $import)

            my $pod = $class_name->new(%args);
            my $ok  = $pod->find();
            return (1, $pod) if $ok;
        } ## end if (($package, $import...))
        if (($package, $subroutine) = $element->class_method_package_and_name())
        {
            my $pod =
              PLS::Parser::Pod::ClassMethod->new(
                                                 index      => $self->{index},
                                                 element    => $element,
                                                 packages   => [$package],
                                                 subroutine => $subroutine
                                                );
            my $ok = $pod->find();
            return (1, $pod) if $ok;
        } ## end if (($package, $subroutine...))
        if ($subroutine = $element->method_name())
        {
            my $pod =
              PLS::Parser::Pod::Method->new(
                                            index      => $self->{index},
                                            element    => $element,
                                            subroutine => $subroutine
                                           );
            my $ok = $pod->find();
            return (1, $pod) if $ok;
        } ## end if ($subroutine = $element...)
        if (($package, $subroutine) = $element->subroutine_package_and_name())
        {
            my @packages = length $package ? ($package) : ();

            my $pod =
              PLS::Parser::Pod::Subroutine->new(
                                                uri              => $uri,
                                                index            => $self->{index},
                                                element          => $element,
                                                packages         => \@packages,
                                                subroutine       => $subroutine,
                                                include_builtins => 1
                                               );
            my $ok = $pod->find();
            return (1, $pod) if $ok;
        } ## end if (($package, $subroutine...))
        if ($variable = $element->variable_name())
        {
            my $pod =
              PLS::Parser::Pod::Variable->new(
                                              index    => $self->{index},
                                              element  => $element,
                                              variable => $variable
                                             );
            my $ok = $pod->find();
            return (1, $pod) if $ok;
        } ## end if ($variable = $element...)
        if ($element->type eq 'PPI::Token::Operator' and $element->content =~ /^-[rwxoRWXOezsfdlpSbctugkTBMAC]$/)
        {
            my $pod = PLS::Parser::Pod::Subroutine->new(
                                                        index            => $self->{index},
                                                        element          => $element,
                                                        subroutine       => '-X',
                                                        include_builtins => 1
                                                       );
            my $ok = $pod->find();
            return (1, $pod) if $ok;
        } ## end if ($element->type eq ...)
    } ## end foreach my $element (@elements...)

    return 0;
} ## end sub find_pod

sub find_elements_at_location
{
    my ($self, $line_number, $column_number) = @_;

    ($line_number, $column_number) = _ppi_location($line_number, $column_number);
    $line_number = 1 if $self->{one_line};

    my $find = PPI::Find->new(
        sub {
            my ($element) = @_;

            return 0 unless $element->line_number == $line_number;
            return 0 if $element->column_number > $column_number;
            return 0 if $element->column_number + (length $element->content) < $column_number;
            return 1;
        }
    );

    my @matches = $find->in($self->{document});
    @matches =
      sort { (abs $column_number - $a->column_number) <=> (abs $column_number - $b->column_number) } @matches;
    @matches = map { PLS::Parser::Element->new(document => $self->{document}, element => $_, file => $self->{path}) } @matches;
    return @matches;
} ## end sub find_elements_at_location

=head2 find_external_subroutine

This attempts to find the location of a subroutine inside an external module,
by name.

=cut

sub find_external_subroutine
{
    my ($self, $package_name, $subroutine_name) = @_;

    my $include = PLS::Parser::Pod->get_clean_inc();
    my $package = Module::Metadata->new_from_module($package_name, inc => $include);
    return if (ref $package ne 'Module::Metadata');

    my $doc = PLS::Parser::Document->new(path => $package->filename);
    return if (ref $doc ne 'PLS::Parser::Document');

    foreach my $subroutine (@{$doc->get_subroutines()})
    {
        next unless ($subroutine->name eq $subroutine_name);

        return {
                uri       => URI::file->new($package->filename)->as_string,
                range     => $subroutine->range(),
                signature => $subroutine->location_info->{signature}
               };
    } ## end foreach my $subroutine (@{$doc...})

    return;
} ## end sub find_external_subroutine

=head2 find_external_package

This attempts to find the location of an external package by name.

=cut

sub find_external_package
{
    my ($self, $package_name) = @_;

    return unless (length $package_name);

    my $include  = PLS::Parser::Pod->get_clean_inc();
    my $metadata = Module::Metadata->new_from_module($package_name, inc => $include);

    return if (ref $metadata ne 'Module::Metadata');

    my $document = PLS::Parser::Document->new(path => $metadata->filename);
    return if (ref $document ne 'PLS::Parser::Document');

    foreach my $package (@{$document->get_packages()})
    {
        next unless ($package->name eq $package_name);

        return {
                uri   => URI::file->new($metadata->filename)->as_string,
                range => $package->range()
               };
    } ## end foreach my $package (@{$document...})

    return;
} ## end sub find_external_package

=head2 go_to_variable_definition

This finds the definition of a variable.

This B<probably> only works correctly for C<my>, C<local>, and C<state> variables,
but may also work for C<our> variables as long as they are in the same file.

=cut

sub go_to_variable_definition
{
    my ($self, $variable, $element, $line_number, $column_number) = @_;

    my $cursor = $element->element;
    my $prev_cursor;
    my $document = $cursor->top;

    my $declaration;
    state $var_rx = qr/((?&PerlVariable))$PPR::GRAMMAR/;

  OUTER: while (1)
    {
        $prev_cursor = $cursor;
        $cursor      = $cursor->parent;

        next unless blessed($cursor);

        if ($cursor->isa('PPI::Structure::Block') or $cursor->isa('PPI::Document'))
        {
          CHILDREN: foreach my $child ($cursor->children)
            {
                last CHILDREN if $child == $prev_cursor;
                next unless blessed($child);

                if ($child->isa('PPI::Statement::Variable') and any { $_ eq $variable } $child->variables)
                {
                    $declaration = $child;
                    last OUTER;
                }
                if ($child->isa('PPI::Statement::Include') and $child->type eq 'use' and $child->pragma eq 'vars')
                {
                    while ($child =~ /$var_rx/g)
                    {
                        next if ($1 ne $variable);
                        $declaration = $child;
                        last OUTER;
                    } ## end while ($child =~ /$var_rx/g...)
                } ## end if ($child->isa('PPI::Statement::Include'...))
            } ## end foreach my $child ($cursor->...)
        } ## end if ($cursor->isa('PPI::Structure::Block'...))
        elsif ($cursor->isa('PPI::Statement::Compound'))
        {
            if ($cursor->type eq 'foreach')
            {
              CHILDREN: foreach my $child ($cursor->children)
                {
                    last CHILDREN if $child == $prev_cursor;
                    next unless blessed($child);

                    if ($child->isa('PPI::Token::Word') and $child =~ /^my|our|local|state$/)
                    {
                        if (blessed($child->snext_sibling) and $child->snext_sibling->isa('PPI::Token::Symbol') and $child->snext_sibling->symbol eq $variable)
                        {
                            #$declaration = $child->snext_sibling;
                            $declaration = $cursor;
                            last OUTER;
                        } ## end if (blessed($child->snext_sibling...))
                    } ## end if ($child->isa('PPI::Token::Word'...))
                } ## end foreach my $child ($cursor->...)
            } ## end if ($cursor->type eq 'foreach'...)
            else
            {
                my $condition = first { $_->isa('PPI::Structure::Condition') } grep { blessed($_) } $cursor->children;
                next OUTER if (not blessed($condition) or not $condition->isa('PPI::Structure::Condition'));

              CHILDREN: foreach my $child ($condition->children)
                {
                    last CHILDREN if $child == $prev_cursor;
                    next unless blessed($child);

                    if ($child->isa('PPI::Statement::Variable') and any { $_ eq $variable } $child->variables)
                    {
                        $declaration = $child;
                        last OUTER;
                    }
                } ## end foreach my $child ($condition...)
            } ## end else [ if ($cursor->type eq 'foreach'...)]
        } ## end elsif ($cursor->isa('PPI::Statement::Compound'...))

        last if $cursor == $document;
    } ## end while (1)

    return if (not blessed($declaration) or not $declaration->isa('PPI::Element'));

    $element = PLS::Parser::Element->new(file => $self->{path}, document => $self->{document}, element => $declaration);

    return [
            {
             uri   => $self->{uri},
             range => $element->range()
            }
           ];
} ## end sub go_to_variable_definition

=head2 open_file

This adds a file and its text to a list of open files.

=cut

sub open_file
{
    my ($class, %args) = @_;

    return unless $args{languageId} eq 'perl';

    $FILES{$args{uri}}    = \($args{text});
    $VERSIONS{$args{uri}} = $args{version};

    return;
} ## end sub open_file

=head2 open_files

This provides a list of names of files that are currently open.

=cut

sub open_files
{
    return [keys %FILES];
}

=head2 update_file

This patches an open file in memory to keep it synched with
the actual file in the editor.

=cut

sub update_file
{
    my ($class, @args) = @_;

    my %args = @args;

    my $file = $FILES{$args{uri}};
    return if (ref $file ne 'SCALAR');

    $VERSIONS{$args{uri}} = $args{version};

    foreach my $change (@{$args{changes}})
    {
        if (ref $change->{range} eq 'HASH')
        {
            my @lines       = _split_lines($$file);
            my @replacement = _split_lines($change->{text});

            my ($starting_text, $ending_text);

            # get the text that we're not replacing at the start and end of each selection
            # this needs to be done in UTF-16 according to the LSP specification.
            # the byte order doesn't matter because we're decoding immediately,
            # so we are using little endian.

            if ($#lines >= $change->{range}{start}{line})
            {
                my $first_line = Encode::encode('UTF-16LE', $lines[$change->{range}{start}{line}]);

                # each code unit is two bytes long
                my $starting_code_unit = $change->{range}{start}{character} * 2;
                $starting_text = substr $first_line, 0, $starting_code_unit;
                $starting_text = Encode::decode('UTF-16LE', $starting_text);
            } ## end if ($#lines >= $change...)

            if ($#lines >= $change->{range}{end}{line})
            {
                my $last_line = Encode::encode('UTF-16LE', $lines[$change->{range}{end}{line}]);

                # each code unit is two bytes long
                my $ending_code_unit = $change->{range}{end}{character} * 2;
                $ending_text = substr $last_line, $ending_code_unit;
                $ending_text = Encode::decode('UTF-16LE', $ending_text);
            } ## end if ($#lines >= $change...)

            # append the existing text to the replacement
            if (length $starting_text)
            {
                $replacement[0] = length $replacement[0] ? $starting_text . $replacement[0] : $starting_text;
            }
            if (length $ending_text)
            {
                if (scalar @replacement)
                {
                    $replacement[-1] .= $ending_text;
                }
                else
                {
                    $replacement[0] = $ending_text;
                }
            } ## end if (length $ending_text...)

            # replace the lines in the range (which may not match the number of lines in the replacement)
            # with the replacement, including the existing text that is not changing, that we appended above
            my $lines_replacing = $change->{range}{end}{line} - $change->{range}{start}{line} + 1;
            splice @lines, $change->{range}{start}{line}, $lines_replacing, @replacement;
            $$file = join '', @lines;
        } ## end if (ref $change->{range...})
        else
        {
            # no range means we're updating the entire document
            $$file = $change->{text};
        }
    } ## end foreach my $change (@{$args...})

    return;
} ## end sub update_file

=head2 close_file

This removes a file from the list of open files.

=cut

sub close_file
{
    my ($class, @args) = @_;

    my %args = @args;

    delete $FILES{$args{uri}};
    delete $VERSIONS{$args{uri}};

    return;
} ## end sub close_file

=head2 get_subroutines

This gets a list of all subroutines in a document.

=cut

sub get_subroutines
{
    my ($self) = @_;

    my $find = PPI::Find->new(
        sub {
            $_[0]->isa('PPI::Statement::Sub') and not $_[0]->isa('PPI::Statement::Scheduled') and ref $_[0]->block eq 'PPI::Structure::Block';
        }
    );
    return [map { PLS::Parser::Element::Subroutine->new(document => $self->{document}, element => $_, file => $self->{path}) } $find->in($self->{document})];
} ## end sub get_subroutines

=head2 get_constants

This gets a list of all constants in a document.

Only constants declared with C<use constant> are found.

=cut

sub get_constants
{
    my ($self, $element) = @_;

    my @matches;

    if (ref $element eq 'PPI::Statement::Include')
    {
        @matches = ($element);
    }
    else
    {
        my $find = PPI::Find->new(
            sub {
                my ($element) = @_;

                return 0 unless $element->isa('PPI::Statement::Include');
                return   unless $element->type eq 'use';
                return (length $element->module and $element->module eq 'constant');
            }
        );

        @matches = $find->in($self->{document});
    } ## end else [ if (ref $element eq 'PPI::Statement::Include'...)]

    my @constants;

    foreach my $match (@matches)
    {
        my ($constructor) = grep { $_->isa('PPI::Structure::Constructor') } $match->children;

        if (ref $constructor eq 'PPI::Structure::Constructor')
        {
            push @constants, grep { _is_constant($_) }
              map { $_->children }
              grep { $_->isa('PPI::Statement::Expression') } $constructor->children;
        } ## end if (ref $constructor eq...)
        else
        {
            push @constants, grep { _is_constant($_) } $match->children;
        }
    } ## end foreach my $match (@matches...)

    return [map { PLS::Parser::Element::Constant->new(document => $self->{document}, element => $_, file => $self->{path}) } @constants];
} ## end sub get_constants

=head2 get_packages

This gets a list of all packages in a document.

=cut

sub get_packages
{
    my ($self) = @_;

    my $find = PPI::Find->new(sub { $_[0]->isa('PPI::Statement::Package') });
    return [map { PLS::Parser::Element::Package->new(document => $self->{document}, element => $_, file => $self->{path}) } $find->in($self->{document})];
} ## end sub get_packages

=head2 get_variable_statements

This gets a list of all variable statements in a document.
A variable statement is a statement which declares one or more variables.

=cut

sub get_variable_statements
{
    my ($self, $element) = @_;

    my @elements;

    if (blessed($element) and $element->isa('PPI::Statement::Variable'))
    {
        @elements = ($element);
    }
    else
    {
        my $find = PPI::Find->new(sub { $_[0]->isa('PPI::Statement::Variable') });
        @elements = $find->in($self->{document});
    }

    return [map { PLS::Parser::Element::VariableStatement->new(document => $self->{document}, element => $_, file => $self->{path}) } @elements];
} ## end sub get_variable_statements

=head2 get_full_text

This returns a SCALAR reference of the in-memory text of the current document.

=cut

sub get_full_text
{
    my ($self) = @_;

    return $self->text_from_uri($self->{uri});
}

=head2 get_variables_fast

This gets a list of all variables in the current document.
It uses L<PPR> to do so, which is faster than L<PPI>, but only provides a list of strings.

=cut

sub get_variables_fast
{
    my ($self, $text) = @_;

    $text = $self->get_full_text() if (ref $text ne 'SCALAR');
    return []                      if (ref $text ne 'SCALAR');

    state $variable_decl_rx = qr/((?&PerlVariableDeclaration))$PPR::GRAMMAR/;
    state $lvalue_rx        = qr/((?&PerlLvalue))$PPR::GRAMMAR/;
    state $variable_rx      = qr/((?&PerlVariable))$PPR::GRAMMAR/;
    my @variables;

    while ($$text =~ /$variable_rx/g)
    {
        my $declaration = $1;
        my ($lvalue) = $declaration =~ /$lvalue_rx/;

        next unless (length $lvalue);

        while ($lvalue =~ /$variable_rx/g)
        {
            my $variable = $1;
            next unless (length $variable);
            $variable =~ s/^\s+|\s+$//g;

            push @variables, $variable;
        } ## end while ($lvalue =~ /$variable_rx/g...)
    } ## end while ($$text =~ /$variable_rx/g...)

    return \@variables;
} ## end sub get_variables_fast

=head2 get_packages_fast

This gets a list of all packages in the current document.
It uses L<PPR> to do so, which is faster than L<PPI>, but only provides a list of strings.

=cut

sub get_packages_fast
{
    my ($self, $text) = @_;

    $text = $self->get_full_text() if (ref $text ne 'SCALAR');
    return []                      if (ref $text ne 'SCALAR');

    state $package_rx = qr/((?&PerlPackageDeclaration))$PPR::GRAMMAR/;
    my @packages;

    while ($$text =~ /$package_rx/g)
    {
        my ($package) = $1 =~ /^package\s+(\S+)/;
        $package =~ s/;$//;
        next unless (length $package);

        push @packages, $package;
    } ## end while ($$text =~ /$package_rx/g...)

    return \@packages;
} ## end sub get_packages_fast

=head2 get_subroutines_fast

This gets a list of all subroutines in the current document.
It uses L<PPR> to do so, which is faster than L<PPI>, but only provides a list of strings.

=cut

sub get_subroutines_fast
{
    my ($self, $text) = @_;

    $text = $self->get_full_text() if (ref $text ne 'SCALAR');
    return []                      if (ref $text ne 'SCALAR');

    state $sub_rx = qr/sub\b(?&PerlOWS)((?&PerlOldQualifiedIdentifier))$PPR::GRAMMAR/;
    my @subroutine_declarations;

    while ($$text =~ /$sub_rx/g)
    {
        my $sub = $1;
        $sub =~ s/^\s+|\s+$//;
        push @subroutine_declarations, $1;
    } ## end while ($$text =~ /$sub_rx/g...)

    return \@subroutine_declarations;
} ## end sub get_subroutines_fast

=head2 get_constants_fast

This gets a list of all constants in the current document.
It uses L<PPR> to do so, which is faster than L<PPI>, but only provides a list of strings.

This only finds constants declared with C<use constant>.

=cut

sub get_constants_fast
{
    my ($self, $text) = @_;

    $text = $self->get_full_text() if (ref $text ne 'SCALAR');
    return []                      if (ref $text ne 'SCALAR');

    state $block_rx        = qr/use\h+constant(?&PerlOWS)((?&PerlBlock))$PPR::GRAMMAR/;
    state $bareword_rx     = qr/((?&PerlBareword))(?&PerlOWS)(?&PerlComma)$PPR::GRAMMAR/;
    state $one_constant_rx = qr/use\h+constant\h+((?&PerlBareword))(?&PerlOWS)(?&PerlComma)$PPR::GRAMMAR/;
    my @constants;

    while ($$text =~ /$block_rx/g)
    {
        my $block = $1;

        while ($block =~ /$bareword_rx/g)
        {
            my $constant = $1;

            next unless (length $constant);
            $constant =~ s/^\s+|\s+$//g;

            push @constants, $constant;
        } ## end while ($block =~ /$bareword_rx/g...)
    } ## end while ($$text =~ /$block_rx/g...)

    while ($$text =~ /$one_constant_rx/g)
    {
        my $constant = $1;
        next unless (length $constant);
        $constant =~ s/^\s+|\s+$//g;

        push @constants, $constant;
    } ## end while ($$text =~ /$one_constant_rx/g...)

    return \@constants;
} ## end sub get_constants_fast

sub get_imports
{
    my ($self, $text) = @_;

    $text = $self->get_full_text() if (ref $text ne 'SCALAR');
    return []                      if (ref $text ne 'SCALAR');

    state $use_rx        = qr/((?&PerlUseStatement))$PPR::GRAMMAR/;
    state $identifier_rx = qr/use\h+((?&PerlQualifiedIdentifier))(?&PerlOWS)(?&PerlList)?$PPR::GRAMMAR/;

    my @imports;

    while ($$text =~ /$use_rx/g)
    {
        my $use = $1;

        if ($use =~ /$identifier_rx/)
        {
            my $module = $1;

            # Assume lowercase modules are pragmas.
            next if (lc $module eq $module);

            push @imports, {use => $use, module => $module};
        } ## end if ($use =~ /$identifier_rx/...)
    } ## end while ($$text =~ /$use_rx/g...)

    return \@imports;
} ## end sub get_imports

=head2 format_range

This formats a range of text in the document using perltidy.

=cut

sub format_range
{
    my ($class, %args) = @_;

    $args{formatting_options} = {} unless (ref $args{formatting_options} eq 'HASH');
    my $range = $args{range};
    my $text  = $args{text};

    if (ref $text ne 'SCALAR')
    {
        return (0, {code => -32700, message => 'Could not get document text.'});
    }

    my $selection  = '';
    my $whole_file = 0;

    if (ref $range eq 'HASH')
    {
        # if we've selected up until the first character of the next line,
        # just format up to the line before that
        $range->{end}{line}-- if ($range->{end}{character} == 0);

        my @lines = _split_lines($$text);
        @lines = @lines[$range->{start}{line} .. $range->{end}{line}];

        # ignore the column, and just format the entire line.
        # the text will likely get messed up if you don't include the entire line, anyway.
        $range->{start}{character} = 0;
        $range->{end}{character}   = 0;
        $range->{end}{line}++;
        $selection = join '', @lines;
    } ## end if (ref $range eq 'HASH'...)
    else
    {
        $whole_file = 1;
        $selection  = $$text;
        my $lines = () = $selection =~ m{($/)}g;
        $lines++;

        $range = {
                  start => {
                            line      => 0,
                            character => 0
                           },
                  end => {
                          line      => $lines,
                          character => 0
                         }
                 };
    } ## end else [ if (ref $range eq 'HASH'...)]

    my $formatted = '';
    my $stderr    = '';
    my $argv      = '-se';
    if (length $args{formatting_options}{tabSize})
    {
        $argv .= $args{formatting_options}{insertSpaces} ? ' -i=' : ' -et=';
        $argv .= $args{formatting_options}{tabSize};
    }
    my ($perltidyrc) = glob $args{perltidyrc};
    undef $perltidyrc if (not length $perltidyrc or not -f $perltidyrc or not -r $perltidyrc);
    my $error = Perl::Tidy::perltidy(source => \$selection, destination => \$formatted, stderr => \$stderr, perltidyrc => $perltidyrc, argv => $argv);

    # get the number of lines in the formatted result - we need to modify the range if
    # any lines were added
    my $lines = () = $formatted =~ m{($/)}g;
    $lines++;

    # if the selection length has increased due to formatting, update the end.
    $range->{end}{line} = $lines if ($whole_file and $lines > $range->{end}{line});

    $formatted =~ s/\h+$//gm if ($args{formatting_options}{trimTrailingWhitespace});

    if ($args{formatting_options}{insertFinalNewline})
    {
        $formatted .= "\n" unless ($formatted =~ /\n$/);
    }
    if ($args{formatting_options}{trimFinalNewlines})
    {
        $formatted =~ s/\n+$/\n/;
    }

    $stderr =~ s/^<source_stream>:\s*//gm;
    $stderr =~ s/^Begin Error Output Stream.*$//m;
    $stderr =~ s/^.*To save a full \.LOG file.*$//m;
    $stderr =~ s/^\s*$//gm;

    return (1, undef) if ($error == 1 or length $stderr);

    return (
            1,
            [
             {
              range   => $range,
              newText => $formatted
             }
            ]
           );
} ## end sub format_range

=head2 format

This formats the entire document using perltidy.

=cut

sub format
{
    my ($class, %args) = @_;

    return $class->format_range(formatting_options => $args{formatting_options}, text => $args{text}, perltidyrc => $args{perltidyrc});
}

=head2 _ppi_location

This converts an LSP 0-indexed location to a PPI 1-indexed location.

=cut

sub _ppi_location
{
    my ($line_number, $column_number) = @_;

    return ++$line_number, ++$column_number;
}

=head2 text_from_uri

This returns a SCALAR reference to the text of a particular URI.

=cut

sub text_from_uri
{
    my (undef, $uri) = @_;

    if (ref $FILES{$uri} eq 'SCALAR')
    {
        return $FILES{$uri};
    }
    else
    {
        my $file = URI->new($uri);
        open my $fh, '<', $file->file or return;
        my $text = do { local $/; <$fh> };
        return \$text;
    } ## end else [ if (ref $FILES{$uri} eq...)]
} ## end sub text_from_uri

sub uri_version
{
    my ($uri) = @_;

    return $VERSIONS{$uri};
}

=head2 _get_ppi_document

This creates a L<PPI::Document> object for a document. It will
return an L<PPI::Document> from memory if the file has not changed since it was last parsed.

=cut

sub _get_ppi_document
{
    my ($self, %args) = @_;

    my $file;

    if ($args{text})
    {
        $file = $args{text};
    }
    elsif (length $args{uri})
    {
        if (ref $FILES{$args{uri}} eq 'SCALAR')
        {
            $file = $FILES{$args{uri}};
        }
        else
        {
            $file = URI->new($args{uri})->file;
        }
    } ## end elsif (length $args{uri})

    if (length $args{line})
    {
        my $fh;
        if (ref $file eq 'SCALAR')
        {
            my $line     = $args{line};
            my $new_line = $/;

            my ($text) = $$file =~ /(?:[^$new_line]*$new_line){$line}([^$new_line]*)$new_line?/m;

            if (length $text)
            {
                $file = \$text;
                $self->{one_line} = 1;
            }
        } ## end if (ref $file eq 'SCALAR'...)
        elsif (open $fh, '<', $file)
        {
            my @text = <$fh>;

            if (length $text[$args{line}])
            {
                $file = \($text[$args{line}]);
                $self->{one_line} = 1;
            }
        } ## end elsif (open $fh, '<', $file...)
    } ## end if (length $args{line}...)

    my $document = PPI::Document->new($file, readonly => 1);
    return if (not blessed($document) or not $document->isa('PPI::Document'));

    $document->index_locations();

    return $document;
} ## end sub _get_ppi_document

=head2 _is_constant

Determines if a PPI element is a constant.

=cut

sub _is_constant
{
    my ($element) = @_;

    return unless $element->isa('PPI::Token::Word');
    return unless ref $_->snext_sibling eq 'PPI::Token::Operator';
    return $_->snext_sibling->content eq '=>';
} ## end sub _is_constant

=head2 find_word_under_cursor

Gets information about the current word under the cursor.
Returns a four-element list:

=over

=item The range where the word is located

=item A boolean indicating whether the word is before an arrow (->) or not.

=item The name of the package where the word is located

=item The word under the cursor to be used as a filter for searching

=back

=cut

sub find_word_under_cursor
{
    my ($self, $line, $character) = @_;

    my @elements = $self->find_elements_at_location($line, $character);
    @elements = map { $_->tokens } @elements;
    @elements =
      sort { (abs $character - $a->lsp_column_number) <=> (abs $character - $b->lsp_column_number) } @elements;
    my @in_range  = grep { $_->lsp_column_number <= $character and $_->lsp_column_number + length($_->content) >= $character } @elements;
    my $predicate = sub {
             $_->type eq 'PPI::Token::Word'
          or $_->type eq 'PPI::Token::Label'
          or $_->type eq 'PPI::Token::Symbol'
          or $_->type eq 'PPI::Token::Magic'
          or $_->type eq 'PPI::Token::Quote::Double'
          or $_->type eq 'PPI::Token::Quote::Interpolate'
          or $_->type eq 'PPI::Token::QuoteLike::Regexp'
          or $_->type eq 'PPI::Token::QuoteLike::Command'
          or $_->element->isa('PPI::Token::Regexp');
    };
    my $element          = first { $predicate->() or $_->type eq 'PPI::Token::Operator' } @in_range;
    my $closest_operator = first { $_->type eq 'PPI::Token::Operator' } grep { $_->lsp_column_number < $character } @elements;

    # Handle -X operators
    if (blessed($element) and $element->isa('PLS::Parser::Element') and $element->type eq 'PPI::Token::Operator')
    {
        if (
            # -X operators must be preceded by whitespace
            (not blessed($element->element->previous_sibling) or $element->element->previous_sibling->isa('PPI::Token::Whitespace'))

            # -X operators must not be subroutine declarations
            and (   not blessed($element->previous_sibling)
                 or not $element->previous_sibling->isa('PLS::Parser::Element')
                 or not $element->previous_sibling->element->isa('PPI::Token::Word')
                 or not $element->previous_sibling->name eq 'sub')
            and $element->content eq '-'
           )
        {
            return $element->range(), 0, '', '-';
        } ## end if ( (not blessed($element...)))

        undef $element;
    } ## end if (blessed($element) ...)

    $element = first { $predicate->() } @in_range;

    if (
            blessed($element)
        and $element->isa('PLS::Parser::Element')
        and (   $element->type eq 'PPI::Token::Quote::Double'
             or $element->type eq 'PPI::Token::Quote::Interpolate'
             or $element->type eq 'PPI::Token::QuoteLike::Regexp'
             or $element->type eq 'PPI::Token::QuoteLike::Command'
             or $element->element->isa('PPI::Token::Regexp'))
       )
    {
        my $string_start = $character - $element->range->{start}{character};
        my $string_end   = $character - $element->range->{end}{character};

        return if ($string_start <= 0);

        my $string = $element->name;

        if ($string =~ /^"/)
        {
            $string = substr $string, 1, -1;
        }
        elsif ($string =~ /^(q[qrx]|[ysm]|tr)(\S)/ or $string =~ m{^()(/)})
        {
            my $operator      = $1 // '';
            my $delimiter     = $2;
            my $end_delimiter = $delimiter;
            $end_delimiter = '}' if ($delimiter eq '{');
            $end_delimiter = ')' if ($delimiter eq '(');
            $end_delimiter = '>' if ($delimiter eq '<');
            $end_delimiter = ']' if ($delimiter eq '[');

            if ($string =~ /\Q$end_delimiter\E$/)
            {
                $string = substr $string, length($operator) + 1, -1;
            }
            else
            {
                $string = substr $string, length($operator) + 1;
            }
        } ## end elsif ($string =~ /^(q[qrx]|[ysm]|tr)(\S)/...)

        state $var_rx = qr/((?&PerlVariable)|[\$\@\%])$PPR::GRAMMAR$/;

        if ($string =~ /$var_rx/)
        {
            return {
                    start => {
                              line      => $line - 1,
                              character => $character - length $1
                             },
                    end => {
                            line      => $line - 1,
                            character => $character
                           }
                   },
              0, '', $1;
        } ## end if ($string =~ /$var_rx/...)

        undef $element;
    } ## end if (blessed($element) ...)

    if (not blessed($element) or not $element->isa('PLS::Parser::Element'))
    {
        # Let's see if PPI thinks that we're typing the start of a Regexp operator.
        my $regexp = first { $_->element->isa('PPI::Token::Regexp') } @elements;
        if (
            blessed($regexp)
            and (   $regexp->type eq 'PPI::Token::Regexp::Match' and $regexp->content eq 'm'
                 or $regexp->type eq 'PPI::Token::Regexp::Substitute'    and $regexp->content eq 's'
                 or $regexp->type eq 'PPI::Token::Regexp::Transliterate' and ($regexp->content eq 'tr' or $regexp->content eq 'y'))
           )
        {
            $element = $regexp;
        } ## end if (blessed($regexp) and...)
    } ## end if (not blessed($element...))

    if (not blessed($element) or not $element->isa('PLS::Parser::Element'))
    {
        # Let's see if PPI thinks that we're typing the start of a quote operator.
        my $literal     = first { $_->type eq 'PPI::Token::Quote::Literal' } @elements;
        my $interpolate = first { $_->type eq 'PPI::Token::Quote::Interpolate' } @elements;
        my $qr          = first { $_->type eq 'PPI::Token::QuoteLike::Regexp' } @elements;
        my $qw          = first { $_->type eq 'PPI::Token::QuoteLike::Words' } @elements;
        my $qx          = first { $_->type eq 'PPI::Token::QuoteLike::Command' } @elements;

        if (blessed($literal) and $literal->element->content eq 'q')
        {
            $element = $literal;
        }
        elsif (blessed($interpolate) and $interpolate->element->content eq 'qq')
        {
            $element = $interpolate;
        }
        elsif (blessed($qr) and $qr->element->content eq 'qr')
        {
            $element = $qr;
        }
        elsif (blessed($qw) and $qw->element->content eq 'qw')
        {
            $element = $qw;
        }
        elsif (blessed($qx) and $qx->element->content eq 'qx')
        {
            $element = $qx;
        }
    } ## end if (not blessed($element...))

    if (not blessed($element) or not $element->isa('PLS::Parser::Element'))
    {
        my $cast = first { $_->type eq 'PPI::Token::Cast' } @elements;

        # A cast probably means only a sigil was typed.
        if (blessed($cast) and $cast->isa('PLS::Parser::Element'))
        {
            return $cast->range, 0, '', $cast->name;
        }
    } ## end if (not blessed($element...))

    if (
        (
            not blessed($element)
         or not $element->isa('PLS::Parser::Element')
        )
        and blessed($closest_operator)
        and $closest_operator->isa('PLS::Parser::Element')
        and $closest_operator->name eq '->'
        and $closest_operator->lsp_column_number + length($closest_operator->content) == $character
       )
    {
        my $range = $closest_operator->range;
        $range->{start}{character} += length $closest_operator->content;
        $range->{end}{character} = $range->{start}{character};

        # If there is a word before the arrow AND it is not after another arrow, use it as the package name.
        # Otherwise, there is no package name, but there is an arrow and a blank filter.
        if (
                blessed($closest_operator->previous_sibling)
            and $closest_operator->previous_sibling->isa('PLS::Parser::Element')
            and $closest_operator->previous_sibling->type eq 'PPI::Token::Word'
            and (   not blessed($closest_operator->previous_sibling->element->previous_sibling)
                 or not $closest_operator->previous_sibling->element->previous_sibling->isa('PPI::Token::Operator')
                 or not $closest_operator->previous_sibling->element->previous_sibling eq '->')
           )
        {
            return $range, 1, $closest_operator->previous_sibling->name, '';
        } ## end if (blessed($closest_operator...))
        else
        {
            return $range, 1, '', '';
        }
    } ## end if ((not blessed($element...)))

    return if (not blessed($element) or not $element->isa('PLS::Parser::Element'));

    if ($element->type eq 'PPI::Token::Magic')
    {
        if ($element->name =~ /^[\$\@\%]/)
        {
            my $sigil = substr $element->name, 0, 1;
            my $range = $element->range;
            $range->{end}{character}--;
            return $range, 0, '', $sigil;
        } ## end if ($element->name =~ ...)

        return;
    } ## end if ($element->type eq ...)

    # If we're typing right before a sigil, return the previous element.
    if ($element->type eq 'PPI::Token::Symbol' and $element->lsp_column_number == $character and blessed($element->previous_sibling) and $element->previous_sibling->isa('PLS::Parser::Element'))
    {
        $element = $element->previous_sibling;
    }

    # Short-circuit if this is a HASH reference subscript.
    my $parent = $element->parent;
    $parent = $parent->parent if (blessed($parent) and ref $parent eq 'PLS::Parser::Element');
    return if ($element->type eq 'PPI::Token::Word' and blessed($parent) and $parent->isa('PLS::Parser::Element') and $parent->type eq 'PPI::Structure::Subscript');

    # if the cursor is on the word after an arrow, back up to the arrow so we can use any package information before it.
    if (    $element->type eq 'PPI::Token::Word'
        and blessed($element->previous_sibling)
        and $element->previous_sibling->isa('PLS::Parser::Element')
        and $element->previous_sibling->name eq '->')
    {
        $closest_operator = $element->previous_sibling;
    } ## end if ($element->type eq ...)

    if (    blessed($closest_operator)
        and $closest_operator->isa('PLS::Parser::Element')
        and $closest_operator->name eq '->'
        and $element->type eq 'PPI::Token::Word'
        and $element->parent->element == $closest_operator->parent->element)
    {
        # default to inserting after the arrow
        my $arrow_range = $closest_operator->range;
        my $range = {
                     start => $arrow_range->{end},
                     end   => $arrow_range->{end}
                    };

        my $filter = '';

        # if the next element is a word, it is likely the start of a method name,
        # so we want to return it as a filter. we also want the range to be that
        # of the next element so that we replace the word when it is selected.
        if (    blessed($closest_operator->next_sibling)
            and $closest_operator->next_sibling->isa('PLS::Parser::Element')
            and $closest_operator->next_sibling->type eq 'PPI::Token::Word'
            and $closest_operator->ppi_line_number == $closest_operator->next_sibling->ppi_line_number)
        {
            $filter = $closest_operator->next_sibling->name;
            $range  = $closest_operator->next_sibling->range;
        } ## end if (blessed($closest_operator...))

        # if the previous element is a word, it's possibly a class name,
        # so we return that to use for searching for that class's methods.
        my $package = '';

        if (
                blessed($closest_operator->previous_sibling)
            and $closest_operator->previous_sibling->isa('PLS::Parser::Element')
            and $closest_operator->previous_sibling->type eq 'PPI::Token::Word'
            and (   not blessed($closest_operator->previous_sibling->previous_sibling)
                 or not $closest_operator->previous_sibling->previous_sibling->isa('PLS::Parser::Element')
                 or $closest_operator->previous_sibling->previous_sibling->name ne '->')
           )
        {
            $package = $closest_operator->previous_sibling->name;
        } ## end if (blessed($closest_operator...))

        # the 1 indicates that the current token is an arrow, due to the special logic needed.
        return $range, 1, $package, $filter;
    } ## end if (blessed($closest_operator...))

    # This handles the case for when there is an arrow after a variable name
    # but the user has not yet started typing the method name.
    if (    blessed($closest_operator)
        and $closest_operator->isa('PLS::Parser::Element')
        and $closest_operator->name eq '->'
        and blessed($closest_operator->previous_sibling)
        and $closest_operator->previous_sibling->isa('PLS::Parser::Element')
        and $closest_operator->previous_sibling->element == $element->element)
    {
        my $arrow_range = $closest_operator->range;
        my $range = {
                     start => $arrow_range->{end},
                     end   => $arrow_range->{end}
                    };

        return $range, 1, '', '';
    } ## end if (blessed($closest_operator...))

    # something like "Package::Name:", we just want Package::Name.
    if (
            $element->name eq ':'
        and blessed($element->previous_sibling)
        and $element->previous_sibling->isa('PLS::Parser::Element')
        and (   $element->previous_sibling->type eq 'PPI::Token::Word'
             or $element->previous_sibling->type eq 'PPI::Token::Label')

        # Check that there isn't another arrow before the previous word - in this case the previous word is likely NOT a package name.
        and (   not blessed($element->previous_sibling->previous_sibling)
             or not $element->previous_sibling->previous_sibling->isa('PLS::Parser::Element')
             or $element->previous_sibling->previous_sibling->name ne '->')
       )
    {
        $element = $element->previous_sibling;
    } ## end if ($element->name eq ...)

    my $range = $element->range;

    # look at labels as well, because a label looks like a package name before the second colon.
    my $package = '';

    if (   $element->type eq 'PPI::Token::Word'
        or $element->type eq 'PPI::Token::Label'
        or $element->element->isa('PPI::Token::Quote')
        or $element->element->isa('PPI::Token::QuoteLike')
        or $element->element->isa('PPI::Token::Regexp'))
    {
        $package = $element->name;
    } ## end if ($element->type eq ...)

    # Don't suggest anything when this is a subroutine declaration.
    return if (    blessed($element->parent)
               and $element->parent->isa('PLS::Parser::Element')
               and $element->parent->element->isa('PPI::Statement::Sub'));

    my $name = $element->name;
    $name =~ s/:?:$//;

    return $range, 0, $package, $name;
} ## end sub find_word_under_cursor

=head2 get_list_index

Gets the index within a list where a cursor is.

This is useful for determining which function parameter the cursor is on
within a function call.

=cut

sub get_list_index
{
    my ($self, $list, $line, $character) = @_;

    return 0 if (not blessed($list) or not $list->isa('PLS::Parser::Element') or $list->type ne 'PPI::Structure::List');

    my $find = PPI::Find->new(sub { $_[0]->isa('PPI::Statement::Expression') });
    my $expr;
    $expr = $find->match() if $find->start($list->element);

    return 0 if (not blessed($expr) or not $expr->isa('PPI::Statement::Expression'));

    my @commas = grep { $_->isa('PPI::Token::Operator') and $_ eq ',' } $expr->schildren;

    return 0 unless (scalar @commas);

    my $param_index = -1;

    foreach my $index (reverse 0 .. $#commas)
    {
        my $param = $commas[$index];

        if ($param->column_number <= $character)
        {
            $param_index = $index;
            last;
        }
    } ## end foreach my $index (reverse ...)

    return $param_index + 1;
} ## end sub get_list_index

=head2 sort_imports

This sorts the imports within a file. The order is:

=over

=item C<use strict> and C<use warnings>

=item C<use parent> and C<use base>

=item Other pragmas (excluding C<use constant>)

=item Core and external imports

=item Internal imports (from the current project)

=item Constants (C<use constant>)

=back

=cut

sub sort_imports
{
    my ($self) = @_;

    my $doc       = $self->{document}->clone();
    my @installed = ExtUtils::Installed->new->modules;

    # Just strict and warnings - I like them to be first and in their own group
    my @special_pragmas;

    # parent and base - I like them to be after strict and warnings and in their own group.
    my @isa_pragmas;

    # The rest of the pragmas
    my @pragmas;

    # Group of any modules that are installed (either core or external)
    my @installed_modules;

    # Group of modules that are part of this project,
    # though it gets tricky if this project is also installed
    my @internal_modules;

    # Put constant pragmas at the very end of all imports
    my @constant_pragmas;

    my $insert_after;

    foreach my $child ($doc->children)
    {
        my $seqno;
        next unless ($seqno = ($child->isa('PPI::Statement::Include') .. (not $child->isa('PPI::Statement::Include') and not $child->isa('PPI::Token::Whitespace'))));
        last                                     if ($seqno =~ /E0/);
        $insert_after = $child->previous_sibling if ($seqno eq '1');

        if ($child->isa('PPI::Token::Whitespace'))
        {
            $child->delete;
            next;
        }

        if ($child->pragma eq 'strict' or $child->pragma eq 'warnings')
        {
            push @special_pragmas, $child;
        }
        elsif ($child->pragma eq 'parent' or $child->pragma eq 'base')
        {
            push @isa_pragmas, $child;
        }
        elsif ($child->pragma eq 'constant')
        {
            push @constant_pragmas, $child;
        }
        elsif (length $child->pragma)
        {
            push @pragmas, $child;
        }
        else
        {
            if (Module::CoreList::is_core($child->module) or any { $child->module =~ /^\Q$_\E/ } @installed)
            {
                push @installed_modules, $child;
            }
            else
            {
                push @internal_modules, $child;
            }
        } ## end else [ if ($child->pragma eq ...)]

        $child->remove;
    } ## end foreach my $child ($doc->children...)

    @special_pragmas   = _pad_imports(sort _sort_imports @special_pragmas)   if (scalar @special_pragmas);
    @isa_pragmas       = _pad_imports(sort _sort_imports @isa_pragmas)       if (scalar @isa_pragmas);
    @pragmas           = _pad_imports(sort _sort_imports @pragmas)           if (scalar @pragmas);
    @installed_modules = _pad_imports(sort _sort_imports @installed_modules) if (scalar @installed_modules);
    @internal_modules  = _pad_imports(sort _sort_imports @internal_modules)  if (scalar @internal_modules);
    @constant_pragmas  = _pad_imports(sort _sort_imports @constant_pragmas)  if (scalar @constant_pragmas);

    # There doesn't seem to be a better way to do this other than to use this private method.
    $insert_after->__insert_after(@special_pragmas, @isa_pragmas, @pragmas, @installed_modules, @internal_modules, @constant_pragmas);

    open my $fh, '<', $self->get_full_text();

    my $lines;

    while (my $line = <$fh>)
    {
        $lines = $.;
    }

    return \($doc->serialize), $lines;
} ## end sub sort_imports

=head2 _sort_imports

Determines the sorting of two imports within a block of imports.

=cut

sub _sort_imports
{
    return $b->type cmp $a->type || $a->module cmp $b->module;
}

=head2 _pad_imports

Adds newlines to pad the various import sections from each other and from
the rest of the document.

=cut

sub _pad_imports
{
    my @imports = @_;

    # Newlines between the imports
    @imports = map { $_, PPI::Token::Whitespace->new("\n") } @imports;

    # An extra newline at the end of the section
    push @imports, PPI::Token::Whitespace->new("\n");

    return @imports;
} ## end sub _pad_imports

=head2 _split_lines

Splits a document into lines using C<$/> as the separator.

=cut

sub _split_lines
{
    my ($text) = @_;

    my $sep = $/;
    return split /(?<=$sep)/, $text;
} ## end sub _split_lines

1;
