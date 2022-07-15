package PLS::Server::Method::Workspace;

use strict;
use warnings;

use PLS::Server::Request::Workspace::Configuration;
use PLS::Server::Request::Workspace::DidChangeConfiguration;
use PLS::Server::Request::Workspace::DidChangeWatchedFiles;
use PLS::Server::Request::Workspace::DidChangeWorkspaceFolders;
use PLS::Server::Request::Workspace::ExecuteCommand;
use PLS::Server::Request::Workspace::Symbol;

=head1 NAME

PLS::Server::Method::Workspace

=head1 DESCRIPTION

This module redirects requests starting with C<workspace/> to the appropriate
subclass of L<PLS::Server::Request> for the type of request.

Requests currently implemented:

=over

=item workspace/didChangeConfiguration - L<https://microsoft.github.io/language-server-protocol/specifications/specification-current/#workspace_didChangeConfiguration>

L<PLS::Server::Request::Workspace::DidChangeConfiguration>

=item workspace/didChangeWatchedFiles - L<https://microsoft.github.io/language-server-protocol/specifications/specification-current/#workspace_didChangeWatchedFiles>

L<PLS::Server::Request::Workspace::DidChangeWatchedFiles>

=item workspace/didChangeWorkspaceFolders - L<https://microsoft.github.io/language-server-protocol/specifications/specification-current/#workspace_didChangeWorkspaceFolders>

L<PLS::Server::Request::Workspace::DidChangeWorkspaceFolders>

=item workspace/configuration - L<https://microsoft.github.io/language-server-protocol/specifications/specification-current/#workspace_configuration>

L<PLS::Server::Request::Workspace::Configuration>

=item workspace/executeCommand - L<https://microsoft.github.io/language-server-protocol/specifications/specification-current/#workspace_executeCommand>

L<PLS::Server::Request::Workspace::ExecuteCommand>

=back

=cut

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
    if ($method eq 'didChangeWorkspaceFolders')
    {
        return PLS::Server::Request::Workspace::DidChangeWorkspaceFolders->new($request);
    }
    if ($method eq 'configuration')
    {
        return PLS::Server::Request::Workspace::Configuration->new($request);
    }
    if ($method eq 'executeCommand')
    {
        return PLS::Server::Request::Workspace::ExecuteCommand->new($request);
    }
    if ($method eq 'symbol')
    {
        return PLS::Server::Request::Workspace::Symbol->new($request);
    }
} ## end sub get_request

1;
