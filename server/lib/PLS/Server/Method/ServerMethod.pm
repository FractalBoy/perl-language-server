package PLS::Server::Method::ServerMethod;

use strict;
use warnings;

use PLS::Server::State;
use PLS::Server::Request::Initialize;
use PLS::Server::Request::Initialized;
use PLS::Server::Request::CancelRequest;
use PLS::Server::Response::ServerNotInitialized;

=head1 NAME

PLS::Server::Method::ServerMethod

=head1 DESCRIPTION

This module redirects requests that the server must handle to the appropriate
subclass of L<PLS::Server::Request>.

It will also return the appropriate error if the client is attempting to make a
request before the server has been initialized (L<PLS::Server::Response::ServerNotInitialized>).

Requests currently implemented:

=over

=item initialize - L<https://microsoft.github.io/language-server-protocol/specifications/specification-current/#initialize>

L<PLS::Server::Request::Initialize>

=item initialized - L<https://microsoft.github.io/language-server-protocol/specifications/specification-current/#initialized>

L<PLS::Server::Request::Initialized>

=item $/cancelRequest - L<https://microsoft.github.io/language-server-protocol/specifications/specification-current/#cancelRequest>

L<PLS::Server::Request::CancelRequest>

=back

=cut

sub get_request
{
    my ($request) = @_;

    my $method = $request->{method};

    if ($method eq 'initialize')
    {
        return PLS::Server::Request::Initialize->new($request);
    }

    return PLS::Server::Response::ServerNotInitialized->new($request) unless $PLS::Server::State::INITIALIZED;

    if ($method eq 'initialized')
    {
        return PLS::Server::Request::Initialized->new($request);
    }

    if ($method eq '$/cancelRequest')
    {
        return PLS::Server::Request::CancelRequest->new($request);
    }

    return;
} ## end sub get_request

sub is_server_method
{
    my ($method) = @_;

    return 1 if ($method eq 'initialize');
    return 1 if ($method eq 'initialized');
    return 1 if ($method eq '$');
    return 0;
} ## end sub is_server_method

1;
