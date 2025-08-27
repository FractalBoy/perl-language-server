package PLS::Server::Request::TextDocument::SemanticTokens::Full;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use PLS::Server::Response::SemanticTokens::Full;

sub service
{
    my ($self) = @_;

    return PLS::Server::Response::SemanticTokens::Full->new($self);
}

1;
