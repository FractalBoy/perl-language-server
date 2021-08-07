package PLS::Server::Request::TextDocument::DidSave;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Parser::Document;
use PLS::Server::Request::TextDocument::PublishDiagnostics;

=head1 NAME

PLS::Server::Request::TextDocument::DidSave

=head1 DESCRIPTION

This is a notification from the client to the server that
a text document was saved.

=cut

sub service
{
    my ($self, $server) = @_;

    my $uri = $self->{params}{textDocument}{uri};
    $server->send_server_request(PLS::Server::Request::TextDocument::PublishDiagnostics->new(uri => $uri));

    return;
} ## end sub service

1;
