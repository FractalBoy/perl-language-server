package PLS::Parser::Element::Constant;

use strict;
use warnings;

use parent 'PLS::Parser::Element';

sub location_info
{
    my ($self) = @_;

    my $info = $self->SUPER::location_info;
    $info->{constant} = 1;
    return $info;
} ## end sub location_info

1;
