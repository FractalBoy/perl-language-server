package PLS::Server::Method::CompletionItem;

use strict;

use PLS::Server::Request::CompletionItem::Resolve;

sub get_request
{
    my ($request) = @_;

    my (undef, $method) = split '/', $request->{method};

    if ($method eq 'resolve')
    {
        return PLS::Server::Request::CompletionItem::Resolve->new($request);
    }
} ## end sub get_request

1;
