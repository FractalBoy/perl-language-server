package PLS::Server::Method::TextDocument;

use strict;

use PLS::Server::Request::TextDocument::Definition;

sub get_request {
    my ($request) = @_;

    my (undef, $method) = split '/', $request->{method};

    if ($method eq 'definition') {
        return PLS::Server::Request::TextDocument::Definition->new($request);
    }
}

1;
