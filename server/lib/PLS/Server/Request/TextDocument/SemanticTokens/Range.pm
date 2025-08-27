package PLS::Server::Request::TextDocument::SemanticTokens::Range;

use strict;
use warnings;

use parent 'PLS::Server::Request::TextDocument::SemanticTokens';

use PLS::Server::Response::SemanticTokens::Range;

sub service
{
    my ($self) = @_;

    return PLS::Server::Response::SemanticTokens::Range->new($self);
}

1;
