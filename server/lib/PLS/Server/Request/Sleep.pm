package PLS::Server::Request::Sleep;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use IO::Async::Loop;
use IO::Async::Timer::Countdown;

use PLS::Server::Response::Sleep;

=head1 NAME

PLS::Server::Request::Sleep

=head1 DESCRIPTION

This is not a real language server request - it is only used for testing,
to start a request that takes an arbitrary amount of time to complete.

=cut

sub service
{
    my ($self) = @_;

    return PLS::Server::Response::Sleep->new($self);
}

1;
