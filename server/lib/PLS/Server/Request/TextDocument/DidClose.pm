package PLS::Server::Request::TextDocument::DidClose;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Parser::Document;
use PLS::Server::Request::Diagnostics::PublishDiagnostics;

=head1 NAME

PLS::Server::Request::TextDocument::DidClose

=head1 DESCRIPTION

This is a notification from the client to the server that
a text document was closed.

=cut

sub service
{
    my ($self, $server) = @_;

    my $text_document = $self->{params}{textDocument};
    PLS::Parser::Document->close_file(%{$text_document});

    $server->send_server_request(PLS::Server::Request::Diagnostics::PublishDiagnostics->new(uri => $self->{params}{textDocument}{uri}, close => 1));

    return;
} ## end sub service

1;
