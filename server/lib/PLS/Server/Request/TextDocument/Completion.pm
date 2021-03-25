package PLS::Server::Request::TextDocument::Completion;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::Response::Completion;

sub service
{
    my ($self) = @_;

    return PLS::Server::Response::Completion->new($self);
}

1;
