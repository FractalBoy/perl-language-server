package PLS::Server::Method::TextDocument;

use strict;

use PLS::Server::Request::TextDocument::Definition;
use PLS::Server::Request::TextDocument::DocumentSymbol; 
use PLS::Server::Request::TextDocument::Hover; 
use PLS::Server::Request::TextDocument::SignatureHelp; 

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
        return unless $text_document->{languageId} eq 'perl';
        $PLS::Server::State::FILES->{$text_document->{uri}}{version} = $text_document->{version};
        $PLS::Server::State::FILES->{$text_document->{uri}}{text} = $text_document->{text};
    }
    if ($method eq 'didChange')
    {
        my $text_document = $request->{params}{textDocument};
        my $tracked = $PLS::Server::State::FILES->{$text_document->{uri}};
        # not tracking this file, probably because it isn't perl
        return if ref $tracked ne 'HASH';
        # version is not newer than the version we have in memory
        return if $text_document->{version} <= $tracked->{version};
        return unless ref $request->{params}{contentChanges} eq 'ARRAY'; 
        # just take the last change, it's the most up to date.
        $tracked->{text} = $request->{params}{contentChanges}[-1]{text};
    }
    if ($method eq 'didClose')
    {
        # stop tracking, use the file as it is on disk (whether it was saved or not).
        delete $PLS::Server::State::FILES->{$request->{params}{textDocument}{uri}};
    }
}

1;
