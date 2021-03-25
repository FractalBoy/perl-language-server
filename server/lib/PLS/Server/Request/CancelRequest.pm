package PLS::Server::Request::CancelRequest;

use strict;
use warnings;

use feature 'isa';
no warnings 'experimental::isa';

use parent 'PLS::Server::Request';

use PLS::Server::Response::Cancelled;

sub service
{
    my ($self, $server) = @_;

    my $id = $self->{params}{id};
    return unless (exists $server->{running_coros}{$id});
    my $request_to_cancel = $server->{running_coros}{$id};

    return unless ($request_to_cancel isa 'Coro');
    eval { $request_to_cancel->safe_cancel() };

    delete $server->{running_coros}{$id};

    return PLS::Server::Response::Cancelled->new(id => $id);
} ## end sub service

1;
