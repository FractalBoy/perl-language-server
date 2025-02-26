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

# Install $SIG{__WARN__} handler to hide warnings coming from IO::Async and Future.
$SIG{__WARN__} = sub {    ## no critic (RequireLocalizedPunctuationVars)
    my ($warning) = @_;

    if (   $warning =~ m{Deep recursion on subroutine "Future.+(?:done|on_ready)"}
        or $warning =~ m{Use of uninitialized value \$events in bitwise and (&).*IO/Async/Loop/Poll.pm})
    {
        return;
    }

    warn $warning;
    return;
}; ## end sub

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
            return $self->send_message($message);
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
        $request->on_done(
            sub {
                my ($request) = @_;
                $self->handle_server_request($request);
            }
        );
    } ## end elsif ($request->isa('Future'...))

    return;
} ## end sub send_server_request

sub send_message
{
    my ($self, $message) = @_;

    return Future->done() if (not blessed($message) or not $message->isa('PLS::Server::Message'));
    my $json   = $message->serialize();
    my $length = length ${$json};
    return $self->{stream}->write("Content-Length: $length\r\n\r\n$$json");
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
        return $self->send_message($response);
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
                return $self->send_message($response);
            }
          )->on_cancel(
            sub {
                $self->send_message(PLS::Server::Response::Cancelled->new(id => $id))->await();
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
        return $request->handle_response($response, $self);
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

    $self->send_message($request)->await();
    return;
} ## end sub handle_server_request

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
