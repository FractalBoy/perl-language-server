package PLS::Server::Method::TextDocument;

use strict;

use PLS::Server::Request::TextDocument::Definition;
use PLS::Server::Request::TextDocument::DocumentSymbol; 
use PLS::Server::Request::TextDocument::Hover; 

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
}

1;
