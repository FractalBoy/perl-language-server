package PLS::Parser::Element::Variable;

use strict;
use warnings;

use parent 'PLS::Parser::Element';

sub name
{
    my ($self) = @_;

    return $self->{ppi_element}->symbol;
}

1;
