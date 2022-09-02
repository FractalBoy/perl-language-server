package PLS::Server::Request::TextDocument::DidOpen;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Parser::Document;
use PLS::Parser::PackageSymbols;
use PLS::Server::Request::TextDocument::PublishDiagnostics;

=head1 NAME

PLS::Server::Request::TextDocument::DidOpen

=head1 DESCRIPTION

This is a notification from the client to the server that
a text document was opened.

=cut

sub service
{
    my ($self, $server) = @_;

    my $text_document = $self->{params}{textDocument};
    PLS::Parser::Document->open_file(%{$text_document});

    $server->send_server_request(PLS::Server::Request::TextDocument::PublishDiagnostics->new(uri => $text_document->{uri}));

    # Warm up the cache for imported package symbols
    my $text    = PLS::Parser::Document->text_from_uri($text_document->{uri});
    my $imports = PLS::Parser::Document->get_imports($text);
    PLS::Parser::PackageSymbols::get_imported_package_symbols($PLS::Server::State::CONFIG, @{$imports})->retain();

    return;
} ## end sub service

1;
