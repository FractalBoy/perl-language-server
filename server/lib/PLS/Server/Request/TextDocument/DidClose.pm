package PLS::Server::Request::TextDocument::DidClose;

use strict;
use warnings;

use Coro;
use parent 'PLS::Server::Request';

use PLS::Parser::Document;
use PLS::Server::Request::Diagnostics::PublishDiagnostics;

sub service
{
    my ($self, $server) = @_;

    my $text_document = $self->{params}{textDocument};
    PLS::Parser::Document->close_file(%{$text_document});

    $server->{server_requests}->put(PLS::Server::Request::Diagnostics::PublishDiagnostics->new(uri => $self->{params}{textDocument}{uri}, close => 1));

    return;
} ## end sub service

1;
