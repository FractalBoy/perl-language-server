package PLS::Server::Request::TextDocument::RangeFormatting;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::Response::RangeFormatting;

sub service
{
    my ($self) = @_;

    return PLS::Server::Response::RangeFormatting->new($self);
}

1;
