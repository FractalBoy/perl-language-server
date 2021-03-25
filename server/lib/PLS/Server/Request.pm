package PLS::Server::Request;

use strict;
use warnings;

use parent 'PLS::Server::Message';

use PLS::Server::Method::CompletionItem;
use PLS::Server::Method::TextDocument;
use PLS::Server::Method::Workspace;
use PLS::Server::Response::ServerNotInitialized;
use PLS::Server::Request::Initialize;
use PLS::Server::Request::Initialized;
use PLS::Server::Request::CancelRequest;

sub new
{
    my ($class, $request) = @_;

    if ($class ne __PACKAGE__)
    {
        return bless $request, $class;
    }

    my $method = $request->{method};

    if ($method eq 'initialize')
    {
        return PLS::Server::Request::Initialize->new($request);
    }
    elsif ($method eq 'initialized')
    {
        return PLS::Server::Request::Initialized->new($request);
    }

    return PLS::Server::Response::ServerNotInitialized->new($request)
      unless $PLS::Server::State::INITIALIZED;

    if ($method eq '$/cancelRequest')
    {
        return PLS::Server::Request::CancelRequest->new($request);
    }

    # create and return request classes here
    ($method) = split '/', $method;

    if ($method eq 'textDocument')
    {
        return PLS::Server::Method::TextDocument::get_request($request);
    }
    elsif ($method eq 'workspace')
    {
        return PLS::Server::Method::Workspace::get_request($request);
    }
    elsif ($method eq 'completionItem')
    {
        return PLS::Server::Method::CompletionItem::get_request($request);
    }

    return bless $request, $class;
} ## end sub new

sub service
{
    my ($self, $server) = @_;
    return;
}

sub handle_response
{
    my ($self, $response, $server) = @_;

    return;
}

1;
