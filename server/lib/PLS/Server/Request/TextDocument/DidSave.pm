package PLS::Server::Request::TextDocument::DidSave;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use Coro;

use PLS::Parser::Document;
use PLS::Server::Request::Diagnostics::PublishDiagnostics;

sub service
{
    my ($self, $server) = @_;

    $server->{server_requests}->put(PLS::Server::Request::Diagnostics::PublishDiagnostics->new(uri => $self->{params}{textDocument}{uri}));

    return;
} ## end sub service

1;
