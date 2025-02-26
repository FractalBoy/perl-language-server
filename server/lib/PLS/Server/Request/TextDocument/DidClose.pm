package PLS::Server::Request::TextDocument::DidClose;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Parser::Document;
use PLS::Server::Request::TextDocument::PublishDiagnostics;

=head1 NAME

PLS::Server::Request::TextDocument::DidClose

=head1 DESCRIPTION

This is a notification from the client to the server that
a text document was closed.

=cut

sub service
{
    my ($self, $server) = @_;

    my $publish_future = PLS::Server::Request::TextDocument::PublishDiagnostics->new(uri => $self->{params}{textDocument}{uri}, close => 1);
    $server->send_server_request($publish_future);

    my $text_document = $self->{params}{textDocument};
    PLS::Parser::Document->close_file(%{$text_document});

    return $publish_future->then(sub { });
} ## end sub service

1;
