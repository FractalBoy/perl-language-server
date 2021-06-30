package PLS::Server::Request::Diagnostics::PublishDiagnostics;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use Fcntl ();
use File::Spec;
use IPC::Open3;
use Perl::Critic;
use Storable;
use Symbol qw(gensym);
use URI;

use PLS::Parser::Pod;
use PLS::Server::State;

=head1 NAME

PLS::Server::Request::Diagnostics::PublishDiagnostics

=head1 DESCRIPTION

This is a message from the server to the client requesting that
diagnostics be published.

These diagnostics currently include compilation errors and linting (using L<perlcritic>).

=cut

sub new
{
    my ($class, %args) = @_;

    my $uri  = $args{uri};
    my $path = URI->new($uri);

    return unless (ref $path eq 'URI::file');
    $path = $path->file;

    my @diagnostics;

    if (not $args{close})
    {
        push @diagnostics, @{get_compilation_errors($path)} if (defined $PLS::Server::State::CONFIG->{syntax}{enabled} and $PLS::Server::State::CONFIG->{syntax}{enabled});
        push @diagnostics, @{get_perlcritic_errors($path)} if (defined $PLS::Server::State::CONFIG->{perlcritic}{enabled} and $PLS::Server::State::CONFIG->{perlcritic}{enabled});
    }

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

sub get_compilation_errors
{
    my ($path) = @_;

    my $inc = PLS::Parser::Pod->get_clean_inc();
    my @inc = map { "-I$_" } @{$inc // []};

    my @line_lengths;
    my $pid = open my $fh, '<', $path or return [];

    while (my $line = <$fh>)
    {
        chomp $line;
        $line_lengths[$.] = length $line;
    }

    waitpid $pid, 0;

    my $perl = $PLS::Server::State::CONFIG->{syntax}{perl};
    $perl = $^X unless (length $perl);
    $pid = open3 my $in, my $out, my $err = gensym, $perl, @inc, '-c', $path or return [];
    close $in;
    close $out;

    my @diagnostics;

    while (my $line = <$err>)
    {
        chomp $line;
        next if $line =~ /syntax OK$/;

        # Hide warnings from circular references
        next if $line =~ /Subroutine .+ redefined/;

        # Hide "BEGIN failed" and "Compilation failed" messages - these provide no useful info.
        next if $line =~ /^BEGIN failed/;
        next if $line =~ /^Compilation failed/;
        if (my ($error, $file, $line, $area) = $line =~ /^(.+) at (.+) line (\d+)(, .+)?/)
        {
            $error .= $area if (length $area);
            $line = int $line;
            next if $file ne $path;

            push @diagnostics,
              {
                range => {
                          start => {line => $line - 1, character => 0},
                          end   => {line => $line - 1, character => $line_lengths[$line]}
                         },
                message  => $error,
                severity => 1,
                source   => 'perl',
              };
        } ## end if (my ($error, $file,...))
    } ## end while (my $line = <$err>)

    waitpid $pid, 0;

    return \@diagnostics;
} ## end sub get_compilation_errors

sub get_perlcritic_errors
{
    my ($path) = @_;

    my ($profile) = glob $PLS::Server::State::CONFIG->{perlcritic}{perlcriticrc};
    undef $profile if (not length $profile or not -f $profile or not -r $profile);
    my $critic     = Perl::Critic->new(-profile => $profile);
    my @violations = $critic->critique($path);

    my @diagnostics;

    foreach my $violation (@violations)
    {
        my $severity = 5 - $violation->severity;
        $severity = 1 unless ($severity);

        my $doc = URI->new();
        $doc->scheme('https');
        $doc->authority('metacpan.org');
        $doc->path('pod/' . $violation->policy);

        push @diagnostics,
          {
            range => {
                      start => {line => $violation->line_number - 1, character => $violation->column_number - 1},
                      end   => {line => $violation->line_number - 1, character => $violation->column_number + length($violation->source) - 1}
                     },
            message         => $violation->description,
            code            => $violation->policy,
            codeDescription => {href => $doc->as_string},
            severity        => $severity,
            source          => 'perlcritic'
          };
    } ## end foreach my $violation (@violations...)

    return \@diagnostics;
} ## end sub get_perlcritic_errors

1;
