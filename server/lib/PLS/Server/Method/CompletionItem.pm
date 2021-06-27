package PLS::Server::Method::CompletionItem;

use strict;
use warnings;

use PLS::Server::Request::CompletionItem::Resolve;

=head1 NAME

This module redirects requests beginning with C<completionItem/> to the
appropriate subclass of L<PLS::Server::Request>.

Requests currently implemented:

=over

=item completionItem/resolve - L<https://microsoft.github.io/language-server-protocol/specifications/specification-current/#completionItem_resolve>

L<PLS::Server::Request::CompletionItem::Resolve>

=back

=cut

sub get_request
{
    my ($request) = @_;

    my (undef, $method) = split '/', $request->{method};

    if ($method eq 'resolve')
    {
        return PLS::Server::Request::CompletionItem::Resolve->new($request);
    }

    return;
} ## end sub get_request

1;
