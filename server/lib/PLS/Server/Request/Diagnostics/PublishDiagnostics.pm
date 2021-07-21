package PLS::Server::Request::Diagnostics::PublishDiagnostics;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use Fcntl ();
use File::Basename;
use File::Spec;
use File::Temp;
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

my $function = IO::Async::Function->new(
    min_workers => 4,
    code => sub {
        my ($uri, $unsaved, $text, $config, $root_path, $perl_exe) = @_;

        $PLS::Server::State::CONFIG = $config;
        $PLS::Server::State::ROOT_PATH = $root_path;
        PLS::Parser::Pod->set_perl_exe($perl_exe);
        return PLS::Server::Request::Diagnostics::PublishDiagnostics->new(uri => $uri, text => $text, unsaved => $unsaved);
    }
);

my $loop = IO::Async::Loop->new();
$loop->add($function);
$function->start();

sub new
{
    my ($class, %args) = @_;

    my $uri  = $args{uri};
    my $path = URI->new($uri);

    return unless (ref $path eq 'URI::file');
    $path = $path->file;
    my (undef, $dir, $filename) = File::Spec->splitpath($path);

    my $temp;

    if ($args{unsaved})
    {
        my $text = $args{text};
        $text = PLS::Parser::Document::text_from_uri($uri) if (ref $text ne 'SCALAR');

        if (ref $text eq 'SCALAR')
        {
            $temp = File::Temp->new(DIR => $dir);
            print {$temp} $$text;
            close $temp;
            $path = $temp->filename;
        }
    }

    my @diagnostics;

    if (not $args{close})
    {
        push @diagnostics, @{get_compilation_errors($path)} if (defined $PLS::Server::State::CONFIG->{syntax}{enabled} and $PLS::Server::State::CONFIG->{syntax}{enabled});
        push @diagnostics, @{get_perlcritic_errors($path, $filename, $args{unsaved})} if (defined $PLS::Server::State::CONFIG->{perlcritic}{enabled} and $PLS::Server::State::CONFIG->{perlcritic}{enabled});
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

    my @line_lengths;
    my $pid = open my $fh, '<', $path or return [];

    while (my $line = <$fh>)
    {
        chomp $line;
        $line_lengths[$.] = length $line;
    }

    waitpid $pid, 0;

    my $perl = PLS::Parser::Pod->get_perl_exe();
    my $inc = PLS::Parser::Pod->get_clean_inc();
    my @inc = map { "-I$_" } @{$inc // []};

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
    my ($path, $filename, $unsaved) = @_;

    my ($profile) = glob $PLS::Server::State::CONFIG->{perlcritic}{perlcriticrc};
    undef $profile if (not length $profile or not -f $profile or not -r $profile);
    my $critic     = Perl::Critic->new(-profile => $profile);
    my @violations = $critic->critique($path);

    my @diagnostics;

    # Mapping from perlcritic severity to LSP severity
    my %severity_map = (
        5 => 1,
        4 => 1,
        3 => 2,
        2 => 3,
        1 => 3
    );

    foreach my $violation (@violations)
    {
        my $severity = $severity_map{$violation->severity};

        my $doc = URI->new();
        $doc->scheme('https');
        $doc->authority('metacpan.org');
        $doc->path('pod/' . $violation->policy);

        # Don't report on filename mismatch if this is a temporary file with the wrong name.
        if ($unsaved and $violation->policy eq 'Perl::Critic::Policy::Modules::RequireFilenameMatchesPackage')
        {
            my ($package) = $violation->source =~ /^\s*package\s*(.+?)\s*;?\s*$/;

            my $expected_filename = (split /::/, $package)[-1];
            $expected_filename .= '.pm';

            my $logical_filename = File::Basename::basename($violation->logical_filename);

            next if ($violation->filename ne $violation->logical_filename and $logical_filename eq $expected_filename);
            next if ($violation->filename eq $violation->logical_filename and $filename eq $expected_filename);
        }

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

sub call_diagnostics_function
{
    my ($class, $uri, $unsaved) = @_;

    return Future->done() if (ref $PLS::Server::State::CONFIG ne 'HASH');

    my $text;
    $text = PLS::Parser::Document::text_from_uri($uri) if $unsaved;
    return $function->call(args => [$uri, $unsaved, $text, $PLS::Server::State::CONFIG, $PLS::Server::State::ROOT_PATH, PLS::Parser::Pod->get_perl_exe()]);
}

1;
