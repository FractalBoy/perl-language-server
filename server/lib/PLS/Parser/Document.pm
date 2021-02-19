package PLS::Parser::Document;

use strict;
use warnings;

use Perl::Critic::Utils;
use Perl::Tidy;
use PPI;
use PPI::Find;
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
    my ($class, @args) = @_;

    my %args = @args;

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
    $INDEX = PLS::Parser::Index->new(root => $PLS::Server::State::ROOT_PATH)
      unless (ref $INDEX eq 'PLS::Parser::Index');

    my ($document, $text);

    if (ref $args{text} eq 'SCALAR')
    {
        $document = PPI::Document->new($args{text});
        $text     = $args{text};
    }
    else
    {
        ($document, $text) = _document_from_uri($uri);
    }

    return unless (ref $document eq 'PPI::Document');

    my %self = (
                path     => $path,
                document => $document,
                text     => $text,
                index    => $INDEX
               );

    return bless \%self, $class;
} ## end sub new

sub set_index
{
    my ($class, $index) = @_;

    $INDEX = $index;
}

sub go_to_definition
{
    my ($self, $line_number, $column_number) = @_;

    my @matches = $self->find_elements_at_location($line_number, $column_number);

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
        if (my $package = $match->package_name())
        {
            return $self->{index}->find_package($package);
        }
    } ## end foreach my $match (@matches...)

    return;
} ## end sub go_to_definition

sub find_pod
{
    my ($self, $line_number, $column_number) = @_;

    my @elements = $self->find_elements_at_location($line_number, $column_number);

    foreach my $element (@elements)
    {
        my ($package, $subroutine, $variable);

        if (($package, $subroutine) = $element->subroutine_package_and_name())
        {
            my $pod =
              PLS::Parser::Pod::Subroutine->new(
                                                document   => $self,
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
                                                 document   => $self,
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
                                            document   => $self,
                                            element    => $element,
                                            subroutine => $subroutine
                                           );
            my $ok = $pod->find();
            return (1, $pod) if $ok;
        } ## end if ($subroutine = $element...)
        if ($package = $element->package_name())
        {
            my $pod =
              PLS::Parser::Pod::Package->new(
                                             document => $self,
                                             element  => $element,
                                             package  => $package
                                            );
            my $ok = $pod->find();
            return (1, $pod) if $ok;
        } ## end if ($package = $element...)
        if ($variable = $element->variable_name())
        {
            my $pod =
              PLS::Parser::Pod::Variable->new(
                                              document => $self->{document},
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
        my $range = $subroutine->range();
        return {
                uri       => URI::file->new($package->filename)->as_string,
                range     => $subroutine->range(),
                signature => $subroutine->location_info->{signature}
               };
    } ## end foreach my $subroutine (@{$doc...})
} ## end sub find_external_subroutine

sub open_file
{
    my ($class, @args) = @_;

    my %args = @args;

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
            $starting_text = substr $lines[$change->{range}{start}{line}], 0, $change->{range}{start}{character} if ($#lines >= $change->{range}{start}{line});
            $ending_text   = substr $lines[$change->{range}{end}{line}],   $change->{range}{end}{character} if ($#lines >= $change->{range}{end}{line});

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

sub format_range
{
    my ($self, @args) = @_;

    my %args = @args;
    $args{formatting_options} = {} unless (ref $args{formatting_options} eq 'HASH');
    my $range = $args{range};

    if (ref $self->{text} ne 'SCALAR' or not length ${$self->{text}})
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

        my @lines = _split_lines(${$self->{text}});
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
        $selection  = ${$self->{text}};
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
    my $perltidyrc = glob($PLS::Server::State::CONFIG{perltidyrc} // '~/.perltidyrc');
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
    if ($error == 2)
    {
        return (
                0,
                {
                 code    => -32700,
                 message => 'There were warnings or errors when running Perltidy. Formatting aborted.',
                 data    => $stderr
                }
               );
    } ## end if ($error == 2)
    if (length $stderr)
    {
        return (
                0,
                {
                 code    => -32001,
                 message => 'Unknown error. View the details below to determine the source of the error.',
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
    my ($self, $formatting_options) = @_;

    return $self->format_range(formatting_options => $formatting_options);
}

sub _ppi_location
{
    my ($line_number, $column_number) = @_;

    return ++$line_number, ++$column_number;
}

sub _document_from_uri
{
    my ($uri) = @_;

    my ($document, $text);

    if (ref $FILES{$uri} eq 'HASH')
    {
        $text     = $FILES{$uri}{text};
        $document = PPI::Document->new(\$text);
    }
    else
    {
        my $file = URI->new($uri);
        open my $fh, '<', $file->file or return ('', \'');
        $text     = do { local $/; <$fh> };
        $document = PPI::Document->new($file->file);
    } ## end else [ if (ref $FILES{$uri} eq...)]

    return '' unless (ref $document eq 'PPI::Document');
    $document->index_locations;
    return ($document, \$text);
} ## end sub _document_from_uri

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
    @elements = map  { $_->tokens } @elements;
    @elements = grep { $_->{ppi_element}->significant } @elements;
    my $element = $elements[0];
    return unless (ref $element eq 'PLS::Parser::Element');

    # if the cursor is on the word after an arrow, back up to the arrow so we can use any package information before it.
    if ($element->{ppi_element}->isa('PPI::Token::Word') and ref $element->previous_sibling eq 'PLS::Parser::Element' and $element->previous_sibling->name eq '->')
    {
        $element = $element->previous_sibling;
    }

    if ($element->name eq '->')
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
        if (    ref $element->next_sibling eq 'PLS::Parser::Element'
            and $element->next_sibling->{ppi_element}->isa('PPI::Token::Word')
            and $element->ppi_line_number == $element->next_sibling->ppi_line_number)
        {
            $filter = $element->next_sibling->name;
            $range  = $element->next_sibling->range;
        } ## end if (ref $element->next_sibling...)

        # if the previous element is a word, it's possibly a class name,
        # so we return that to use for searching for that class's methods.
        my $package = '';
        if (ref $element->previous_sibling eq 'PLS::Parser::Element' and $element->previous_sibling->{ppi_element}->isa('PPI::Token::Word'))
        {
            $package = $element->previous_sibling->name;
        }

        # the 1 indicates that the current token is an arrow, due to the special logic needed.
        return $range, 1, $package, $filter;
    } ## end if ($element->name eq ...)

    # modify the range so we don't overwrite anything after the cursor.
    my $range = $element->range;
    $range->{end}{character} = $character;

    # look at labels as well, because a label looks like a package name before the second colon.
    my $package = ($element->{ppi_element}->isa('PPI::Token::Word') or $element->{ppi_element}->isa('PPI::Token::Label')) ? $element->name : '';
    my $name    = $element->name;

    return $range, 0, $package, $name;
} ## end sub find_word_under_cursor

sub _split_lines
{
    my ($text) = @_;

    my $sep = $/;
    return split /(?<=$sep)/, $text;
} ## end sub _split_lines

1;
