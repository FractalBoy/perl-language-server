package PLS::Server::Method::TextDocument;

use strict;

use PLS::Server::Request::TextDocument::Definition;
use PLS::Server::Request::TextDocument::DocumentSymbol;
use PLS::Server::Request::TextDocument::Hover;
use PLS::Server::Request::TextDocument::SignatureHelp;
use PLS::Parser::Document;

sub get_request {
    my ($request) = @_;

    my (undef, $method) = split '/', $request->{method};

    if ($method eq 'definition') {
        return PLS::Server::Request::TextDocument::Definition->new($request);
    }
    if ($method eq 'documentSymbol') {
        return PLS::Server::Request::TextDocument::DocumentSymbol->new($request);
    }
    if ($method eq 'hover') {
        return PLS::Server::Request::TextDocument::Hover->new($request);
    }
    if ($method eq 'signatureHelp') {
        return PLS::Server::Request::TextDocument::SignatureHelp->new($request);
    }
    if ($method eq 'didOpen')
    {
        my $text_document = $request->{params}{textDocument};
        PLS::Parser::Document->open_file(%$text_document);
    }
    if ($method eq 'didChange')
    {
        # skip the earlier changes and just use the newest one.
        return unless (ref $request->{params}{contentChanges} eq 'ARRAY' and ref $request->{params}{contentChanges}[-1] eq 'HASH');
        my $text_document = $request->{params}{textDocument};
        PLS::Parser::Document->update_file(%$text_document, text => $request->{params}{contentChanges}[-1]{text})
    }
    if ($method eq 'didClose')
    {
        PLS::Parser::Document->close_file(%{$request->{params}{textDocument}});
    }
}

1;
