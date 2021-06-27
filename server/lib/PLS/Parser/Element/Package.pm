package PLS::Parser::Element::Package;

use strict;
use warnings;

use parent 'PLS::Parser::Element';

=head1 NAME

PLS::Parser::Element::Package

=head1 DESCRIPTION

Subclass of L<PLS::Parser::Element> representing a package declaration.

=cut

sub name
{
    my ($self) = @_;

    return $self->element->namespace;
}

sub length
{
    my ($self) = @_;

    return $self->SUPER::length() + length('package ') + length(';');
}

1;
