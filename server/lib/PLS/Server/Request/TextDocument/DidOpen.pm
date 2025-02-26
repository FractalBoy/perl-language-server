package PLS::Server::Request::TextDocument::DidOpen;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use Future;

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

    my $publish_future = PLS::Server::Request::TextDocument::PublishDiagnostics->new(uri => $text_document->{uri});
    $server->send_server_request($publish_future);

    # Warm up the cache for imported package symbols
    my $text    = PLS::Parser::Document->text_from_uri($text_document->{uri});
    my $imports = PLS::Parser::Document->get_imports($text);

    my $symbols_future = PLS::Parser::PackageSymbols::get_imported_package_symbols($PLS::Server::State::CONFIG, @{$imports});

    return Future->wait_all($publish_future, $symbols_future)->then(sub { });
} ## end sub service

1;
