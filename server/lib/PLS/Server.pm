package PLS::Server;

use strict;
use warnings;

use Future::Queue;
use Future::Utils;
use IO::Async::Loop;
use IO::Async::Signal;
use IO::Async::Stream;
use IO::Handle;
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

    $self->{client_requests}  = Future::Queue->new();
    $self->{client_responses} = Future::Queue->new();
    $self->{server_requests}  = Future::Queue->new();
    $self->{server_responses} = Future::Queue->new();

    Future::Utils::repeat
    {
        $self->{client_requests}->shift->on_done(
            sub {
                my ($request) = @_;
                $self->handle_client_request($request);
            }
        );
    } ## end Future::Utils::repeat
    while => sub { 1 };

    Future::Utils::repeat
    {
        $self->{client_responses}->shift->on_done(
            sub {
                my ($response) = @_;
                $self->handle_client_response($response);
            }
        );
    } ## end Future::Utils::repeat
    while => sub { 1 };

    Future::Utils::repeat
    {
        $self->{server_requests}->shift->then(
            sub {
                my ($request) = @_;
                $self->handle_server_request($request);
            }
        );
    } ## end Future::Utils::repeat
    while => sub { 1 };

    Future::Utils::repeat
    {
        $self->{server_responses}->shift->then(
            sub {
                my ($response) = @_;
                $self->handle_server_response($response);
            }
        );
    } ## end Future::Utils::repeat
    while => sub { 1 };

    STDOUT->blocking(0);

    $self->{stream} = IO::Async::Stream->new_for_stdio(
        autoflush => 1,
        on_read   => sub {
            my $line = '';
            my @lines;

            return sub {
                my ($stream, $buffref, $eof) = @_;

                exit if $eof;

                $line .= substr $$buffref, 0, 1, '';

                if ($line eq "\r\n")
                {
                    my %headers = map { split /: / } @lines;

                    return sub {
                        my ($stream, $buffref, $eof) = @_;

                        exit if $eof;

                        my $size = $headers{'Content-Length'};
                        die 'no Content-Length header provided' unless $size;

                        return 0 if (length($$buffref) < $size);

                        my $json    = substr $$buffref, 0, $size, '';
                        my $content = JSON::PP->new->utf8->decode($json);

                        $self->handle_client_message($content);
                        return;
                    }
                } ## end if ($line eq "\r\n")
                if ($line =~ /\r\n$/)
                {
                    $line =~ s/^\s+|\s+$//g;
                    push @lines, $line;
                    $line = '';
                } ## end if ($line =~ /\r\n$/)

                return 1;
            }
        }
    );

    $self->{loop}->add($self->{stream});
    $self->{loop}->add(IO::Async::Signal->new(name => 'TERM', on_receipt => sub { exit; })) if ($^O ne 'MSWin32');

    $self->{loop}->loop_forever();

    return;
} ## end sub run

sub handle_client_message
{
    my ($self, $message) = @_;

    if (length $message->{method})
    {
        $message = PLS::Server::Request::Factory->new($message);

        if (blessed($message) and $message->isa('PLS::Server::Response'))
        {
            $self->{server_responses}->push($message);
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
        $self->{client_requests}->push($message);
    }
    if ($message->isa('PLS::Server::Response'))
    {
        $self->{client_responses}->push($message);
    }

    return;
} ## end sub handle_client_message

sub send_server_request
{
    my ($self, $request) = @_;

    $self->{server_requests}->push($request);
    return;
}

sub send_message
{
    my ($self, $message) = @_;

    return if (not blessed($message) or not $message->isa('PLS::Server::Message'));
    my $json   = $message->serialize();
    my $length = length $json;
    return $self->{stream}->write("Content-Length: $length\r\n\r\n$json");
} ## end sub send_message

sub handle_client_request
{
    my ($self, $request) = @_;

    my $response = $request->service($self);

    if (blessed($response) and $response->isa('PLS::Server::Response'))
    {
        $self->{server_responses}->push($response);
    }

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

    return $self->send_message($request);
} ## end sub handle_server_request

sub handle_server_response
{
    my ($self, $response) = @_;

    return $self->send_message($response);
}

1;
