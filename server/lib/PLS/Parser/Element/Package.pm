package PLS::Parser::Element::Package;

use strict;
use warnings;

use parent 'PLS::Parser::Element';

sub name
{
    my ($self) = @_;

    return $self->{ppi_element}->namespace;
}

1;
