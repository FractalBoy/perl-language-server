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
    return unless (exists $server->{running_futures}{$id});
    my $request_to_cancel = $server->{running_futures}{$id};

    return unless (blessed($request_to_cancel) and $request_to_cancel->isa('Future'));
    $request_to_cancel->cancel();

    delete $server->{running_futures}{$id};

    return;
} ## end sub service

1;
