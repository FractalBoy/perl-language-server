package PLS::Server::Request::Workspace::DidChangeConfiguration;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::Request::Workspace::Configuration;

sub service
{
    my ($self, $server) = @_;

    $server->{server_requests}->put(PLS::Server::Request::Workspace::Configuration->new());
}

1;
