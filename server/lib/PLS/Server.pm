package PLS::Server;

use strict;
use warnings;

use AnyEvent;
use AnyEvent::Loop;
use Coro;
use Coro::Channel;
use JSON;
use List::Util qw(first);
use Scalar::Util;

use PLS::Server::Request;
use PLS::Server::Response;
use PLS::Server::Response::Cancelled;

sub new
{
    my ($class) = @_;

    return bless {}, $class;
}

sub recv
{
    my ($self) = @_;

    my %headers;
    my $line;
    my $buffer;

    while (sysread STDIN, $buffer, 1)
    {
        $line .= $buffer;
        last if $line eq "\r\n";
        next unless $line =~ /\r\n$/;
        $line =~ s/^\s+|\s+$//g;
        my ($field, $value) = split /: /, $line;
        $headers{$field} = $value;
        $line = '';
    } ## end while (sysread STDIN, $buffer...)

    my $size = $headers{'Content-Length'};
    die 'no Content-Length header provided' unless $size;

    my $raw;
    my $bytes_read = -1;
    my $total_read = 0;

    while ($bytes_read)
    {
        $bytes_read = sysread STDIN, $raw, $size - $total_read, $total_read;
        die "failed to read: $!" unless (defined $bytes_read);

        $total_read += $bytes_read;
    } ## end while ($bytes_read)

    die 'content length does not match header' if ($total_read != $size);
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

    syswrite STDOUT, "Content-Length: $size\r\n\r\n$json";
} ## end sub send

sub run
{
    my ($self) = @_;

    my $client_requests  = Coro::Channel->new;
    my $server_responses = Coro::Channel->new;
    my $server_requests  = Coro::Channel->new;
    my $client_responses = Coro::Channel->new;

    $self->{server_requests} = $server_requests;

    my $last_request_id = 0;
    my @pending_requests;
    my %running_coros;

    async
    {
        # check for requests and service them
        while (my $request = $client_requests->get)
        {
            # Handle cancellations by cancelling the Coro and sending an error
            # response indicating the request was cancelled.
            if ($request->{method} eq '$/cancelRequest')
            {
                next unless (exists $running_coros{$request->{params}{id}});
                my $request_to_cancel = $running_coros{$request->{params}{id}};

                next unless (ref $request_to_cancel eq 'Coro');
                $request_to_cancel->cancel();

                delete $running_coros{$request->{params}{id}};

                my $canceled_response = PLS::Server::Response::Cancelled->new(id => $request->{params}{id});
                $server_responses->put($canceled_response);

                next;
            } ## end if ($request->{method}...)

            my $coro = async
            {
                my ($request) = @_;

                my $response = $request->service($self);
                delete $running_coros{$request->{id}} if (length $request->{id});
                return unless Scalar::Util::blessed($response);
                $server_responses->put($response);
            } ## end async
            $request;

            $running_coros{$request->{id}} = $coro if (length $request->{id});
            Coro::cede();
        } ## end while (my $request = $client_requests...)
    };

    async
    {
        # check for responses and send them
        while (my $response = $server_responses->get)
        {
            async
            {
                my ($response) = @_;
                $self->send($response);
            }
            $response;

            Coro::cede();
        } ## end while (my $response = $server_responses...)
    };

    async
    {
        while (my $request = $server_requests->get)
        {
            $request->{id} = ++$last_request_id;
            push @pending_requests, $request;

            async
            {
                my ($request) = @_;
                $self->send($request);
            }
            $request;

            Coro::cede();
        } ## end while (my $request = $server_requests...)
    };

    async
    {
        while (my $response = $client_responses->get)
        {
            my $request = first { $_->{id} == $response->{id} } @pending_requests;
            next unless Scalar::Util::blessed($request);
            @pending_requests = grep { $_->{id} != $response->{id} } @pending_requests;

            async
            {
                my ($request, $response) = @_;
                $request->handle_response($response);
            }
            $request, $response;

            Coro::cede();
        } ## end while (my $response = $client_responses...)
    };

    my $io_watcher = AnyEvent->io(
        fh   => \*STDIN,
        poll => 'r',
        cb   => sub {
            my $message = $self->recv();
            return unless Scalar::Util::blessed($message);

            if ($message->isa('PLS::Server::Request'))
            {
                $client_requests->put($message);
            }
            if ($message->isa('PLS::Server::Response'))
            {
                $client_responses->put($message);
            }
        }
    );

    AnyEvent::Loop::run();
} ## end sub run

1;
