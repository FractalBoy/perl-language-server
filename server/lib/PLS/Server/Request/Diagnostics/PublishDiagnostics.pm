package PLS::Server::Request::Diagnostics::PublishDiagnostics;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use File::Spec;
use IPC::Open3;
use Symbol qw(gensym);

use PLS::Parser::Pod;

sub new
{
    my ($class, %args) = @_;

    my $uri  = $args{uri};
    my $path = URI->new($uri)->file;
    my $inc  = PLS::Parser::Pod->get_clean_inc();
    my @inc  = map { "-I$_" } @{$inc // []};

    my @line_lengths;
    my $pid = open my $fh, '<', $path;

    while (my $line = <$fh>)
    {
        chomp $line;
        $line_lengths[$.] = length $line;
    }

    waitpid $pid, 0;

    $pid = open3 my $in, my $out, my $err = gensym, $^X, @inc, '-c', $path or return;
    close $in;
    close $out;

    my @diagnostics;

    while (my $line = <$err>)
    {
        chomp $line;
        next if $line =~ /syntax OK$/;
        if (my ($error, $file, $line, $area) = $line =~ /^(.+) at (.+) line (\d+)(, .+)?/)
        {
            $error .= $area if (length $area);
            $line = int $line;

            push @diagnostics,
              {
                range => {
                          start => {line => $line, character => 0},
                          end   => {line => $line, character => $line_lengths[$line]}
                         },
                message  => $error,
                severity => 1,
                source   => 'perl',
              };
        } ## end if (my ($error, $file,...))
    } ## end while (my $line = <$err>)

    waitpid $pid, 0;

    my $self = {
        method => 'textDocument/publishDiagnostics',
        params => {
                   uri         => $uri,
                   diagnostics => \@diagnostics
                  },
        notification => 1    # indicates to the server that this should not be assigned an id, and that there will be no response
               };

    return bless $self, $class;
} ## end sub new

1;
