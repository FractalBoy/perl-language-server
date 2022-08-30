package PLS::Server::Response::DocumentSymbol;

use strict;
use warnings;

use parent 'PLS::Server::Response';

use feature 'state';

use IO::Async::Loop;
use IO::Async::Timer::Countdown;

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

    my $uri = $request->{params}{textDocument}{uri};

    # Delay document symbols by a couple of seconds to allow cancelling before processing starts.
    my $future = Future->new();
    my $timer = IO::Async::Timer::Countdown->new(
                                                 delay            => 2,
                                                 on_expire        => sub { $self->on_expire($uri, $future) },
                                                 remove_on_expire => 1
                                                );

    IO::Async::Loop->new->add($timer->start());

    # When the future is canceled, make sure to stop the timer so that it never actually starts generating document symbols.
    $future->on_cancel(
        sub {
            $timer->stop();
            $timer->remove_from_parent();
        }
    );

    return $future;
} ## end sub new

sub on_expire
{
    my ($self, $uri, $future) = @_;

    my $version = PLS::Parser::Document::uri_version($uri);

    PLS::Parser::DocumentSymbols->get_all_document_symbols_async($uri)->on_done(
        sub {
            my ($symbols) = @_;

            my $current_version = PLS::Parser::Document::uri_version($uri);

            if (not length $current_version or length $version and $current_version > $version)
            {
                $future->done($self);
                return;
            }

            $self->{result} = $symbols;
            $future->done($self);
        }
      )->on_fail(
        sub {
            $future->done($self);
        }
    )->retain();
} ## end sub on_expire

1;
