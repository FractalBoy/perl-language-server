package PLS::Server::Request::Initialized;

use strict;
use warnings;

use parent q(PLS::Server::Request::Base);

use PLS::Server::State;
use PLS::Server::Request::Workspace::Configuration;

sub service
{
    my ($self, $server) = @_;

    # now that we're initialized, put in a request for our configuration items.
    $server->{server_requests}->put(PLS::Server::Request::Workspace::Configuration->new);

    $PLS::Server::State::INITIALIZED = 1;
    return undef;
} ## end sub service

1;
