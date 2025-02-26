package PLS::Server;

use strict;
use warnings;

use Future;
use Future::Queue;
use Future::Utils;
use IO::Async::Loop;
use IO::Async::Signal;
use IO::Async::Stream;
use IO::Handle;
use Scalar::Util qw(blessed);

use PLS::JSON;
use PLS::Server::Request::Factory;
use PLS::Server::Response;
use PLS::Server::Response::Cancelled;

=head1 NAME

PLS::Server

=head1 DESCRIPTION

Perl Language Server

This server communicates to a language client through STDIN/STDOUT.

=head1 SYNOPSIS

    my $server = PLS::Server->new();
    my $exit_code = $server->run();

    exit $exit_code;

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
        autoflush => 0,
        on_read   => sub {
            my ($stream, $buffref, $eof) = @_;

            exit if $eof;

            my @futures;

            while (${$buffref} =~ s/^(.*?)\r\n\r\n//s)
            {
                my $headers = $1;

                my %headers = map { split /: / } grep { length } split /\r\n/, $headers;
                my $size    = $headers{'Content-Length'};
                die 'no Content-Length header provided' unless $size;

                if (length ${$buffref} < $size)
                {
                    ${$buffref} = "$headers\r\n\r\n${$buffref}";
                    return 0;
                }

                my $json    = substr ${$buffref}, 0, $size, '';
                my $content = decode_json $json;

                push @futures, $self->handle_client_message($content);
            } ## end while (${$buffref} =~ s/^(.*?)\r\n\r\n//s...)

            Future->wait_all(@futures)->get();
            return 0;
        }
    );

    $self->{loop}->add($self->{stream});
    $self->{loop}->add(
                       IO::Async::Signal->new(name       => 'TERM',
                                              on_receipt => sub { $self->stop(0) })
                      )
      if ($^O ne 'MSWin32');

    my $exit_code = $self->{loop}->run();

    return (length $exit_code) ? $exit_code : 1;
} ## end sub run

sub handle_client_message
{
    my ($self, $message) = @_;

    if (length $message->{method})
    {
        $message = PLS::Server::Request::Factory->new($message);

        if (blessed($message) and $message->isa('PLS::Server::Response'))
        {
            $self->send_message($message);
            return;
        }
    } ## end if (length $message->{...})
    else
    {
        $message = PLS::Server::Response->new($message);
    }

    return unless blessed($message);

    if ($message->isa('PLS::Server::Request'))
    {
        return $self->handle_client_request($message);
    }
    if ($message->isa('PLS::Server::Response'))
    {
        return $self->handle_client_response($message);
    }

    return;
} ## end sub handle_client_message

sub send_server_request
{
    my ($self, $request) = @_;

    return unless blessed($request);

    if ($request->isa('PLS::Server::Request'))
    {
        $self->handle_server_request($request);
    }
    elsif ($request->isa('Future'))
    {
        $request = $request->get();
        $self->handle_server_request($request);
    }

    return;
} ## end sub send_server_request

sub send_message
{
    my ($self, $message) = @_;

    return if (not blessed($message) or not $message->isa('PLS::Server::Message'));
    my $json   = $message->serialize();
    my $length = length ${$json};
    $self->{stream}->write("Content-Length: $length\r\n\r\n$$json")->get();

    return;
} ## end sub send_message

sub handle_client_request
{
    my ($self, $request) = @_;

    my $response = $request->service($self);

    if (not blessed($response))
    {
        return;
    }

    if ($response->isa('PLS::Server::Response'))
    {
        $self->send_message($response);
        return;
    }
    elsif ($response->isa('Future'))
    {
        my $id = $request->{id};

        if (length $id)
        {
            $self->{running_futures}{$id} = $response;
        }

        my $future = $response->then(
            sub {
                my ($response) = @_;

                warn "sending response for id $id\n";
                $self->send_message($response);
                return Future->done();
            }
          )->on_cancel(
            sub {
                $self->send_message(PLS::Server::Response::Cancelled->new(id => $id));
            }
          );

        # Kind of silly, but the sequence future doesn't get cancelled automatically -
        # we need to set that up ourselves.
        $response->on_cancel($future);

        return $future;
    } ## end elsif ($response->isa('Future'...))

    return;
} ## end sub handle_client_request

sub handle_client_response
{
    my ($self, $response) = @_;

    my $request = $self->{pending_requests}{$response->{id}};

    if (blessed($request) and $request->isa('PLS::Server::Request'))
    {
        $request->handle_response($response, $self);
    }

    return;
} ## end sub handle_client_response

sub handle_server_request
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

    $self->send_message($request);
    return;
} ## end sub handle_server_request

sub handle_server_response
{
    my ($self, $response) = @_;

    $self->send_message($response);
    return;
} ## end sub handle_server_response

sub cancel_request
{
    my ($self, $id) = @_;

    my $future = delete $self->{running_futures}{$id};

    if (blessed($future) and $future->isa('Future'))
    {
        $future->cancel();
    }

    return;
} ## end sub cancel_request

sub stop
{
    my ($self, $exit_code) = @_;

    $self->{loop}->stop($exit_code);

    return;
} ## end sub stop

1;
