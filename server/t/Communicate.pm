package t::Communicate;

use strict;
use warnings;

use IO::Handle;
use IO::Select;
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
        close $server_err_fh;

        my $self = {
                    pid       => $pid,
                    read_fh   => $client_read_fh,
                    write_fh  => $client_write_fh,
                    err_fh    => $client_err_fh,
                    read_buff => '',
                    err_buff  => '',
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
    } ## end else[ if ($pid)]

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

    my %headers;

    if (not $self->_read_headers(\%headers) and IO::Select->new($self->{read_fh})->can_read(20))
    {
        while (sysread $self->{read_fh}, $self->{read_buff}, 16 * 1024, length $self->{read_buff})
        {
            last if $self->_read_headers(\%headers);
        }
    } ## end if (not $self->_read_headers...)

    return unless $headers{'Content-Length'};

    if (length $self->{read_buff} < $headers{'Content-Length'})
    {
        my $read = $headers{'Content-Length'} - length $self->{read_buff};
        sysread $self->{read_fh}, $self->{read_buff}, $read, length $self->{read_buff};
    }

    my $json = substr $self->{read_buff}, 0, $headers{'Content-Length'}, '';

    return eval { JSON::PP->new->utf8->decode($json) };
} ## end sub recv_message

sub _read_headers
{
    my ($self, $headers) = @_;

    while ($self->{read_buff} =~ s/^(.*)\r\n//g)
    {
        return 1 unless (length $1);
        my ($name, $value) = split /: /, $1;
        $headers->{$name} = $value;
    } ## end while ($self->{read_buff}...)

    return 0;
} ## end sub _read_headers

sub send_message_and_recv_response
{
    my ($self, $message) = @_;

    $self->send_message($message);
    return $self->recv_message();
} ## end sub send_message_and_recv_response

sub send_raw_message
{
    my ($self, $message) = @_;

    if (IO::Select->new($self->{write_fh})->can_write(10))
    {
        syswrite $self->{write_fh}, $message;
    }
    else
    {
        die "failed write: $!";
    }

    return;
} ## end sub send_raw_message

sub recv_err
{
    my ($self) = @_;

    if ($self->{err_buff} =~ s/^(.*)\n//)
    {
        return $1;
    }

    if (IO::Select->new($self->{err_fh})->can_read(10))
    {
        while (sysread $self->{err_fh}, $self->{err_buff}, 16 * 1024, length $self->{err_buff})
        {
            if ($self->{err_buff} =~ s/^(.*)\n//)
            {
                return $1;
            }
        } ## end while (sysread $self->{err_fh...})
    } ## end if (IO::Select->new($self...))

    return;
} ## end sub recv_err

sub stop_server
{
    my ($self) = @_;

    kill 'TERM', $self->{pid};
    waitpid $self->{pid}, 0;

    return;
} ## end sub stop_server

1;
