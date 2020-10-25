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
                return $self->{index}->find_package_subroutine($package, $subroutine);
            }

            return $self->{index}->find_subroutine($subroutine);
        } ## end if (my ($package, $subroutine...))
        if (my ($class, $method) = $match->class_method_package_and_name())
        {
            my $results = $self->{index}->find_package_subroutine($class, $method);

            # fall back to treating as a method instead of class method
            return $results if (ref $results eq 'ARRAY' and scalar @$results);
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

sub open_file
{
    my ($class, @args) = @_;

    my %args = @args;

    return unless $args{languageId} eq 'perl';

    $FILES{$args{uri}} = {
                          version => $args{version},
                          text    => $args{text}
                         };

    return;
} ## end sub open_file

sub update_file
{
    my ($class, @args) = @_;

    my %args = @args;

    my $file = $FILES{$args{uri}};
    return unless (ref $file eq 'HASH');
    return if $args{version} <= $file->{version};
    $file->{text} = $args{text};
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

    if (not ref $self->{text} eq 'SCALAR' or not length ${$self->{text}})
    {
        return (0, {code => -32700, message => 'Could not get document text.'});
    }

    my @lines = split /\n/, ${$self->{text}};

    # the amount of padding on the first line that is not part of the selection
    my $first_line_padding = '';

    if (ref $range eq 'HASH')
    {
        @lines = @lines[$range->{start}{line} .. $range->{end}{line}];
        ($first_line_padding) = (substr $lines[0], 0, $range->{start}{character}) =~ /^(\s+)/;
        $first_line_padding = '' unless (length $first_line_padding);
        $lines[0]           = substr $lines[0],  $range->{start}{character};
        $lines[-1]          = substr $lines[-1], 0, $range->{end}{character};
    } ## end if (ref $range eq 'HASH'...)
    else
    {
        $range = {
                  start => {
                            line      => 0,
                            character => 0
                           },
                  end => {
                          line      => scalar @lines,
                          character => 0
                         }
                 };
    } ## end else [ if (ref $range eq 'HASH'...)]

    my $selection = join "\n", @lines;

    # add padding to selection to keep indentation consistent
    $selection = $first_line_padding . $selection;

    my $formatted = '';
    my $stderr;
    my $argv = '-se';
    $argv .= ' -i=' . $args{formatting_options}{tabSize} if (length $args{formatting_options}{tabSize});
    $argv .= ' -t' unless ($args{formatting_options}{insertSpaces});
    $argv .= ' -en=' . $args{formatting_options}{tabSize} if (length $args{formatting_options}{tabSize} and $args{formatting_options}{insertSpaces});
    my $perltidyrc = glob($PLS::Server::State::CONFIG{perltidyrc} // '~/.perltidyrc');
    my $error      = Perl::Tidy::perltidy(source => \$selection, destination => \$formatted, stderr => \$stderr, perltidyrc => glob('~/.perltidyrc'), argv => '-se');

    # remove padding added for consistent formatting
    $formatted = substr $formatted, (length $first_line_padding);

    $formatted =~ s/\s+$//gm if ($args{formatting_options}{trimTrailingWhitespace});

    if ($args{formatting_options}{insertFinalNewline})
    {
        $formatted .= "\n" unless ($formatted =~ /\n$/);
    }
    elsif ($args{formatting_options}{trimFinalNewlines})
    {
        $formatted =~ s/\n+$//;
    }

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

    return (0, {code => -32700, message => 'Could not parse document for formatting. Please check code syntax.'}) unless $self->{document}->complete;
    return $self->format_range(formatting_options => $formatting_options);
} ## end sub format

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

1;
