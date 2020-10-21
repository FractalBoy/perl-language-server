package PLS::Server::Request::TextDocument::RangeFormatting;
use parent q(PLS::Server::Request::Base);

use strict;

use PLS::Server::Response::RangeFormatting;

sub service {
    my ($self) = @_;

    return PLS::Server::Response::RangeFormatting->new($self);
}

1;
