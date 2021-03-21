package PLS::Server::Method::Workspace;

use strict;

use PLS::Server::Request::Workspace::DidChangeConfiguration;
use PLS::Server::Request::Workspace::DidChangeWatchedFiles;

sub get_request
{
    my ($request) = @_;

    my (undef, $method) = split '/', $request->{method};

    if ($method eq 'didChangeConfiguration')
    {
        return PLS::Server::Request::Workspace::DidChangeConfiguration->new($request);
    }
    if ($method eq 'didChangeWatchedFiles')
    {
        return PLS::Server::Request::Workspace::DidChangeWatchedFiles->new($request);
    }
} ## end sub get_request

1;
