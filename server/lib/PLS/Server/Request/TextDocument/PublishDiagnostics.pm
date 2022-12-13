package PLS::Server::Request::TextDocument::PublishDiagnostics;

use strict;
use warnings;

use parent 'PLS::Server::Request';

use Encode;
use Fcntl ();
use File::Basename;
use File::Path;
use File::Spec;
use File::Temp;
use IO::Async::Function;
use IO::Async::Loop;
use IO::Async::Process;
use Path::Tiny;
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

my $perlcritic_function = IO::Async::Function->new(code => \&run_perlcritic);
my $podchecker_function = IO::Async::Function->new(code => \&run_podchecker);

my $loop = IO::Async::Loop->new();
$loop->add($perlcritic_function);
$loop->add($podchecker_function);

sub new
{
    my ($class, %args) = @_;

    return if (ref $PLS::Server::State::CONFIG ne 'HASH');

    my $uri = URI->new($args{uri});
    return if (ref $uri ne 'URI::file');

    my $self = bless {
                      method => 'textDocument/publishDiagnostics',
                      params => {
                                 uri         => $uri->as_string,
                                 diagnostics => []
                                },
                      notification => 1
                     },
      $class;

    my (undef, $dir, $suffix) = File::Basename::fileparse($uri->file, qr/\.[^\.]*$/);

    my $source = $uri->file;
    my $text   = PLS::Parser::Document->text_from_uri($uri->as_string);
    $source = $text if (ref $text eq 'SCALAR');
    my $version                    = PLS::Parser::Document::uri_version($uri->as_string);
    my $client_has_version_support = $PLS::Server::State::CLIENT_CAPABILITIES->{textDocument}{publishDiagnostics}{versionSupport};
    $self->{params}{version} = $version if (length $version and $client_has_version_support);

    # If closing, return empty list of diagnostics.
    return Future->done($self) if $args{close};

    my @futures;

    push @futures, get_compilation_errors($source, $dir, $uri->file, $suffix) if ($PLS::Server::State::CONFIG->{syntax}{enabled});
    push @futures, get_perlcritic_errors($source, $uri->file)                 if ($PLS::Server::State::CONFIG->{perlcritic}{enabled});
    push @futures, get_podchecker_errors($source)                             if ($PLS::Server::State::CONFIG->{podchecker}{enabled});

    return Future->wait_all(@futures)->then(
        sub {
            my $current_version = PLS::Parser::Document::uri_version($uri->as_string);

            # No version will be returned if the document has been closed.
            # Since the only way we got here is if the document is open, we
            # should return nothing, since any diagnostics we return will be from
            # when the document was still open.
            return Future->done(undef) unless (length $current_version);

            # If the document has been updated since the diagnostics were created,
            # send nothing back. The next update will re-trigger the diagnostics.
            return Future->done(undef) if (length $version and $current_version > $version);

            @{$self->{params}{diagnostics}} = map { $_->result } @_;

            return Future->done($self);
        }
    );
} ## end sub new

