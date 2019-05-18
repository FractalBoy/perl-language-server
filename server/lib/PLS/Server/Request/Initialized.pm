package PLS::Server::Request::Initialized;
use parent q(PLS::Server::Request::Base);

use strict;

use PLS::Server::State;

sub service {
    $PLS::Server::State::INITIALIZED = 1;
    return undef;
}

1;
