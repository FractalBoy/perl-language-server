package PLS::Server::Request::Workspace::DidChangeConfiguration;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::Request::Workspace::Configuration;

=head1 NAME

PLS::Server::Request::Workspace::DidChangeConfiguration

=head1 DESCRIPTION

This is a notification from the client to the server indicating that there
was a configuration change.

The server sends back a L<PLS::Server::Request::Workspace::Configuration> request
to ask for the new configuration.

=cut

sub service
{
    my ($self, $server) = @_;

    $server->send_server_request(PLS::Server::Request::Workspace::Configuration->new());
}

1;
