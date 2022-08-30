package PLS::Server::Response::InitializeResult;

use strict;
use warnings;

use parent q(PLS::Server::Response);

use PLS::JSON;
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
                                            completionItem => {
                                                               labelDetailsSupport => PLS::JSON::true
                                                              },
                                            definitionProvider     => PLS::JSON::true,
                                            documentSymbolProvider => PLS::JSON::true,
                                            hoverProvider          => PLS::JSON::true,
                                            signatureHelpProvider  => {
                                                                      triggerCharacters => ['(', ',']
                                                                     },
                                            textDocumentSync => {
                                                                 openClose => PLS::JSON::true,
                                                                 change    => 2,
                                                                 save      => PLS::JSON::true,
                                                                },
                                            documentFormattingProvider      => PLS::JSON::true,
                                            documentRangeFormattingProvider => PLS::JSON::true,
                                            completionProvider              => {
                                                                   triggerCharacters => ['>', ':', '$', '@', '%', ' ', '-'],
                                                                   resolveProvider   => PLS::JSON::true,
                                                                  },
                                            executeCommandProvider => {
                                                                       commands => ['pls.sortImports']
                                                                      },
                                            workspaceSymbolProvider => PLS::JSON::true,
                                            workspace               => {
                                                          workspaceFolders => {
                                                                               supported           => PLS::JSON::true,
                                                                               changeNotifications => PLS::JSON::true
                                                                              }
                                                         }
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
} ## end sub serialize

1;
