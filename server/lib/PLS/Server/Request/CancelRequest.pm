package PLS::Server::Request::CancelRequest;

use strict;
use warnings;

use parent q(PLS::Server::Request::Base);

use PLS::Server::State;

sub service
{
    my ($self) = @_;

    # right now, we'll just add this id to the list of cancelled ids.
    # we don't yet have the ability to cancel a request in flight.
    # according to the specification, the server is still supposed to send
    # a response even if it was canceled.
    push @PLS::Server::State::CANCELED, $self->{params}{id};
    return undef;
} ## end sub service

1;
