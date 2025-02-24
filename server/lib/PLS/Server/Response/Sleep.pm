package PLS::Server::Response::Sleep;

use strict;
use warnings;

use parent 'PLS::Server::Response';

use IO::Async::Loop;
use IO::Async::Timer::Countdown;

sub new
{
    my ($class, $request) = @_;

    my $self = bless {
                      id     => $request->{id},
                      result => undef
                     }, $class;

    my $loop   = IO::Async::Loop->new();
    my $future = $loop->new_future();
    $future->set_label('sleep');
    my $timer = IO::Async::Timer::Countdown->new(
        delay     => 10,
        on_expire => sub {
            $future->done($self);
        },
        remove_on_expire => 1
    );
    $timer->start();
    $loop->add($timer);

    return $future;
} ## end sub new

1;
