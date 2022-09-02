package PLS::Parser::Pod;

use strict;
use warnings;
use feature 'state';

use File::Spec;
use FindBin;
use IPC::Open3;
use Pod::Markdown;
use Pod::Simple::Search;
use Symbol qw(gensym);

use PLS::Parser::Index;
use PLS::Server::State;

=head1 NAME

PLS::Parser::Pod

=head1 DESCRIPTION

This class finds and parses POD for an element. It formats the POD into markdown suitable
for sending to the Language Server Protocol.

=cut

my $PERL_EXE  = $^X;
my $PERL_ARGS = [];

sub new
{
    my ($class, @args) = @_;

    my %args = @args;

    my %self = (
                index   => $args{index},
                element => $args{element}
               );

    return bless \%self, $class;
} ## end sub new

=head2 set_perl_exe

Store the perl executable path.

=cut

sub set_perl_exe
{
    my (undef, $perl_exe) = @_;

    $PERL_EXE = $perl_exe if (length $perl_exe and -x $perl_exe);

    return;
} ## end sub set_perl_exe

=head2 get_perl_exe

Get the perl executable path.

=cut

sub get_perl_exe
{
    return $PERL_EXE;
}

=head2 set_perl_args

Set the arguments to be used when using the perl binary.

=cut

sub set_perl_args
{
    my (undef, $args) = @_;

    $PERL_ARGS = $args;
}

=head2 get_perl_args

Get the arguments to be used when using the perl binary.

=cut

sub get_perl_args
{
    return $PERL_ARGS;
}

=head2 get_perldoc_location

Tries to find the path to the perldoc utility.

=cut

sub get_perldoc_location
{
    my (undef, $dir) = File::Spec->splitpath($^X);
    my $perldoc = File::Spec->catfile($dir, 'perldoc');

    # try to use the perldoc matching this perl executable, falling back to the perldoc in the PATH
    return (-f $perldoc and -x $perldoc) ? $perldoc : 'perldoc';
} ## end sub get_perldoc_location

=head2 run_perldoc_command

Runs a perldoc command and returns the text formatted into markdown.

=cut

sub run_perldoc_command
{
    my ($class, @command) = @_;

    my $markdown = '';

    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, get_perldoc_location(), @command);

    close $in, () = <$err>;    # need to read all of error file handle
    my $pod = do { local $/; <$out> };
    close $out;
    waitpid $pid, 0;
    my $exit_code = $? >> 8;
    return 0 if $exit_code != 0;
    return $class->get_markdown_from_text(\$pod);
} ## end sub run_perldoc_command

=head2 get_markdown_for_package

Finds the POD for a package and returns its POD, formatted into markdown.

=cut

sub get_markdown_for_package
{
    my ($class, $package) = @_;

    my $include = $class->get_clean_inc();
    my $search  = Pod::Simple::Search->new();
    $search->inc(0);
    my $path = $search->find($package, @{$include});
    return unless (length $path);
    open my $fh, '<', $path or return;
    my $text = do { local $/; <$fh> };
    return $class->get_markdown_from_text(\$text);
} ## end sub get_markdown_for_package

=head2 get_markdown_from_lines

This formats POD from an array of lines into markdown and fixes up improperly formatted text.

=cut

sub get_markdown_from_lines
{
    my ($class, $lines) = @_;

    my $markdown = '';
    my $parser   = Pod::Markdown->new();

    $parser->output_string(\$markdown);
    $parser->no_whining(1);
    $parser->parse_lines(@$lines, undef);

    $class->clean_markdown(\$markdown);

    my $ok = $parser->content_seen;
    return 0 unless $ok;
    return $ok, \$markdown;
} ## end sub get_markdown_from_lines

=head2 get_markdown_from_text

This formats POD from SCALAR ref to a string into markdown and fixes up improperly formatted text.

=cut

sub get_markdown_from_text
{
    my ($class, $text) = @_;

    my $markdown = '';
    my $parser   = Pod::Markdown->new();

    $parser->output_string(\$markdown);
    $parser->no_whining(1);
    $parser->parse_string_document($$text);

    $class->clean_markdown(\$markdown);

    my $ok = $parser->content_seen;
    return 0 unless $ok;
    return $ok, \$markdown;
} ## end sub get_markdown_from_text

sub find_pod_in_file
{
    my ($self, $path, $name) = @_;

    open my $fh, '<', $path or return 0;

    my @lines;
    my $start = '';

    while (my $line = <$fh>)
    {
        if ($line =~ /^=(head\d|item).*\b\Q$name\E\b.*$/)
        {
            $start = $1;
            push @lines, $line;
            next;
        } ## end if ($line =~ /^=(head\d|item).*\b\Q$name\E\b.*$/...)

        if (length $start)
        {
            push @lines, $line;

            if (   $start eq 'item' and $line =~ /^=item/
                or $start =~ /head/ and $line =~ /^=$start/
                or $line =~ /^=cut/)
            {
                last;
            } ## end if ($start eq 'item' and...)
        } ## end if (length $start)
    } ## end while (my $line = <$fh>)

    close $fh;

    # we don't want the last line - it's a start of a new section.
    pop @lines;

    my $markdown = '';

    if (scalar @lines)
    {
        my $parser = Pod::Markdown->new();

        $parser->output_string(\$markdown);
        $parser->no_whining(1);
        $parser->parse_lines(@lines, undef);

        # remove first extra space to avoid markdown from being displayed inappropriately as code
        $markdown =~ s/\n\n/\n/;
        my $ok = $parser->content_seen;
        return 0 unless $ok;
        return $ok, \$markdown;
    } ## end if (scalar @lines)

    return 0;
} ## end sub find_pod_in_file

=head2 clean_markdown

This fixes markdown so that documentation isn't incorrectly displayed as code.

=cut

sub clean_markdown
{
    my ($class, $markdown) = @_;

    # remove first extra space to avoid markdown from being displayed inappropriately as code
    $$markdown =~ s/\n\n/\n/;
} ## end sub clean_markdown

=head2 combine_markdown

This combines multiple markdown sections into a single string.

=cut

sub combine_markdown
{
    my ($class, @markdown_parts) = @_;

    return join "\n---\n", @markdown_parts;
}

=head2 get_clean_inc

Starts a new perl process and retrieves its @INC, so we do not use an @INC tainted
with things included in PLS.

=cut

sub get_clean_inc
{
    state @include;
    state $last_perl;

    if (not scalar @include or $last_perl ne $PERL_EXE)
    {
        $last_perl = $PERL_EXE;
        local $ENV{PERL5LIB};

        # default to including everything except PLS code in search.
        @include = grep { not /\Q$FindBin::RealBin\E/ } @INC;

        # try to get a clean @INC from the perl we're using
        if (my $pid = open my $perl, '-|', $PERL_EXE, '-e', q{$, = "\n"; print @INC; print "\n"})
        {
            @include = ();

            while (my $line = <$perl>)
            {
                chomp $line;
                next unless (length $line);
                push @include, $line;
            } ## end while (my $line = <$perl>...)

            waitpid $pid, 0;
        } ## end if (my $pid = open my ...)
    }

    my @temp_include = @include;
    push @temp_include, @{$PLS::Server::State::CONFIG->{inc} // []};
    my $index = PLS::Parser::Index->new();
    push @temp_include, @{PLS::Parser::Index->new->workspace_folders // []};

    return \@temp_include;
} ## end sub get_clean_inc

1;
