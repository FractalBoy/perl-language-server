package PLS::Server::Response::InitializeResult;

use strict;
use warnings;

use parent q(PLS::Server::Response);

use JSON::PP;

use PLS::Server::State;

=head1 NAME

PLS::Server::Response::InitializeResult

=head1 DESCRIPTION

This is a message from the server to the client with the result
of initialization.

This message contains information about the server's capabilities.

=cut

sub new
{
    my ($class, $request) = @_;

    my %self = (
                id     => $request->{id},
                result => {
                           capabilities => {
                                            definitionProvider     => JSON::PP::true,
                                            documentSymbolProvider => JSON::PP::true,
                                            hoverProvider          => JSON::PP::true,
                                            signatureHelpProvider  => {
                                                                      triggerCharacters => ['(', ',']
                                                                     },
                                            textDocumentSync => {
                                                                 openClose => JSON::PP::true,
                                                                 change    => 2,
                                                                 save => JSON::PP::true,
                                                                },
                                            documentFormattingProvider      => JSON::PP::true,
                                            documentRangeFormattingProvider => JSON::PP::true,
                                            completionProvider              => {
                                                                   triggerCharacters => ['>', ':', '$', '@', '%'],
                                                                   resolveProvider   => JSON::PP::true,
                                                                  },
                                            executeCommandProvider => {
                                                commands => [
                                                    'perl.sortImports'
                                                ]
                                            },
                                            workspaceSymbolProvider => JSON::PP::true
                                           }
                          }
               );

    return bless \%self, $class;
} ## end sub new

sub serialize
{
    my ($self) = @_;

    $PLS::Server::State::INITIALIZED = 1;
    return $self->SUPER::serialize();
}

1;
