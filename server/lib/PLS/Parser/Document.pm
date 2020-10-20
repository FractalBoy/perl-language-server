package PLS::Parser::Document;

use strict;
use warnings;

use Perl::Critic::Utils;
use PPI;
use PPI::Find;
use URI;

use PLS::Parser::Element;
use PLS::Parser::Element::Constant;
use PLS::Parser::Element::Package;
use PLS::Parser::Element::Subroutine;
use PLS::Parser::Element::VariableStatement;
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
    $INDEX = PLS::Parser::Index->new(root => $PLS::Server::State::ROOT_PATH) unless (ref $INDEX eq 'PLS::Parser::Index');

    my %self = (
                path     => $path,
                document => _document_from_uri($uri),
                index => $INDEX
               );

    return unless (ref $self{document} eq 'PPI::Document');

    return bless \%self, $class;
} ## end sub new

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
            my $pod = PLS::Parser::Pod::Subroutine->new(document => $self, element => $element, package => $package, subroutine => $subroutine);
            my $ok = $pod->find();
            return (1, $pod) if $ok;
        }
        if (($package, $subroutine) = $element->class_method_package_and_name())
        {
            my $pod = PLS::Parser::Pod::ClassMethod->new(document => $self, element => $element, package => $package, subroutine => $subroutine);
            my $ok = $pod->find();
            return (1, $pod) if $ok;
        }
        if ($subroutine = $element->method_name())
        {
            my $pod = PLS::Parser::Pod::Method->new(document => $self, element => $element, subroutine => $subroutine);
            my $ok = $pod->find();
            return (1, $pod) if $ok;
        }
        if ($package = $element->package_name())
        {
            my $pod = PLS::Parser::Pod::Package->new(document => $self, element => $element, package => $package);
            my $ok = $pod->find();
            return (1, $pod) if $ok;
        }
        if ($variable = $element->variable_name())
        {
            my $pod = PLS::Parser::Pod::Variable->new(document => $self->{document}, element => $element, variable => $variable);
            my $ok = $pod->find();
            return (1, $pod) if $ok;
        }
    } ## end foreach my $element (@elements...)

    return 0;
}

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
    @matches = sort { (abs $column_number - $a->column_number) <=> (abs $column_number - $b->column_number) } @matches;
    @matches = map  { PLS::Parser::Element->new(document => $self->{document}, element => $_, file => $self->{path}) } @matches;
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

    my $find = PPI::Find->new(sub { $_[0]->isa('PPI::Statement::Sub') and not $_[0]->isa('PPI::Statement::Scheduled') });
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
            return $element->module eq 'constant';
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
              map  { $_->children }
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
}

sub _ppi_location
{
    my ($line_number, $column_number) = @_;

    return ++$line_number, ++$column_number;
}

sub _document_from_uri
{
    my ($uri) = @_;

    my $document;

    if (ref $FILES{$uri} eq 'HASH')
    {
        $document = PPI::Document->new(\($FILES{$uri}{text}));
    }
    else
    {
        my $file = URI->new($uri);
        $document = PPI::Document->new($file->file);
    }

    return '' unless (ref $document eq 'PPI::Document');
    $document->index_locations;
    return $document;
} ## end sub _document_from_uri

sub _is_constant
{
    my ($element) = @_;

    return unless $element->isa('PPI::Token::Word');
    return unless ref $_->snext_sibling eq 'PPI::Token::Operator';
    return $_->snext_sibling->content eq '=>';
} ## end sub _is_constant

1;
