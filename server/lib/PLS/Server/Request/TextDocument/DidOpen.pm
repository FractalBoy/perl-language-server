package PLS::Server::Request::TextDocument::DidOpen;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use Coro;

use PLS::Parser::Document;
use PLS::Server::Request::Diagnostics::PublishDiagnostics;

sub service
{
    my ($self, $server) = @_;

    my $text_document = $self->{params}{textDocument};
    PLS::Parser::Document->open_file(%{$text_document}); 

    async {
        $server->{server_requests}->put(PLS::Server::Request::Diagnostics::PublishDiagnostics->new(uri => $self->{params}{textDocument}{uri}));
    };

    return;
}

1;
