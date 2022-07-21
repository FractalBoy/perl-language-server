package PLS::Server::Request::Initialized;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use JSON::PP;
use List::Util;
use Path::Tiny;

use PLS::Server::State;
use PLS::Server::Request::Workspace::Configuration;
use PLS::Server::Request::Client::RegisterCapability;
use PLS::Server::Request::WorkDoneProgress;
use PLS::Server::Request::Window::WorkDoneProgress::Create;
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

    if (scalar @{$index->workspace_folders})
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
    } ## end if (scalar @{$index->workspace_folders...})

    $server->send_server_request(PLS::Server::Request::Client::RegisterCapability->new(\@capabilities));
    my $work_done_progress_create = PLS::Server::Request::Window::WorkDoneProgress::Create->new();
    $server->send_server_request($work_done_progress_create);

    $server->send_server_request(
                                 PLS::Server::Request::WorkDoneProgress->new(
                                                                             token       => $work_done_progress_create->{params}{token},
                                                                             kind        => 'begin',
                                                                             title       => 'Indexing',
                                                                             cancellable => JSON::PP::false,
                                                                             percentage  => 0
                                                                            )
                                );

    # Now is a good time to start indexing files.
    $index->index_files()->then(
        sub {
            my @futures = @_;

            my $done  = 0;
            my $total = scalar @futures;

            foreach my $future (@futures)
            {
                $future->then(
                    sub {
                        my ($file) = @_;

                        my $workspace_folder = List::Util::first { path($_)->subsumes($file) } @{$index->workspace_folders};
                        $file = path($file)->relative($workspace_folder);
                        $done++;
                        $server->send_server_request(
                                                     PLS::Server::Request::WorkDoneProgress->new(
                                                                                                 token      => $work_done_progress_create->{params}{token},
                                                                                                 kind       => 'report',
                                                                                                 message    => "Indexed $file ($done/$total)",
                                                                                                 percentage => int($done / $total)
                                                                                                )
                                                    );
                    }
                )->retain();
            } ## end foreach my $future (@futures...)

            return Future->wait_all(@futures)->on_done(
                sub {
                    $server->send_server_request(
                                                 PLS::Server::Request::WorkDoneProgress->new(
                                                                                             token   => $work_done_progress_create->{params}{token},
                                                                                             kind    => 'end',
                                                                                             message => 'Finished indexing all files'
                                                                                            )
                                                );

                }
            );
        }
    )->retain();

    return;
} ## end sub service

1;
