package PLS::Server;

use strict;

use AnyEvent;
use AnyEvent::Loop;
use Coro;
use Coro::AnyEvent;
use Coro::Debug;
use Coro::Handle;
use JSON;
use Scalar::Util;

use PLS::Server::Request;
use PLS::Server::Response;
use PLS::Server::State;

our $unix_server = Coro::Debug->new_unix_server('/tmp/coro.sock');

sub new
{
    my ($class, $readfh, $writefh) = @_;

    my $readfh  = $readfh  || \*STDIN;
    my $writefh = $writefh || \*STDOUT;

    my %self = (
                readfh  => Coro::Handle->new_from_fh($readfh),
                writefh => Coro::Handle->new_from_fh($writefh)
               );

    return bless \%self, $class;
} ## end sub new

sub recv
{
    my ($self) = @_;

    my %headers;
    my $readfh = $self->{readfh};
    my $line;

    while ($readfh->readable && $readfh->sysread(my $buffer, 1))
    {
        $line .= $buffer;
        last if $line eq "\r\n";
        next unless $line =~ /\r\n$/;
        $line =~ s/^\s+|\s+$//g;
        my ($field, $value) = split /: /, $line;
        $headers{$field} = $value;
        $line = '';
    } ## end while ($readfh->readable ...)

    my $size = $headers{'Content-Length'};
    die 'no Content-Length header provided' unless $size;

    my $length = $readfh->sysread(my $raw, $size) if $readfh->readable;
    die 'content length does not match header' unless $length == $size;
    my $content = decode_json $raw;

    if (length $content->{method})
    {
        return PLS::Server::Request->new($content);
    }
    else
    {
        return PLS::Server::Response->new($content);
    }
} ## end sub recv

sub send
{
    my ($self, $response) = @_;

    my $json = $response->serialize;
    my $size = length $json;

    $self->{writefh}->syswrite("Content-Length: $size\r\n\r\n") if $self->{writefh}->writable;
    $self->{writefh}->syswrite($json)                           if $self->{writefh}->writable;
} ## end sub send

sub run
{
    my ($self) = @_;

    my $requests         = Coro::Channel->new;
    my $responses        = Coro::Channel->new;
    my $server_requests  = Coro::Channel->new;
    my $client_responses = Coro::Channel->new;

    $self->{server_requests}  = $server_requests;
    my $last_request_id  = 0;
    my @pending_requests;

    my $stderr = Coro::Handle->new_from_fh(\*STDERR);

    async
    {
        # check for requests and service them
        while (my $request = $requests->get)
        {
            my $response = $request->service($self);
            next unless Scalar::Util::blessed($response);
            $responses->put($response);
        } ## end while (my $request = $requests...)
    } ## end async

    async
    {
        # check for responses and send them
        while (my $response = $responses->get)
        {
            $self->send($response);
        }
    };

    async
    {
        while (my $request = $server_requests->get)
        {
            $request->{id} = ++$last_request_id;
            push @pending_requests, $request;
            $self->send($request);
        } ## end while (my $request = $server_requests...)
    };

    async
    {
        while (my $response = $client_responses->get)
        {
            my ($request) = grep { $_->{id} == $response->{id} } @pending_requests;
            next unless Scalar::Util::blessed($request);
            @pending_requests = grep { $_->{id} != $response->{id} } @pending_requests;
            $request->handle_response($response);
        } ## end while (my $response = $client_responses...)
    };    ## end async

    # main loop
    while (1)
    {
        # check for requests and drop them on the channel to be serviced by existing threads
        my $message = $self->recv;
        next unless Scalar::Util::blessed($message);

        if ($message->isa('PLS::Server::Request'))
        {
            $requests->put($message);
        }
        if ($message->isa('PLS::Server::Response'))
        {
            $client_responses->put($message);
        }
    } ## end while (1)
} ## end sub run

1;
