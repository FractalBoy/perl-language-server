package PLS::Server::Request::CancelRequest;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::Response::Cancelled;

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
    return unless (exists $server->{running_coros}{$id});
    my $request_to_cancel = $server->{running_coros}{$id};

    return unless (blessed($request_to_cancel) and $request_to_cancel->isa('Coro'));
    eval { $request_to_cancel->safe_cancel() };

    delete $server->{running_coros}{$id};

    return PLS::Server::Response::Cancelled->new(id => $id);
} ## end sub service

1;
