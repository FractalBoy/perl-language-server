package PLS::Server::Response::InitializeResult;
use parent q(PLS::Server::Response);

use strict;

sub new {
    my ($class, $request) = @_;

    my %self = ( 
        id => $request->{id},
        result => {
            capabilities => {
                definitionProvider => \1,
                documentFormattingProvider => \1,
                documentSymbolProvider => \1
            }
        }
    );

    return bless \%self, $class;
}

1;