sub get_compilation_errors
{
    my ($source, $dir, $orig_path, $suffix) = @_;

    my $future = $loop->new_future();

    my $fh;
    my $path;
    my $temp;

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

    my $line_lengths = get_line_lengths($fh);

    close $fh;

    my $perl = PLS::Parser::Pod->get_perl_exe();
    my $inc  = PLS::Parser::Pod->get_clean_inc();
    my $args = PLS::Parser::Pod->get_perl_args();
    my @inc  = map { "-I$_" } @{$inc // []};

    my @loadfile;

    if (not length $suffix or $suffix eq '.pl' or $suffix eq '.t' or $suffix eq '.plx')
    {
        @loadfile = (-c => $path);
    }
    elsif ($suffix eq '.pod')
    {
        $future->done();
        return $future;
    }
    else
    {
        my ($relative, $module);

        # Try to get the path as relative to @INC. If we're successful,
        # then we can convert it to a package name and import it using that name
        # instead of the full path.
        foreach my $inc_path (@{$inc})
        {
            my $rel = path($orig_path)->relative($inc_path);

            if ($rel !~ /\.\./)
            {
                $module   = $rel;
                $relative = $rel;
                $module =~ s/\.pm$//;
                $module =~ s/\//::/g;
                last;
            } ## end if ($rel !~ /\.\./)
        } ## end foreach my $inc_path (@{$inc...})

        my $code;
        $path =~ s/'/\\'/g;

        if (length $module and length $relative)
        {
            $relative =~ s/'/\\'/g;

            # Load code using module name, but redirect Perl to the temp file
            # when loading the file we are compiling.
            $code = <<~ "EOF";
            BEGIN
            {
                unshift \@INC, sub {
                    my (undef, \$filename) = \@_;

                    if (\$filename eq '$relative')
                    {
                        if (open my \$fh, '<', '$path')
                        {
                            \$INC{\$filename} = '$orig_path';
                            return \$fh;
                        }
                    }

                    return undef;
                };

                require $module;
            }
            EOF
        } ## end if (length $module and...)
        else
        {
            $code = "BEGIN { require '$path' }";
        }

        @loadfile = (-e => $code);
    } ## end else [ if (not length $suffix...)]

    my @diagnostics;

    my $proc = IO::Async::Process->new(
        command => [$perl, @inc, @loadfile, '--', @{$args}],
        setup   => [chdir => path($orig_path)->parent],
        stderr  => {
            on_read => sub {
                my ($stream, $buffref, $eof) = @_;

                while ($$buffref =~ s/^(.*)\n//)
                {
                    my $line = $1;

                    next if $line =~ /syntax OK$/;

                    if (my ($error, $file, $line_num, $area) = $line =~ /^(.+) at (.+?) line (\d+)(, .+)?/)
                    {
                        $line_num = int $line_num;
                        $file     = $orig_path if ($file eq $path);

                        if ($file ne $path and $file ne $orig_path)
                        {
                            $error .= " at $file line $line_num" if ($file ne '-e');
                            $line_num = 1;
                        }

                        if (length $area)
                        {
                            if ($area =~ /^, near "/ and $area !~ /"$/)
                            {
                                $area .= "\n";

                                while ($$buffref =~ s/^(.*\n)//)
                                {
                                    $area .= $1;
                                    last if ($1 =~ /"$/);
                                }
                            } ## end if ($area =~ /^, near "/...)

                            $error .= $area;
                        } ## end if (length $area)

                        push @diagnostics,
                          {
                            range => {
                                      start => {line => $line_num - 1, character => 0},
                                      end   => {line => $line_num - 1, character => $line_lengths->[$line_num]}
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
    my ($source, $path) = @_;

    my ($profile) = glob $PLS::Server::State::CONFIG->{perlcritic}{perlcriticrc};
    undef $profile if (not length $profile or not -f $profile or not -r $profile);

    return $perlcritic_function->call(args => [$profile, $source, $path]);
} ## end sub get_perlcritic_errors

sub run_perlcritic
{
    my ($profile, $source, $path) = @_;

    my $critic = Perl::Critic->new(-profile => $profile);
    my %args;
    $args{filename} = $path if (ref $source eq 'SCALAR');
    my $doc        = PPI::Document->new($source, %args);
    my @violations = eval { $critic->critique($doc) };

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

sub get_line_lengths
{
    my ($fh) = @_;

    my @line_lengths;

    while (my $line = <$fh>)
    {
        chomp $line;
        $line_lengths[$.] = length $line;
    }

    return \@line_lengths;
} ## end sub get_line_lengths

sub get_podchecker_errors
{
    my ($source) = @_;

    return $podchecker_function->call(args => [$source]);
}

sub run_podchecker
{
    my ($source) = @_;

    return unless (eval { require Pod::Checker; 1 });

    my $errors = '';
    open my $ofh, '>', \$errors;
    open my $ifh, '<', $source;

    my $line_lengths = get_line_lengths($ifh);
    seek $ifh, 0, Fcntl::SEEK_SET;

    Pod::Checker::podchecker($ifh, $ofh);

    my @diagnostics;

    while ($errors =~ s/^(.*)\n//)
    {
        my $line = $1;

        if (my ($severity, $error, $line_num) = $line =~ /^\**\s*([A-Z]{3,}):\s*(.+) at line (\d+) in file/)
        {
            push @diagnostics,
              {
                range => {
                          start => {line => $line_num - 1, character => 0},
                          end   => {line => $line_num - 1, character => $line_lengths->[$line_num]}
                         },
                message  => $error,
                severity => $severity eq 'ERROR' ? 1 : 2,
                source   => 'podchecker',
              };
        } ## end if (my ($severity, $error...))
    } ## end while ($errors =~ s/^(.*)\n//...)

    return @diagnostics;
} ## end sub run_podchecker

1;
