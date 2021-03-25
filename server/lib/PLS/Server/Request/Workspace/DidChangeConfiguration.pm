package PLS::Server::Request::Workspace::DidChangeConfiguration;

use strict;
use warnings;

use parent q(PLS::Server::Request::Base);

use PLS::Server::Request::Workspace::Configuration;

sub service
{
    my ($self, $server) = @_;

    $server->{server_requests}->put(PLS::Server::Request::Workspace::Configuration->new());
}

1;
