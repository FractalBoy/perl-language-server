package PLS::Server::Response::SemanticTokens::Range;

use strict;
use warnings;

use parent 'PLS::Server::Response::SemanticTokens';

sub new
{
    my ($class, $request) = @_;

    my %self = (id => $request->{id});

    return bless \%self, $class;
} ## end sub new

1;
