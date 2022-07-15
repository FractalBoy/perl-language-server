package PLS::Server::Request::Initialized;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::State;
use PLS::Server::Request::Workspace::Configuration;
use PLS::Server::Request::Client::RegisterCapability;
use PLS::Parser::Document;

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

    # request that we receive a notification any time configuration changes
    my @capabilities = ({id => 'did-change-configuration', method => 'workspace/didChangeConfiguration'});

    # request that we receive a notification every time a file changes,
    # so that we can reindex it.
    my $index = PLS::Parser::Index->new();

    if (scalar @{$index->{workspace_folders}})
    {
        push @capabilities,
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
          };
    } ## end if (length $PLS::Server::State::ROOT_PATH...)

    $server->send_server_request(PLS::Server::Request::Client::RegisterCapability->new(\@capabilities));

    $index->index_files();

    return;
} ## end sub service

1;
