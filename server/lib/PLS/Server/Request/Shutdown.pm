package PLS::Server::Request::Shutdown;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use Scalar::Util qw(blessed);

=head1 NAME

PLS::Server::Request::Shutdown

=head1 DESCRIPTION

This is a notification message from the client to the server requesting
that the server shuts down.

=cut

sub service
{
    my ($self) = @_;

    return PLS::Server::Response::Shutdown->new($self);
} ## end sub service

1;
