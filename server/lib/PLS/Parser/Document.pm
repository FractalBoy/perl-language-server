package PLS::Parser::Document;

use strict;
use warnings;

use feature 'isa';
no warnings 'experimental::isa';

use List::Util qw(first);
use Perl::Tidy;
use PPI;
use PPI::Find;
use PPR;
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
my $INDEX;

sub new
{
    my ($class, %args) = @_;

    my ($path, $uri);

    if (length $args{uri})
    {
        $path = URI->new($args{uri})->file;
        $uri  = $args{uri};
    }
    elsif (length $args{path})
    {
        $path = $args{path};
        $uri  = URI::file->new($path)->as_string;
    }

    return unless (length $path and length $uri);

    my $self = bless {
                      path  => $path,
                      uri   => $uri,
                      index => $INDEX
                     }, $class;

    $self->get_index();
    my $document = $self->_get_ppi_document(%args);
    return unless (ref $document eq 'PPI::Document');
    $self->{document} = $document;

    return $self;
} ## end sub new

sub set_index
{
    my ($class, $index) = @_;

    $INDEX = $index;
}

sub get_index
{
    my ($class) = @_;

    $INDEX = PLS::Parser::Index->new(root => $PLS::Server::State::ROOT_PATH) unless (ref $INDEX eq 'PLS::Parser::Index');
    return $INDEX;
} ## end sub get_index

sub go_to_definition
{
    my ($self, $line_number, $column_number) = @_;

    my @matches = $self->find_elements_at_location($line_number, $column_number);

    return $self->search_elements_for_definition($line_number, $column_number, @matches);
} ## end sub go_to_definition

sub find_current_list
{
    my ($self, $line_number, $column_number) = @_;

    my @elements = $self->find_elements_at_location($line_number, $column_number);
    my $find     = PPI::Find->new(sub { $_[0]->isa('PPI::Structure::List') });

    # Find the nearest list structure that completely surrounds the column.
    return first { $_->lsp_column_number < $column_number < $_->lsp_column_number + length($_->content) }
    sort  { abs($column_number - $a->lsp_column_number) - abs($column_number - $b->lsp_column_number) }
      map { PLS::Parser::Element->new(element => $_, document => $self->{document}, file => $self->{path}) }
      map { $find->in($_->{ppi_element}) } @elements;
} ## end sub find_current_list

sub go_to_definition_of_closest_subroutine
{
    my ($self, $list, $line_number, $column_number) = @_;

    return unless ($list isa 'PLS::Parser::Element' and $list->{ppi_element} isa 'PPI::Structure::List');

    # Try to find the closest word before the list - this is the function name.
    my $word = $list;

    while ($word isa 'PLS::Parser::Element' and not $word->{ppi_element} isa 'PPI::Token::Word')
    {
        $word = $word->previous_sibling;
    }

    return unless ($word->{ppi_element} isa 'PPI::Token::Word');
    return $self->search_elements_for_definition($line_number, $column_number, $word);
} ## end sub go_to_definition_of_closest_subroutine

