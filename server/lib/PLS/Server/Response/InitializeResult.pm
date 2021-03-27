package PLS::Server::Response::InitializeResult;

use strict;
use warnings;

use parent q(PLS::Server::Response);

sub new
{
    my ($class, $request) = @_;

    my %self = (
                id     => $request->{id},
                result => {
                           capabilities => {
                                            definitionProvider     => \1,
                                            documentSymbolProvider => \1,
                                            hoverProvider          => \1,
                                            signatureHelpProvider  => {
                                                                      triggerCharacters => ['(', ',']
                                                                     },
                                            textDocumentSync => {
                                                                 openClose => \1,
                                                                 change    => 2,
                                                                 save => \1
                                                                },
                                            documentFormattingProvider      => \1,
                                            documentRangeFormattingProvider => \1,
                                            completionProvider              => {
                                                                   triggerCharacters => ['>', ':', '$', '@', '%'],
                                                                   resolveProvider   => \1
                                                                  },
                                            executeCommandProvider => {
                                                commands => [
                                                    'perl.sortImports'
                                                ]
                                            }
                                           }
                          }
               );

    return bless \%self, $class;
} ## end sub new

1;
