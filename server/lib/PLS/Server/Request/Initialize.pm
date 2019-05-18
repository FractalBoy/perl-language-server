package PLS::Server::Request::Initialize;
use parent q(PLS::Server::Request::Base);

use strict;

use PLS::Server::Response::InitializeResult;

sub service {
    my ($self) = @_;
    return PLS::Server::Response::InitializeResult->new($self);
}

1;
