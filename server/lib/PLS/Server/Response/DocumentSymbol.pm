package PLS::Server::Response::DocumentSymbol;

use strict;
use warnings;

use parent 'PLS::Server::Response';

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

    # Document symbols are requested and canceled very often. We should wait to make sure
    # that we aren't requesting them too quickly.
    my $loop   = IO::Async::Loop->new();
    my $future = $loop->new_future();
    my $timer = IO::Async::Timer::Countdown->new(delay     => 2,
                                                 on_expire => sub { $self->on_expire($uri, $future) });
    $timer->start();
    $loop->add($timer);

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

    if ($future->is_ready)
    {
        return;
    }

    my $version = PLS::Parser::Document::uri_version($uri);

    PLS::Parser::DocumentSymbols->get_all_document_symbols_async($uri)->then(
        sub {
            my ($symbols) = @_;

            if ($future->is_ready)
            {
                return Future->done();
            }

            my $current_version = PLS::Parser::Document::uri_version($uri);

            if (not length $current_version or length $version and $current_version > $version)
            {
                $future->done($self);
                return Future->done();
            }

            $self->{result} = $symbols;
            $future->done($self);
            return Future->done();
        }
    )->get();

    return;
} ## end sub on_expire

1;
