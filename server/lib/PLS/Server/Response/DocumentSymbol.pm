package PLS::Server::Response::DocumentSymbol;

use strict;
use warnings;

use parent 'PLS::Server::Response';

use IO::Async::Loop;

use PLS::Parser::Document;
use PLS::Parser::DocumentSymbols;

=head1 NAME

PLS::Server::Response::DocumentSymbol

=head1 DESCRIPTION

This is a message from the server to the client with a list
of symbols in the current document.

=cut

sub new
{
    my ($class, $request) = @_;

    my $self = bless {id => $request->{id}, result => undef}, $class;

    my $uri     = $request->{params}{textDocument}{uri};
    my $version = PLS::Parser::Document::uri_version($uri);

    return PLS::Parser::DocumentSymbols->get_all_document_symbols_async($uri)->then(
        sub {
            my ($symbols) = @_;

            my $current_version = PLS::Parser::Document::uri_version($uri);
            return Future->done($self) unless (length $current_version);
            return Future->done($self) if (length $version and $current_version > $version);

            $self->{result} = $symbols;
            return Future->done($self);
        },
        sub {
            return Future->done($self);
        }
    );
} ## end sub new

1;
