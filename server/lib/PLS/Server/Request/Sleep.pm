package PLS::Server::Request::Sleep;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use IO::Async::Loop;
use IO::Async::Timer::Countdown;

use PLS::Server::Response::Sleep;

sub service
{
    my ($self) = @_;

    return PLS::Server::Response::Sleep->new($self);
}

1;
