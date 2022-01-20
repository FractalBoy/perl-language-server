package PLS::Server::Request::TextDocument::PublishDiagnostics;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use Encode;
use File::Basename;
use File::Path;
use File::Spec;
use File::Temp;
use IO::Async::Function;
use IO::Async::Loop;
use IO::Async::Process;
use Perl::Critic;
use PPI;
use URI;

use PLS::Parser::Pod;
use PLS::Server::State;

=head1 NAME

PLS::Server::Request::TextDocument::PublishDiagnostics

=head1 DESCRIPTION

This is a message from the server to the client requesting that
diagnostics be published.

These diagnostics currently include compilation errors and linting (using L<perlcritic>).

=cut

my $function = IO::Async::Function->new(max_workers => 1,
                                        code        => \&run_perlcritic);

my $loop = IO::Async::Loop->new();
$loop->add($function);

sub new
{
    my ($class, %args) = @_;

    return if (ref $PLS::Server::State::CONFIG ne 'HASH');

    my $uri = URI->new($args{uri});

    return if (ref $uri ne 'URI::file');
    my (undef, $dir) = File::Basename::fileparse($uri->file);

    my $source = $uri->file;

    if ($args{unsaved})
    {
        my $text = PLS::Parser::Document::text_from_uri($uri->as_string);
        $source = $text if (ref $text eq 'SCALAR');
    }

    my @futures;

    push @futures, get_compilation_errors($source, $dir, $args{close}) if (defined $PLS::Server::State::CONFIG->{syntax}{enabled} and $PLS::Server::State::CONFIG->{syntax}{enabled});
    push @futures, get_perlcritic_errors($source, $uri->file, $args{close})
      if (defined $PLS::Server::State::CONFIG->{perlcritic}{enabled} and $PLS::Server::State::CONFIG->{perlcritic}{enabled});


    return Future->wait_all(@futures)->then(
        sub {
            my @diagnostics = map { $_->result } @_;

            my $self = {
                method => 'textDocument/publishDiagnostics',
                params => {
                           uri         => $uri->as_string,
                           diagnostics => \@diagnostics
                          },
                notification => 1    # indicates to the server that this should not be assigned an id, and that there will be no response
                       };

            return Future->done(bless $self, $class);
        }
    );
} ## end sub new

sub get_compilation_errors
{
    my ($source, $dir, $close) = @_;

    my $temp;
    my $future = $loop->new_future();

    if ($close)
    {
        $future->done();
        return $future;
    }

    my $fh;
    my $path;

    if (ref $source eq 'SCALAR')
    {
        $temp = eval { File::Temp->new(CLEANUP => 0, TEMPLATE => '.pls-tmp-XXXXXXXXXX', DIR => $dir) };
        $temp = eval { File::Temp->new(CLEANUP => 0) } if (ref $temp ne 'File::Temp');
        $path = $temp->filename;

        $future->on_done(sub { unlink $temp });
        my $source_text = Encode::encode_utf8($$source);

        print {$temp} $source_text;
        close $temp;

        open $fh, '<', \$source_text;
    } ## end if (ref $source eq 'SCALAR'...)
    else
    {
        $path = $source;
        open $fh, '<', $path or return [];
    }

    my @line_lengths;

    while (my $line = <$fh>)
    {
        chomp $line;
        $line_lengths[$.] = length $line;
    }

    close $fh;

    my $perl = PLS::Parser::Pod->get_perl_exe();
    my $inc  = PLS::Parser::Pod->get_clean_inc();
    my @inc  = map { "-I$_" } @{$inc // []};

    my @diagnostics;

    my $proc = IO::Async::Process->new(
        command => [$perl, @inc, '-c', $path],
        stderr  => {
            on_read => sub {
                my ($stream, $buffref, $eof) = @_;

                while ($$buffref =~ s/^(.*)\n//)
                {
                    my $line = $1;
                    next if $line =~ /syntax OK$/;

                    # Hide warnings from circular references
                    next if $line =~ /Subroutine .+ redefined/;

                    # Hide "BEGIN failed" and "Compilation failed" messages - these provide no useful info.
                    #next if $line =~ /^BEGIN failed/;
                    #next if $line =~ /^Compilation failed/;
                    if (my ($error, $file, $line, $area) = $line =~ /^(.+) at (.+?) line (\d+)(, .+)?/)
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

                } ## end while ($$buffref =~ s/^(.*)\n//...)

                return 0;
            }
        },
        stdout => {
            on_read => sub {
                my ($stream, $buffref) = @_;

                # Discard STDOUT, otherwise it might interfere with the server execution.
                # This can happen if there is a BEGIN block that prints to STDOUT.
                $$buffref = '';
                return 0;
            }
        },
        on_finish => sub {
            $future->done(@diagnostics);
        }
    );

    $loop->add($proc);

    return $future;
} ## end sub get_compilation_errors

sub get_perlcritic_errors
{
    my ($source, $path, $close) = @_;

    my ($profile) = glob $PLS::Server::State::CONFIG->{perlcritic}{perlcriticrc};
    undef $profile if (not length $profile or not -f $profile or not -r $profile);

    return $function->call(args => [$profile, $source, $path, $close]);
} ## end sub get_perlcritic_errors

sub run_perlcritic
{
    my ($profile, $source, $path, $close) = @_;

    return if $close;

    my $critic = Perl::Critic->new(-profile => $profile);
    my %args;
    $args{filename} = $path if (ref $source eq 'SCALAR');
    my $doc        = PPI::Document->new($source, %args);
    my @violations = $critic->critique($doc);

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

    return @diagnostics;
} ## end sub run_perlcritic

1;