sub search_elements_for_definition
{
    my ($self, $line_number, $column_number, @matches) = @_;

    foreach my $match (@matches)
    {
        if (my ($package, $subroutine) = $match->subroutine_package_and_name())
        {
            if ($match->cursor_on_package($column_number))
            {
                return $self->{index}->find_package($package);
            }

            if (length $package)
            {
                my $results = $self->{index}->find_package_subroutine($package, $subroutine);
                return $results if (ref $results eq 'ARRAY' and scalar @$results);

                my $external = $self->find_external_subroutine($package, $subroutine);
                return [$external] if (ref $external eq 'HASH');
                return [];
            } ## end if (length $package)

            return $self->{index}->find_subroutine($subroutine);
        } ## end if (my ($package, $subroutine...))
        if (my ($class, $method) = $match->class_method_package_and_name())
        {
            my $results = $self->{index}->find_package_subroutine($class, $method);

            # fall back to treating as a method instead of class method
            return $results if (ref $results eq 'ARRAY' and scalar @$results);

            my $external = $self->find_external_subroutine($class, $method);
            return [$external] if (ref $external eq 'HASH');
        } ## end if (my ($class, $method...))
        if (my $method = $match->method_name())
        {
            $method =~ s/SUPER:://;
            return $self->{index}->find_subroutine($method);
        }
        if (my ($package, $import) = $match->package_name($column_number))
        {
            if (length $import)
            {
                return $self->{index}->find_package_subroutine($package, $import);
            }
            else
            {
                return $self->{index}->find_package($package);
            }
        } ## end if (my ($package, $import...))
    } ## end foreach my $match (@matches...)

    # If all else fails, see if we're on a POD link.
    if (my $link = $self->pod_link($line_number, $column_number))
    {
        my $package = $self->{index}->find_package($link);
        return $package if (ref $package eq 'ARRAY' and scalar @{$package});

        my @pieces          = split /::/, $link;
        my $subroutine_name = pop @pieces;
        my $package_name    = join '::', @pieces;
        return $self->{index}->find_package_subroutine($package_name, $subroutine_name) if (length $package_name);

        return $self->{index}->find_subroutine($subroutine_name);
    } ## end if (my $link = $self->...)

    return;
} ## end sub search_elements_for_definition

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

            next unless ($start <= $column_number <= $end);

            # Get just the name - remove the text and section parts
            $link =~ s/^[^<]*\|//;
            $link =~ s/\/[^>]*$//;
            return $link;
        } ## end while ($line =~ m{ ) (})

        last;
    } ## end while (my $line = <$fh>)

    return;
} ## end sub pod_link

