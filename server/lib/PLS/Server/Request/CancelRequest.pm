package PLS::Server::Request::CancelRequest;

use strict;
use warnings;

use parent q(PLS::Server::Request::Base);

use PLS::Server::State;

sub service
{
    my ($self) = @_;

    # right now, we don't do anything with a cancelled request
    # we don't yet have the ability to cancel a request in flight.
    # according to the specification, the server is still supposed to send
    # a response even if it was canceled.

    return;
} ## end sub service

1;
