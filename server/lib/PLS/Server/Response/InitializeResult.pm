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

    my $supports_semantic_tokens = $PLS::Server::State::CLIENT_CAPABILITIES->{textDocument}{semanticTokens}{requests}{full};

    if (not $supports_semantic_tokens)
    {
        warn "client does not support semantic tokens\n";
    }

    # if ($supports_semantic_tokens)
    # {
    #     $supports_semantic_tokens = $PLS::Server::State::CLIENT_CAPABILITIES->{textDocument}{semanticTokens}{requests}{augmentsSyntaxTokens};
    #     if (not $supports_semantic_tokens)
    #     {
    #         warn "client does not support semantic tokens augmenting syntax tokens\n";
    #     }
    # } ## end if ($supports_semantic_tokens...)

    my @token_types = qw(keyword function class number modifier);

    if ($supports_semantic_tokens)
    {
        foreach my $required_token (@token_types)
        {
            if (List::Util::none { $_ eq $required_token } @{$PLS::Server::State::CLIENT_CAPABILITIES->{textDocument}{semanticTokens}{tokenTypes} || []})
            {
                warn "client does not support semantic token type '$required_token'\n";
                $supports_semantic_tokens = 0;
                last;
            } ## end if (List::Util::none {...})
        } ## end foreach my $required_token ...
    } ## end if ($supports_semantic_tokens...)

    if ($supports_semantic_tokens)
    {
        warn "supports semantic tokens\n";
        $self{result}{capabilities}{semanticTokensProvider} = {
                                                               legend => {
                                                                          tokenTypes     => \@token_types,
                                                                          tokenModifiers => []
                                                                         },
                                                               range => PLS::JSON::false,
                                                               full  => {delta => PLS::JSON::false}
                                                              };
    } ## end if ($supports_semantic_tokens...)

    return bless \%self, $class;
} ## end sub new

sub serialize
{
    my ($self) = @_;

    $PLS::Server::State::INITIALIZED = 1;
    return $self->SUPER::serialize();
} ## end sub serialize

1;
