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
                documentSymbolProvider => \1,
                hoverProvider => \1,
                signatureHelpProvider => {
                    triggerCharacters => ['(']
                },
                textDocumentSync => {
                    openClose => \1,
                    change => 1
                },
                documentFormattingProvider => \1,
                documentRangeFormattingProvider => \1
            }
        }
    );

    return bless \%self, $class;
}

1;
