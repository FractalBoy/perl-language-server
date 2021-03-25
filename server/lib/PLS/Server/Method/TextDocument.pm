package PLS::Server::Method::TextDocument;

use strict;
use warnings;

use PLS::Server::Request::TextDocument::Completion;
use PLS::Server::Request::TextDocument::Definition;
use PLS::Server::Request::TextDocument::DidChange;
use PLS::Server::Request::TextDocument::DidClose;
use PLS::Server::Request::TextDocument::DidOpen;
use PLS::Server::Request::TextDocument::DocumentSymbol;
use PLS::Server::Request::TextDocument::Formatting;
use PLS::Server::Request::TextDocument::Hover;
use PLS::Server::Request::TextDocument::SignatureHelp;
use PLS::Server::Request::TextDocument::RangeFormatting;

sub get_request
{
    my ($request) = @_;

    my (undef, $method) = split '/', $request->{method};

    if ($method eq 'definition')
    {
        return PLS::Server::Request::TextDocument::Definition->new($request);
    }
    if ($method eq 'documentSymbol')
    {
        return PLS::Server::Request::TextDocument::DocumentSymbol->new($request);
    }
    if ($method eq 'hover')
    {
        return PLS::Server::Request::TextDocument::Hover->new($request);
    }
    if ($method eq 'signatureHelp')
    {
        return PLS::Server::Request::TextDocument::SignatureHelp->new($request);
    }
    if ($method eq 'didOpen')
    {
        return PLS::Server::Request::TextDocument::DidOpen->new($request);
    }
    if ($method eq 'didChange')
    {
        return PLS::Server::Request::TextDocument::DidChange->new($request);
    }
    if ($method eq 'didClose')
    {
        return PLS::Server::Request::TextDocument::DidClose->new($request);
    }
    if ($method eq 'formatting')
    {
        return PLS::Server::Request::TextDocument::Formatting->new($request);
    }
    if ($method eq 'rangeFormatting')
    {
        return PLS::Server::Request::TextDocument::RangeFormatting->new($request);
    }
    if ($method eq 'completion')
    {
        return PLS::Server::Request::TextDocument::Completion->new($request);
    }
} ## end sub get_request

1;
