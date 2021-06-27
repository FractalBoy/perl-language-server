package PLS::Parser::Element::Constant;

use strict;
use warnings;

use parent 'PLS::Parser::Element';

=head1 NAME

PLS::Parser::Element::Constant

=head1 DESCRIPTION

Subclass of L<PPI::Parser::Element> representing a constant
declared with C<use constant>.

=cut

sub location_info
{
    my ($self) = @_;

    my $info = $self->SUPER::location_info;
    $info->{constant} = 1;
    return $info;
} ## end sub location_info

1;
