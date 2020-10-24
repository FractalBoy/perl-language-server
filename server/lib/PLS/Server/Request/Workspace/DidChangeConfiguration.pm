package PLS::Server::Request::Workspace::DidChangeConfiguration;
use parent q(PLS::Server::Request::Base);

use strict;

sub service
{
    my ($self) = @_;

    use Data::Dumper;
    warn Dumper $self;
}

1;
