package PLS::Parser::Element::VariableStatement;

use strict;
use warnings;

use parent 'PLS::Parser::Element';

use PLS::Parser::Element::Variable;

sub new
{
    my ($class, @args) = @_;

    my $self = $class->SUPER::new(@args);
    $self->{symbols} = [
                        map  { PLS::Parser::Element::Variable->new(document => $self->{document}, element => $_, file => $self->{file}) }
                        grep { ref $_ eq 'PPI::Token::Symbol' } $self->element->symbols
                       ];

    return $self;
} ## end sub new

sub symbols
{
    my ($self) = @_;

    return $self->{symbols};
}

1;
