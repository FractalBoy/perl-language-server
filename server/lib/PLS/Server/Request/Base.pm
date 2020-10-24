package PLS::Server::Request::Base;

use strict;
use warnings;

sub new
{
    my ($class, $request) = @_;

    return bless $request, $class;
}

sub service
{
    my ($self) = @_;

    return;
}

sub isa
{
    my ($self, $class) = @_;

    return 1 if $self->SUPER::isa($class);
    return $class eq 'PLS::Server::Request';
} ## end sub isa

1;
