package PLS::Server::Response::Hover;
use parent q(PLS::Server::Response);

use strict;
use warnings;

use Pod::Find;
use Pod::Markdown;
use URI;

use PLS::Parser::BuiltIns;
use PLS::Parser::Document;
use PLS::Parser::Index;
use PLS::Server::State;

sub new
{
    my ($class, $request) = @_;

    my $self = {
                id     => $request->{id},
                result => undef
               };

    bless $self, $class;

    my $markdown;
    my ($ok, $name, $line_number, $column_number) = find_pod($request->{params}{textDocument}{uri}, @{$request->{params}{position}}{qw(line character)}, \$markdown);

    if ($ok)
    {
        $self->{result} = {
                   contents => {kind => 'markdown', value => $markdown},
                   range    => {
                             start => {
                                       line      => $line_number,
                                       character => $column_number,
                                      },
                             end => {
                                     line      => $line_number,
                                     character => ($column_number + length $name),
                                    }
                            }
                  };
    } ## end if ($ok)

    return $self;
} ## end sub new

sub get_pod_for_subroutine
{
    my ($path, $subroutine, $markdown) = @_;

    open my $fh, '<', $path or return 0;

    my @lines;
    my $start = '';

    while (my $line = <$fh>)
    {
        if ($line =~ /^=(head\d|item).*\b$subroutine\b.*$/)
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

    if (scalar @lines)
    {
        my $parser = Pod::Markdown->new();

        $parser->output_string($markdown);
        $parser->no_whining(1);
        $parser->parse_lines(@lines, undef);

        # remove first extra space to avoid markdown from being displayed inappropriately as code
        $$markdown =~ s/\n\n/\n/;
        return $parser->content_seen;
    } ## end if (scalar @lines)

    return 0;
} ## end sub get_pod_for_subroutine

sub find_pod
{
    my ($uri, $line, $character, $markdown) = @_;

    my $document = PLS::Parser::Document->new(uri => $uri);
    return 0 unless (ref $document eq 'PLS::Parser::Document');
    my @elements = $document->find_elements_at_location($line, $character);

    foreach my $element (@elements)
    {
        my ($package, $subroutine, $variable);

        if (($package, $subroutine) = $element->subroutine_package_and_name())
        {
            my $ok = get_pod($document, $package, $subroutine, $markdown);
            return (1, length $package ? "${package}::${subroutine}" : $subroutine, $element->lsp_line_number, $element->lsp_column_number) if $ok;
        }
        if (($package, $subroutine) = $element->class_method_package_and_name())
        {
            my $ok = get_pod($document, $package, $subroutine, $markdown);
            return (1, "${package}->${subroutine}", $element->lsp_line_number, $element->lsp_column_number) if $ok;
        }
        if ($subroutine = $element->method_name())
        {
            my $ok = get_pod($document, '', $subroutine, $markdown);
            return (1, $subroutine, $element->lsp_line_number, $element->lsp_column_number) if $ok;
        }
        if ($package = $element->package_name())
        {
            my $ok = PLS::Parser::BuiltIns::run_perldoc_command($markdown, '-Tu', $package);
            return (1, $package, $element->lsp_line_number, $element->lsp_column_number) if $ok;
            return 0;
        }
        if ($variable = $element->variable_name())
        {
            my $ok = PLS::Parser::BuiltIns::get_builtin_variable_documentation($variable, $markdown);
            return (1, $variable, $element->lsp_line_number, $element->lsp_column_number) if $ok;
            return 0;
        }
    } ## end foreach my $element (@elements...)

    return 0;
} ## end sub find_pod

sub get_pod_for_definitions
{
    my ($subroutine, $definitions, $markdown) = @_;

    return 0 unless (ref $definitions eq 'ARRAY' and scalar @$definitions);

    my $ok;
    my @markdown_parts;

    foreach my $definition (@$definitions)
    {
        my $markdown_part;
        my $path      = URI->new($definition->{uri})->file;
        my $result_ok = get_pod_for_subroutine($path, $subroutine, \$markdown_part);

        if (length $markdown_part)
        {
            $markdown_part = "*(From $path)*\n" . $markdown_part;
            push @markdown_parts, $markdown_part;
        }

        $ok = 1 if $result_ok;
    } ## end foreach my $definition (@$definitions...)

    return 0 unless $ok;
    $$markdown = join "\n---\n", @markdown_parts;
    return 1;
} ## end sub get_pod_for_definitions

sub get_pod
{
    my ($document, $package, $subroutine, $markdown) = @_;

    my $definitions;

    if (length $package)
    {
        my $path = Pod::Find::pod_where({-inc => 1}, $package);

        if (length $path)
        {
            my $ok = get_pod_for_subroutine($path, $subroutine, $markdown);
            return 1 if $ok;
        }

        $definitions = $document->{index}->find_package_subroutine($package, $subroutine);
    } ## end if (length $package)

    unless (ref $definitions eq 'ARRAY' and scalar @$definitions)
    {
        $definitions = $document->{index}->find_subroutine($subroutine);
    } ## end unless (ref $definitions eq...)

    my $ok = get_pod_for_definitions($subroutine, $definitions, $markdown);
    return 1 if $ok;

    # see if it's a built-in
    $ok = PLS::Parser::BuiltIns::get_builtin_function_documentation($subroutine, $markdown);
    return 1 if $ok;

    # if all else fails, show documentation for the entire package
    return PLS::Parser::BuiltIns::run_perldoc_command($markdown, '-Tu', $package) if (length $package);
    return 0;
} ## end sub get_pod

1;
