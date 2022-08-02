package PLS::Parser::Pod::Subroutine;

use strict;
use warnings;

use parent 'PLS::Parser::Pod';

use Pod::Simple::Search;
use Pod::Markdown;

use PLS::Parser::Document;
use PLS::Parser::PackageSymbols;
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
    $self->{packages}         = $args{packages};
    $self->{include_builtins} = $args{include_builtins};
    $self->{uri}              = $args{uri};

    return $self;
} ## end sub new

sub find
{
    my ($self) = @_;

    my $definitions;

    # If there is no package name in the subroutine call, check to see if the
    # function is imported.
    if (length $self->{uri} and (ref $self->{packages} ne 'ARRAY' or not scalar @{$self->{packages}}))
    {
        my $full_text          = PLS::Parser::Document->text_from_uri($self->{uri});
        my $imports            = PLS::Parser::Document->get_imports($full_text);
        my $imported_functions = PLS::Parser::PackageSymbols::get_imported_package_symbols($PLS::Server::State::CONFIG, @{$imports})->get();

      PACKAGE: foreach my $package (keys %{$imported_functions})
        {
            foreach my $subroutine (@{$imported_functions->{$package}})
            {
                if ($self->{subroutine} eq $subroutine)
                {
                    $self->{packages} = [$package];
                    last PACKAGE;
                }
            } ## end foreach my $subroutine (@{$imported_functions...})
        } ## end foreach my $package (keys %...)
    } ## end if (length $self->{uri...})

    my @markdown;
    my @definitions;

    if (ref $self->{packages} eq 'ARRAY' and scalar @{$self->{packages}})
    {
        my $include = $self->get_clean_inc();
        foreach my $package (@{$self->{packages}})
        {
            my $search = Pod::Simple::Search->new();
            $search->inc(0);
            my $path = $search->find($package, @{$include});
            my $ok;

            if (length $path)
            {
                my $markdown;
                ($ok, $markdown) = $self->find_pod_in_file($path, $self->{subroutine});
                push @markdown, $$markdown if $ok;
            } ## end if (length $path)

            unless ($ok)
            {
                push @definitions, @{$self->{index}->find_package_subroutine($package, $self->{subroutine})} if (ref $self->{index} eq 'PLS::Parser::Index');
            }
        } ## end foreach my $package (@{$self...})
    } ## end if (ref $self->{packages...})
    elsif (ref $self->{index} eq 'PLS::Parser::Index')
    {
        push @definitions, @{$self->{index}->find_subroutine($self->{subroutine})};
    }

    if (scalar @definitions)
    {
        my ($ok, $markdown) = $self->find_pod_in_definitions(\@definitions);
        push @markdown, $$markdown if $ok;
    }

    if ($self->{include_builtins})
    {
        my $builtin = PLS::Parser::Pod::Builtin->new(function => $self->{subroutine});
        my $ok      = $builtin->find();
        unshift @markdown, ${$builtin->{markdown}} if $ok;
    } ## end if ($self->{include_builtins...})

    if (scalar @markdown)
    {
        $self->{markdown} = \($self->combine_markdown(@markdown));
        return 1;
    }

    # if all else fails, show documentation for the entire package
    if (ref $self->{packages} and scalar @{$self->{packages}})
    {
        foreach my $package (@{$self->{packages}})
        {
            my ($ok, $markdown) = $self->get_markdown_for_package($package);

            unless ($ok)
            {
                $package = join '::', $package, $self->{subroutine};
                ($ok, $markdown) = $self->get_markdown_for_package($package);
            }

            push @markdown, $$markdown if $ok;
        } ## end foreach my $package (@{$self...})
    } ## end if (ref $self->{packages...})

    if (scalar @markdown)
    {
        $self->{markdown} = \($self->combine_markdown(@markdown));
        return 1;
    }

    return 0;
} ## end sub find

sub find_pod_in_definitions
{
    my ($self, $definitions) = @_;

    return 0 unless (ref $definitions eq 'ARRAY' and scalar @$definitions);

    my $ok;
    my @markdown_parts;

    foreach my $definition (@{$definitions})
    {
        my $path = URI->new($definition->{uri})->file;
        my ($found, $markdown_part) = $self->find_pod_in_file($path, $self->{subroutine});
        next unless $found;

        if (length $$markdown_part)
        {
            $$markdown_part = "*(From $path)*\n" . $$markdown_part;
            push @markdown_parts, $$markdown_part;
        }

        $ok = 1;
    } ## end foreach my $definition (@{$definitions...})

    return 0 unless $ok;
    my $markdown = $self->combine_markdown(@markdown_parts);
    return 1, \$markdown;
} ## end sub find_pod_in_definitions

1;
