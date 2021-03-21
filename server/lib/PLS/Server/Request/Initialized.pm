package PLS::Server::Request::Initialized;

use strict;
use warnings;

use parent q(PLS::Server::Request::Base);

use PLS::Server::State;
use PLS::Server::Request::Workspace::Configuration;
use PLS::Server::Request::Client::RegisterCapability;

sub service
{
    my ($self, $server) = @_;

    # now that we're initialized, put in a request for our configuration items.
    $server->{server_requests}->put(PLS::Server::Request::Workspace::Configuration->new);

    # also start watching all files
    $server->{server_requests}->put(
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
