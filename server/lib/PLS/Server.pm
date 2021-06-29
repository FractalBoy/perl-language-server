package PLS::Server;

use strict;
use warnings;

use IO::Async::Loop;
use IO::Async::Stream;
use JSON::PP;
use Scalar::Util qw(blessed);

use PLS::Server::Request::Factory;
use PLS::Server::Response;

=head1 NAME

PLS::Server

=head1 DESCRIPTION

Perl Language Server

This server communicates to a language client through STDIN/STDOUT.

=head1 SYNOPSIS

    my $server = PLS::Server->new();
    $server->run() # never returns

=cut

sub new
{
    my ($class) = @_;

    return
      bless {
             loop             => IO::Async::Loop->new(),
             stream           => undef,
             running_futures  => {},
             pending_requests => {}
            }, $class;
} ## end sub new

sub run
{
    my ($self) = @_;

    $self->{stream} = IO::Async::Stream->new_for_stdio(
        on_read => sub {
            my ($stream, $buffref, $eof) = @_;

            return 0 if ($$buffref !~ /\r\n\r\n/);

            my ($headers) = $$buffref =~ s/^(.*)\r\n\r\n//s;
            my %headers   = map { split /: /, $_ } split /\r\n/, $headers;

            return 0 if (length $$buffref < $headers{'Content-Length'});

            my $json    = substr $$buffref, 0, $headers{'Content-Length'}, '';
            my $content = JSON::PP->new->utf8->decode($json);

            $self->handle_client_message($content);

            return 1;
        }
    );

    $self->{loop}->add($self->{stream});

    $self->{loop}->loop_forever();

    return;
} ## end sub run

sub handle_client_message
{
    my ($self, $message) = @_;

    if (length $message->{method})
    {
        my $request = PLS::Server::Request::Factory->new($message);
        my $future  = $loop->later();

        $future->on_done(
            sub {
                my $response = $request->service($self);
                $loop->add($self->send_message($response));
            }
        );

        $self->{running_futures}{$request->{id}} = $future;
    } ## end if (length $message->{...})
    else
    {
        my $response = PLS::Server::Response->new($message);

        $loop->later(
            sub {
                my $request = $self->{pending_requests}{$response->{id}};
                return if (not blessed($request) or not $request->isa('PLS::Server::Request'));
                $loop->later(sub { $request->handle_response($response) });
            }
        );
    } ## end else [ if (length $message->{...})]

    return;
} ## end sub handle_client_message

sub send_message
{
    my ($self, $message) = @_;

    return $self->{stream}->write($message->serialize(), autoflush => 1);
}

sub send_server_request
{
    my ($self, $request) = @_;

    if ($request->{notification})
    {
        delete $request->{notification};
    }
    else
    {
        $request->{id} = ++$self->{last_request_id};
        $self->{pending_requests}{$request->{id}} = $request;
    }

    return $self->send_message($request);
} ## end sub send_server_request

1;
