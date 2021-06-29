package PLS::Server::Request::Initialized;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::State;
use PLS::Server::Request::Workspace::Configuration;
use PLS::Server::Request::Client::RegisterCapability;

=head1 NAME

PLS::Server::Request::Initialized

=head1 DESCRIPTION

This is a request from the client to the server indicating that it received
the result of the initialize request from the server.

The server sends back some initial requests that it needs to complete initialization.

=cut

sub service
{
    my ($self, $server) = @_;

    # now that we're initialized, put in a request for our configuration items.
    $server->send_server_request(PLS::Server::Request::Workspace::Configuration->new());

    # also start watching all files
    $server->send_server_request(
                                    PLS::Server::Request::Client::RegisterCapability->new(
                                                                                          [
                                                                                           {
                                                                                            id              => 'did-change-watched-files',
                                                                                            method          => 'workspace/didChangeWatchedFiles',
                                                                                            registerOptions => {
                                                                                                                watchers => [
                                                                                                                             {
                                                                                                                              globPattern => '**/*'
                                                                                                                             }
                                                                                                                            ]
                                                                                                               }
                                                                                           },
                                                                                           {
                                                                                            id     => 'did-change-configuration',
                                                                                            method => 'workspace/didChangeConfiguration'
                                                                                           }
                                                                                          ]
                                                                                         )
                                   );

    $PLS::Server::State::INITIALIZED = 1;
    return;
} ## end sub service

1;
