package PLS::Parser::Element::Variable;

use strict;
use warnings;

use parent 'PLS::Parser::Element';

=head1 NAME

PLS::Parser::Element::Variable

=head1 DESCRIPTION

Subclass of L<PLS::Parser::Element> representing a variable reference.

=cut

sub name
{
    my ($self) = @_;

    return $self->element->symbol;
}

1;
