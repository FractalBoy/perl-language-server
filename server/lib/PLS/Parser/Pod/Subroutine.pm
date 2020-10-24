package PLS::Parser::Pod::Subroutine;

use strict;
use warnings;

use parent 'PLS::Parser::Pod';

sub new
{
    my ($class, @args) = @_;

    my %args = @args;
    my $self = $class->SUPER::new(%args);
    $self->{subroutine} = $args{subroutine};
    $self->{package}    = $args{package};

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
        my $path = Pod::Find::pod_where({-inc => 1}, $self->{package});

        if (length $path)
        {
            my ($ok, $markdown) = $self->find_pod_in_file($path);
            if ($ok)
            {
                $self->{markdown} = $markdown;
                return 1;
            }
        }

        $definitions = $self->{document}{index}->find_package_subroutine($self->{package}, $self->{subroutine});
    } ## end if (length $package)

    unless (ref $definitions eq 'ARRAY' and scalar @$definitions)
    {
        $definitions = $self->{document}{index}->find_subroutine($self->{subroutine});
    } ## end unless (ref $definitions eq...)

    my @markdown;

    my ($ok, $markdown) = $self->find_pod_in_definitions($definitions);
    push @markdown, $$markdown if $ok;

    # see if it's a built-in
    ($ok, $markdown) = $self->run_perldoc_command('-Tuf', $self->{subroutine});
    push @markdown, $$markdown if $ok;
    
    if (scalar @markdown)
    {
        $self->{markdown} = \($self->combine_markdown(@markdown));
        return 1;
    }

    # if all else fails, show documentation for the entire package
    ($ok, $markdown) = $self->run_perldoc_command('-Tu', $self->{package}) if (length $self->{package});
    $self->{markdown} = $markdown if $ok;
    return $ok;
}

sub find_pod_in_definitions
{
    my ($self, $definitions) = @_;

    return 0 unless (ref $definitions eq 'ARRAY' and scalar @$definitions);

    my $ok;
    my @markdown_parts;

    foreach my $definition (@$definitions)
    {
        my $path      = URI->new($definition->{uri})->file;
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
}

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
        } ## end if ($line =~ /^=(head\d|item).*\b$subroutine\b.*$/...)

        if (length $start)
        {
            push @lines, $line;

            if (   $start eq 'item' and $line =~ /^=item/
                or $start =~ /head/ and $line eq $start
                or $line  =~ /^=cut/)
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