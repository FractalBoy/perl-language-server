package t::Communicate;

use strict;
use warnings;

use IO::Handle;
use JSON::PP;

use PLS::Server;

sub new
{
    my ($class) = @_;

    pipe my $client_read_fh, my $server_write_fh;
    pipe my $server_read_fh, my $client_write_fh;
    pipe my $client_err_fh,  my $server_err_fh;

    $client_read_fh->autoflush();
    $client_write_fh->autoflush();
    $server_read_fh->autoflush();
    $server_write_fh->autoflush();

    my $pid = fork;

    if ($pid)
    {
        close $server_read_fh;
        close $server_write_fh;

        my $self = {
                    pid      => $pid,
                    read_fh  => $client_read_fh,
                    write_fh => $client_write_fh,
                    err_fh   => $client_err_fh
                   };

        return bless $self, $class;
    } ## end if ($pid)
    else
    {
        close $client_read_fh;
        close $client_write_fh;
        close $client_err_fh;

        open STDOUT, '>&', $server_write_fh;
        open STDIN,  '>&', $server_read_fh;

        open STDERR, '>&', $server_err_fh;
        my $server = PLS::Server->new();
        exit $server->run();
    } ## end else [ if ($pid) ]

    return;
} ## end sub new

sub send_message
{
    my ($self, $message) = @_;

    $message = JSON::PP->new->utf8->encode($message) if (ref $message);
    my $length = length $message;
    $self->send_raw_message("Content-Length: $length\r\n\r\n$message");

    return;
} ## end sub send_message

sub recv_message
{
    my ($self) = @_;

    local $/ = "\r\n";
    my $response = readline $self->{read_fh};
    return unless (length $response);
    readline $self->{read_fh};    # blank line
    my ($content_length) = $response =~ /Content-Length: (\d+)/;
    my $json;
    read $self->{read_fh}, $json, $content_length;

    return eval { JSON::PP->new->utf8->decode($json) };
} ## end sub recv_message

sub send_message_and_recv_response
{
    my ($self, $message) = @_;

    $self->send_message($message);
    return $self->recv_message();
} ## end sub send_message_and_recv_response

sub send_raw_message
{
    my ($self, $message) = @_;

    print {$self->{write_fh}} $message;

    return;
} ## end sub send_raw_message

sub recv_err
{
    my ($self) = @_;

    return readline $self->{err_fh};
}

sub stop_server
{
    my ($self) = @_;

    kill 'TERM', $self->{pid};
    waitpid $self->{pid}, 0;

    return;
} ## end sub stop_server

1;
