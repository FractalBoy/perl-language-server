package PLS::Parser::Pod::Subroutine;

use strict;
use warnings;

use parent 'PLS::Parser::Pod';

use Pod::Simple::Search;
use Pod::Markdown;

use PLS::Parser::Pod::Builtin;
use PLS::Server::State;

=head1 NAME

PLS::Parser::Pod::Subroutine

=head1 DESCRIPTION

This is a subclass of L<PLS::Parser::Pod>, for finding POD for a subroutine.
This class also might find built-in Perl functions if found and C<include_builtins>
is set to true.

=cut

sub new
{
    my ($class, @args) = @_;

    my %args = @args;
    my $self = $class->SUPER::new(%args);
    $self->{subroutine}       = $args{subroutine};
    $self->{package}          = $args{package};
    $self->{include_builtins} = $args{include_builtins};

    return $self;
} ## end sub new

sub name
{
    my ($self) = @_;

    my $name = '';
    $name = $self->{package} . '::' if (length $self->{package});
    return $name . $self->{subroutine};
} ## end sub name

sub find
{
    my ($self) = @_;

    my $definitions;

    if (length $self->{package})
    {
        my $include = $self->get_clean_inc();
        my $search  = Pod::Simple::Search->new();
        $search->inc(0);
        my $path = $search->find($self->{package}, @{$include});

        if (length $path)
        {
            my ($ok, $markdown) = $self->find_pod_in_file($path);
            if ($ok)
            {
                $self->{markdown} = $markdown;
                return 1;
            }
        } ## end if (length $path)

        $definitions = $self->{index}->find_package_subroutine($self->{package}, $self->{subroutine}) if (ref $self->{index} eq 'PLS::Parser::Index');
    } ## end if (length $self->{package...})

    if ((ref $definitions ne 'ARRAY' or not scalar @{$definitions}) and ref $self->{index} eq 'PLS::Parser::Index')
    {
        $definitions = $self->{index}->find_subroutine($self->{subroutine});
    }

    my @markdown;

    my ($ok, $markdown) = $self->find_pod_in_definitions($definitions);
    push @markdown, $$markdown if $ok;

    if ($self->{include_builtins})
    {
        my $builtin = PLS::Parser::Pod::Builtin->new(function => $self->{subroutine});
        $ok = $builtin->find();
        unshift @markdown, ${$builtin->{markdown}} if $ok;
    } ## end if ($self->{include_builtins...})

    if (scalar @markdown)
    {
        $self->{markdown} = \($self->combine_markdown(@markdown));
        return 1;
    }

    # if all else fails, show documentation for the entire package
    if (length $self->{package})
    {
        ($ok, $markdown) = $self->get_markdown_for_package($self->{package}) if (length $self->{package});

        unless ($ok)
        {
            my $package = join '::', $self->{package}, $self->{subroutine};
            ($ok, $markdown) = $self->get_markdown_for_package($package);
        }
    } ## end if (length $self->{package...})

    $self->{markdown} = $markdown if $ok;
    return $ok;
} ## end sub find

sub find_pod_in_definitions
{
    my ($self, $definitions) = @_;

    return 0 unless (ref $definitions eq 'ARRAY' and scalar @$definitions);

    my $ok;
    my @markdown_parts;

    foreach my $definition (@$definitions)
    {
        my $path = URI->new($definition->{uri})->file;
        my ($found, $markdown_part) = $self->find_pod_in_file($path);
        next unless $found;

        if (length $$markdown_part)
        {
            $$markdown_part = "*(From $path)*\n" . $$markdown_part;
            push @markdown_parts, $$markdown_part;
        }

        $ok = 1;
    } ## end foreach my $definition (@$definitions...)

    return 0 unless $ok;
    my $markdown = $self->combine_markdown(@markdown_parts);
    return 1, \$markdown;
} ## end sub find_pod_in_definitions

sub find_pod_in_file
{
    my ($self, $path) = @_;

    open my $fh, '<', $path or return 0;

    my @lines;
    my $start = '';

    while (my $line = <$fh>)
    {
        if ($line =~ /^=(head\d|item).*\b$self->{subroutine}\b.*$/)
        {
            $start = $1;
            push @lines, $line;
            next;
        } ## end if ($line =~ /^=(head\d|item).*\b$self->{subroutine}\b.*$/...)

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

1;
