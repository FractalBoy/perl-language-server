package PLS::Server::Request::Initialized;
use parent q(PLS::Server::Request::Base);

use strict;

use PLS::Server::State;
use PLS::Server::Request::Workspace::Configuration;

sub service
{
    my ($self, $server) = @_;

    $server->{server_requests}->put(PLS::Server::Request::Workspace::Configuration->new);

    $PLS::Server::State::INITIALIZED = 1;
    return undef;
} ## end sub service

1;