sub find_pod
{
    my ($self, $line_number, $column_number) = @_;

    my @elements = $self->find_elements_at_location($line_number, $column_number);

    foreach my $element (@elements)
    {
        my ($package, $subroutine, $variable, $import);

        if (($package, $subroutine) = $element->subroutine_package_and_name())
        {
            my $pod =
              PLS::Parser::Pod::Subroutine->new(
                                                index      => $self->{index},
                                                element    => $element,
                                                package    => $package,
                                                subroutine => $subroutine
                                               );
            my $ok = $pod->find();
            return (1, $pod) if $ok;
        } ## end if (($package, $subroutine...))
        if (($package, $subroutine) = $element->class_method_package_and_name())
        {
            my $pod =
              PLS::Parser::Pod::ClassMethod->new(
                                                 index      => $self->{index},
                                                 element    => $element,
                                                 package    => $package,
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
                    $class_name = 'PLS::Parser::Pod::Subroutine';
                }
            } ## end if (length $import)

            my $pod = $class_name->new(%args);
            my $ok  = $pod->find();
            return (1, $pod) if $ok;
        } ## end if (($package, $import...))
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

sub find_external_subroutine
{
    my ($self, $package_name, $subroutine_name) = @_;

    my $include = PLS::Parser::Pod->get_clean_inc();
    my $package = Module::Metadata->new_from_module($package_name, inc => $include);
    return unless (ref $package eq 'Module::Metadata');

    my $doc = PLS::Parser::Document->new(path => $package->filename);
    return unless (ref $doc eq 'PLS::Parser::Document');

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

sub find_external_package
{
    my ($self, $package_name) = @_;

    return unless (length $package_name);

    my $include  = PLS::Parser::Pod->get_clean_inc();
    my $metadata = Module::Metadata->new_from_module($package_name, inc => $include);

    return unless (ref $metadata eq 'Module::Metadata');

    my $document = PLS::Parser::Document->new(path => $metadata->filename);
    return unless (ref $document eq 'PLS::Parser::Document');

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

sub open_file
{
    my ($class, %args) = @_;

    return unless $args{languageId} eq 'perl';

    $FILES{$args{uri}} = {text => $args{text}};

    return;
} ## end sub open_file

sub update_file
{
    my ($class, @args) = @_;

    my %args = @args;

    my $file = $FILES{$args{uri}};
    return unless (ref $file eq 'HASH');

    foreach my $change (@{$args{changes}})
    {
        if (ref $change->{range} eq 'HASH')
        {
            my @lines       = _split_lines($file->{text});
            my @replacement = _split_lines($change->{text});

            my ($starting_text, $ending_text);

            # get the text that we're not replacing at the start and end of each selection
            $starting_text = substr $lines[$change->{range}{start}{line}], 0, $change->{range}{start}{character}
              if ($#lines >= $change->{range}{start}{line});
            $ending_text = substr $lines[$change->{range}{end}{line}], $change->{range}{end}{character} if ($#lines >= $change->{range}{end}{line});

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
            $file->{text} = join '', @lines;
        } ## end if (ref $change->{range...})
        else
        {
            # no range means we're updating the entire document
            $file->{text} = $change->{text};
        }
    } ## end foreach my $change (@{$args...})

    return;
} ## end sub update_file

sub close_file
{
    my ($class, @args) = @_;

    my %args = @args;

    delete $FILES{$args{uri}};
} ## end sub close_file

sub get_subroutines
{
    my ($self) = @_;

    my $find = PPI::Find->new(
        sub {
            $_[0]->isa('PPI::Statement::Sub') and not $_[0]->isa('PPI::Statement::Scheduled');
        }
    );
    return [map { PLS::Parser::Element::Subroutine->new(document => $self->{document}, element => $_, file => $self->{path}) } $find->in($self->{document})];
} ## end sub get_subroutines

sub get_constants
{
    my ($self) = @_;

    my $find = PPI::Find->new(
        sub {
            my ($element) = @_;

            return 0 unless $element->isa('PPI::Statement::Include');
            return   unless $element->type eq 'use';
            return (length $element->module and $element->module eq 'constant');
        }
    );

    my @matches = $find->in($self->{document});
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

sub get_packages
{
    my ($self) = @_;

    my $find = PPI::Find->new(sub { $_[0]->isa('PPI::Statement::Package') });
    return [map { PLS::Parser::Element::Package->new(document => $self->{document}, element => $_, file => $self->{path}) } $find->in($self->{document})];
} ## end sub get_packages

sub get_variable_statements
{
    my ($self) = @_;

    my $find = PPI::Find->new(sub { $_[0]->isa('PPI::Statement::Variable') });
    return [map { PLS::Parser::Element::VariableStatement->new(document => $self->{document}, element => $_, file => $self->{path}) } $find->in($self->{document})];
} ## end sub get_variable_statements

sub get_full_text
{
    my ($self) = @_;

    return _text_from_uri($self->{uri});
}

sub get_variables_fast
{
    my ($self, $text) = @_;

    $text = $self->get_full_text() unless (ref $text eq 'SCALAR');
    return []                      unless (ref $text eq 'SCALAR');

    my @variable_declarations = $$text =~ /((?&PerlVariableDeclaration))$PPR::GRAMMAR/gx;
    @variable_declarations = grep { defined } @variable_declarations;

    # Precompile regex used multiple times
    my $re = qr/((?&PerlVariable))$PPR::GRAMMAR/x;

    return [
            map { s/^\s+|\s+$//r }
            grep { defined } map { /$re/g } @variable_declarations
           ];
} ## end sub get_variables_fast

sub get_packages_fast
{
    my ($self, $text) = @_;

    $text = $self->get_full_text() unless (ref $text eq 'SCALAR');
    return []                      unless (ref $text eq 'SCALAR');

    my @package_declarations = $$text =~ /((?&PerlPackageDeclaration))$PPR::GRAMMAR/gx;
    @package_declarations = grep { defined } @package_declarations;

    # Precompile regex used multiple times
    my $re = qr/((?&PerlQualifiedIdentifier))$PPR::GRAMMAR/x;

    return [
            map { s/^\s+|\s+$//r }
            grep { defined } map { /$re/g } @package_declarations
           ];
} ## end sub get_packages_fast

sub get_subroutines_fast
{
    my ($self, $text) = @_;

    $text = $self->get_full_text() unless (ref $text eq 'SCALAR');
    return []                      unless (ref $text eq 'SCALAR');

    my @subroutine_declarations = $$text =~ /sub\b(?&PerlOWS)((?&PerlOldQualifiedIdentifier))$PPR::GRAMMAR/gx;

    return [
            map  { s/^\s+|\s+$//r }
            grep { defined } @subroutine_declarations
           ];
} ## end sub get_subroutines_fast

sub get_constants_fast
{
    my ($self, $text) = @_;

    $text = $self->get_full_text() unless (ref $text eq 'SCALAR');
    return []                      unless (ref $text eq 'SCALAR');

    my @use_statements = $$text =~ /((?&PerlUseStatement)) $PPR::GRAMMAR/gx;
    @use_statements = grep { defined } @use_statements;

    # Precompile regex used multiple times
    my $block_re    = qr/constant (?&PerlOWS) ((?&PerlBlock)) $PPR::GRAMMAR/x;
    my $bareword_re = qr/((?&PerlBareword)) (?&PerlOWS) (?&PerlComma) $PPR::GRAMMAR/x;

    return [
            map  { s/^\s+|\s+$//r }
            grep { defined } map { /$bareword_re/g }
            grep { defined } map { /$block_re/g } @use_statements
           ];
} ## end sub get_constants_fast

sub format_range
{
    my ($class, %args) = @_;

    $args{formatting_options} = {} unless (ref $args{formatting_options} eq 'HASH');
    my $range = $args{range};

    my $text = _text_from_uri($args{uri});

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
    my $perltidyrc = glob($PLS::Server::State::CONFIG->{perltidyrc} // '~/.perltidyrc');
    my $error      = Perl::Tidy::perltidy(source => \$selection, destination => \$formatted, stderr => \$stderr, perltidyrc => $perltidyrc, argv => $argv);

    # get the number of lines in the formatted result - we need to modify the range if
    # any lines were added
    my $lines = () = $formatted =~ m{($/)}g;
    $lines++;

    # if the selection length has increased due to formatting, update the end.
    $range->{end}{line} = $lines if ($whole_file and $lines > $range->{end}{line});

    $formatted =~ s/\s+$//gm if ($args{formatting_options}{trimTrailingWhitespace});

    if ($args{formatting_options}{insertFinalNewline})
    {
        $formatted .= "\n" unless ($formatted =~ /\n$/);
    }
    elsif ($args{formatting_options}{trimFinalNewlines})
    {
        $formatted =~ s/\n+$//;
    }

    $stderr =~ s/^<source_stream>:\s*//gm;
    $stderr =~ s/^Begin Error Output Stream.*$//m;
    $stderr =~ s/^.*To save a full \.LOG file.*$//m;
    $stderr =~ s/^\s*$//gm;

    if ($error == 1)
    {
        return (0, {code => -32700, message => 'Perltidy failed to format the text.', data => $stderr});
    }
    if (length $stderr)
    {
        return (
                0,
                {
                 code    => -32700,
                 message => 'There were warnings or errors when running Perltidy. Formatting aborted.',
                 data    => $stderr
                }
               );
    } ## end if (length $stderr)

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

sub format
{
    my ($class, %args) = @_;

    return $class->format_range(formatting_options => $args{formatting_options}, uri => $args{uri});
}

sub _ppi_location
{
    my ($line_number, $column_number) = @_;

    return ++$line_number, ++$column_number;
}

sub _text_from_uri
{
    my ($uri) = @_;

    if (ref $FILES{$uri} eq 'HASH')
    {
        return \($FILES{$uri}{text});
    }
    else
    {
        my $file = URI->new($uri);
        open my $fh, '<', $file->file or return;
        my $text = do { local $/; <$fh> };
        return \$text;
    } ## end else [ if (ref $FILES{$uri} eq...)]
} ## end sub _text_from_uri

sub _get_ppi_document
{
    my ($self, %args) = @_;

    my $file;

    if (length $args{uri})
    {
        if (ref $FILES{$args{uri}} eq 'HASH')
        {
            $file = \($FILES{$args{uri}}{text});
        }
        else
        {
            $file = URI->new($args{uri})->file;
        }
    } ## end if (length $args{uri})
    elsif ($args{text})
    {
        $file = $args{text};
    }

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
    return unless (ref $document eq 'PPI::Document');
    $document->index_locations();
    return $document;
} ## end sub _get_ppi_document

sub _is_constant
{
    my ($element) = @_;

    return unless $element->isa('PPI::Token::Word');
    return unless ref $_->snext_sibling eq 'PPI::Token::Operator';
    return $_->snext_sibling->content eq '=>';
} ## end sub _is_constant

sub find_word_under_cursor
{
    my ($self, $line, $character) = @_;

    my @elements = $self->find_elements_at_location($line, $character);
    @elements = map { $_->tokens } @elements;
    my $element          = first { $_->{ppi_element}->isa('PPI::Token::Word') or $_->{ppi_element}->isa('PPI::Token::Label') or $_->{ppi_element}->isa('PPI::Token::Symbol') } @elements;
    my $closest_operator = first { $_->{ppi_element}->isa('PPI::Token::Operator') } @elements;
    return unless ($element isa 'PLS::Parser::Element');

    # Short-circuit if this is a HASH reference subscript.
    my $parent = $element->parent;
    $parent = $parent->parent if ($parent isa 'PLS::Parser::Element');
    return if ($element->{ppi_element} isa 'PPI::Token::Word' and $parent isa 'PLS::Parser::Element' and $parent->{ppi_element}->isa('PPI::Structure::Subscript'));

    # if the cursor is on the word after an arrow, back up to the arrow so we can use any package information before it.
    if (    $element->{ppi_element}->isa('PPI::Token::Word')
        and $element->previous_sibling isa 'PLS::Parser::Element'
        and $element->previous_sibling->name eq '->')
    {
        $closest_operator = $element->previous_sibling;
    } ## end if ($element->{ppi_element...})

    if ($closest_operator isa 'PLS::Parser::Element' and $closest_operator->name eq '->' and $element->{ppi_element} isa 'PPI::Token::Word')
    {
        # default to inserting after the arrow
        my $arrow_range = $element->range;
        my $range = {
                     start => $arrow_range->{end},
                     end   => $arrow_range->{end}
                    };

        my $filter = '';

        # if the next element is a word, it is likely the start of a method name,
        # so we want to return it as a filter. we also want the range to be that
        # of the next element so that we replace the word when it is selected.
        if (    ref $closest_operator->next_sibling eq 'PLS::Parser::Element'
            and $closest_operator->next_sibling->{ppi_element}->isa('PPI::Token::Word')
            and $closest_operator->ppi_line_number == $closest_operator->next_sibling->ppi_line_number)
        {
            $filter = $closest_operator->next_sibling->name;
            $range  = $closest_operator->next_sibling->range;
        } ## end if (ref $closest_operator...)

        # if the previous element is a word, it's possibly a class name,
        # so we return that to use for searching for that class's methods.
        my $package = '';
        if (ref $closest_operator->previous_sibling eq 'PLS::Parser::Element' and $closest_operator->previous_sibling->{ppi_element}->isa('PPI::Token::Word'))
        {
            $package = $closest_operator->previous_sibling->name;
        }

        # the 1 indicates that the current token is an arrow, due to the special logic needed.
        return $range, 1, $package, $filter;
    } ## end if ($closest_operator ...)

    # something like "Package::Name:", we just want Package::Name.
    if (
            $element->name eq ':'
        and ref $element->previous_sibling eq 'PLS::Parser::Element'
        and (   $element->previous_sibling->{ppi_element}->isa('PPI::Token::Word')
             or $element->previous_sibling->{ppi_element}->isa('PPI::Token::Label'))
       )
    {
        $element = $element->previous_sibling;
    } ## end if ($element->name eq ...)

    # modify the range so we don't overwrite anything after the cursor.
    my $range = $element->range;
    $range->{end}{character} = $character;

    # look at labels as well, because a label looks like a package name before the second colon.
    my $package = '';

    if (   $element->{ppi_element}->isa('PPI::Token::Word')
        or $element->{ppi_element}->isa('PPI::Token::Label'))
    {
        $package = $element->name;
    }

    my $name = $element->name;
    $name =~ s/:?:$//;

    return $range, 0, $package, $name;
} ## end sub find_word_under_cursor

sub get_list_index
{
    my ($self, $list, $line, $character) = @_;

    return 0 unless ($list isa 'PLS::Parser::Element' and $list->{ppi_element} isa 'PPI::Structure::List');

    my $find = PPI::Find->new(sub { $_[0] isa 'PPI::Statement::Expression' });
    my $expr;
    $expr = $find->match() if $find->start($list->{ppi_element});

    return 0 unless ($expr isa 'PPI::Statement::Expression');

    my @commas = grep { $_ isa 'PPI::Token::Operator' and $_ eq ',' } $expr->schildren;

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

sub _split_lines
{
    my ($text) = @_;

    my $sep = $/;
    return split /(?<=$sep)/, $text;
} ## end sub _split_lines

1;
