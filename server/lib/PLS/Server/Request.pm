package PLS::Server::Request;

use strict;

use JSON;
use List::Util;

use PLS::Server::Method;
use PLS::Server::Request::Base;
use PLS::Server::Request::Initialize;
use PLS::Server::Request::Initialized;
use PLS::Server::Request::CancelRequest;

sub new {
    my ($class, $request) = @_;

    my $method = $request->{method};

    if ($method eq 'initialize') {
        return PLS::Server::Request::Initialize->new($request);
    } elsif ($method eq 'initialized') {
        return PLS::Server::Request::Initialized->new($request);
    }

    return PLS::Server::Response::ServerNotInitialized->new($request)
        unless $PLS::Server::State::INITIALIZED;

    if ($method eq '$/cancelRequest') {
        return PLS::Server::Request::CancelRequest->new($request);
    }

    # create and return request classes here
    my @method = split '/', $method;

    if ($method[0] eq 'textDocument') {
        return PLS::Server::Method::TextDocument::get_request($request);
    } elsif ($method[0] eq 'workspace') {
        return PLS::Server::Method::Workspace::get_request($request);
    }

    return PLS::Server::Request::Base->new($request);
}

1;
