package PLS::Server::Request::CompletionItem::Resolve;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::Response::Resolve;

=head2 service

Service this request

=cut

sub service
{
    my ($self) = @_;

    return PLS::Server::Response::Resolve->new($self);
}

1;
