package PLS::Server::Request::TextDocument::DidChange;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use feature 'state';

use IO::Async::Loop;
use IO::Async::Timer::Countdown;

use PLS::Parser::Document;
use PLS::Server::Request::Diagnostics::PublishDiagnostics;

=head1 NAME

PLS::Server::Request::TextDocument::DidChange

=head1 DESCRIPTION

This is a notification from the client to the server that
a text document was changed.

=cut

sub service
{
    my ($self, $server) = @_;

    return unless (ref $self->{params}{contentChanges} eq 'ARRAY');
    PLS::Parser::Document->update_file(uri => $self->{params}{textDocument}{uri}, changes => $self->{params}{contentChanges});

    state %timers;

    my $uri = $self->{params}{textDocument}{uri};

    if (ref $timers{$uri} eq 'IO::Async::Timer::Countdown')
    {
        # If we get another change before the timer goes off, reset the timer.
        # This will allow us to limit the diagnostics to a time one second after the user stopped typing.
        $timers{$uri}->reset();
    }
    else
    {
        $timers{$uri} = IO::Async::Timer::Countdown->new(
            delay => 1,
            on_expire => sub {
                my $text = PLS::Parser::Document::text_from_uri($uri);
                $server->send_server_request(PLS::Server::Request::Diagnostics::PublishDiagnostics->new(uri => $uri, unsaved => 1));
                delete $timers{$uri};
            },
            remove_on_expire => 1
        );

        my $loop = IO::Async::Loop->new();
        $loop->add($timers{$uri});
        $timers{$uri}->start();
    }

    return;
}

1;
