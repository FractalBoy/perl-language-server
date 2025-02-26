package PLS::Server::Response::Sleep;

use strict;
use warnings;

use parent 'PLS::Server::Response';

use IO::Async::Loop;
use IO::Async::Timer::Countdown;

=head1 NAME

PLS::Server::Response::Sleep

=head1 DESCRIPTION

This is not a real language server response - it is only used for testing.

It will wait the requested delay in seconds before returning an empty response.

=cut

sub new
{
    my ($class, $request) = @_;

    my $self = bless {
                      id     => $request->{id},
                      result => undef
                     }, $class;

    my $loop   = IO::Async::Loop->new();
    my $future = $loop->new_future();

    my $timer = IO::Async::Timer::Countdown->new(
        delay     => $request->{params}{delay},
        on_expire => sub {
            $future->done($self);
        },
        remove_on_expire => 1
    );
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

1;
