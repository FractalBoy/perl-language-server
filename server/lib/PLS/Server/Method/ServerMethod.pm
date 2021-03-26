package PLS::Server::Method::ServerMethod;

use strict;
use warnings;

use PLS::Server::State;
use PLS::Server::Request::Initialize;
use PLS::Server::Request::Initialized;
use PLS::Server::Request::CancelRequest;

sub get_request
{
    my ($request) = @_;

    my $method = $request->{method};

    if ($method eq 'initialize')
    {
        return PLS::Server::Request::Initialize->new($request);
    }
    elsif ($method eq 'initialized')
    {
        return PLS::Server::Request::Initialized->new($request);
    }

    return PLS::Server::Response::ServerNotInitialized->new($request) unless $PLS::Server::State::INITIALIZED;

    if ($method eq '$/cancelRequest')
    {
        return PLS::Server::Request::CancelRequest->new($request);
    }

    return;
} ## end sub get_request

1;
