package PLS::Parser::Element::Package;

use strict;
use warnings;

use parent 'PLS::Parser::Element';

sub name
{
    my ($self) = @_;

    return $self->{ppi_element}->namespace;
}

sub length
{
    my ($self) = @_;

    return $self->SUPER::length() + length('package ') + length(';');
}

1;
