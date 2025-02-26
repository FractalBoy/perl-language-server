package PLS::Server::Request::CancelRequest;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use Scalar::Util qw(blessed);

=head1 NAME

PLS::Server::Request::CancelRequest

=head1 DESCRIPTION

This is a notification message from the client to the server requesting
that a request be cancelled.

=cut

sub service
{
    my ($self, $server) = @_;

    my $id = $self->{params}{id};
    $server->cancel_request($id);

    return;
} ## end sub service

1;
