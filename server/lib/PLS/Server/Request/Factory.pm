package PLS::Server::Request::Factory;

use strict;
use warnings;

use PLS::Server::Method::CompletionItem;
use PLS::Server::Method::TextDocument;
use PLS::Server::Method::Workspace;
use PLS::Server::Method::ServerMethod;
use PLS::Server::Request;

=head1 NAME

PLS::Server::Request::Factory

=head1 DESCRIPTION

This is a factory class. Given a request from the client, this
will determine the appropriate subclass of L<PLS::Server::Request> for the request
and return it.

=cut

sub new
{
    my ($class, $request) = @_;

    my $method = $request->{method};
    ($method) = split '/', $method;

    # create and return request classes here

    if ($method eq '' or $method eq '$' or not $PLS::Server::State::INITIALIZED)
    {
        return PLS::Server::Method::ServerMethod::get_request($request);
    }
    elsif ($method eq 'textDocument')
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

    return PLS::Server::Request->new($request);
} ## end sub new

1;
