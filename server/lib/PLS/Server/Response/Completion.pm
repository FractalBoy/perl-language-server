package PLS::Server::Response::Completion;

use strict;
use warnings;

use parent q(PLS::Server::Response);
use feature 'state';

use Pod::Functions;
use List::Util;
use Module::CoreList;
use Module::Metadata;
use ExtUtils::Installed;

use PLS::Parser::Document;
use PLS::Parser::PackageSymbols;
use PLS::Parser::Pod;
use PLS::Server::State;

=head1 NAME

PLS::Server::Response::Completion

=head1 DESCRIPTION

This is a message from the server to the client with a list
of completion items for the current location.

=cut

sub new
{
    my ($class, $request) = @_;

    my $self = bless {id => $request->{id}, result => undef}, $class;

    my $document = PLS::Parser::Document->new(uri => $request->{params}{textDocument}{uri}, line => $request->{params}{position}{line});
    return $self if (ref $document ne 'PLS::Parser::Document');

    my @word_under_cursor_info = $document->find_word_under_cursor(@{$request->{params}{position}}{qw(line character)});
    return $self unless (scalar @word_under_cursor_info);

    my ($range, $arrow, $package, $filter) = @word_under_cursor_info;

    if (ref $range eq 'HASH')
    {
        $range->{start}{line} = $request->{params}{position}{line};
        $range->{end}{line}   = $request->{params}{position}{line};
    }

    return $self unless (ref $range eq 'HASH');
    $package =~ s/::$// if (length $package);

    my @results;

    if ($filter =~ /^[\$\%\@]/ and not $arrow)
    {
        my $full_text = $document->get_full_text();
        push @results, @{get_variables($document, $filter, $full_text)};
    }
    else
    {
        my $full_text;

        my %imported_functions;
        unless ($arrow)
        {
            $full_text = $document->get_full_text() unless (ref $full_text eq 'SCALAR');
            push @results, @{get_packages($document, $filter, $full_text)};

            my $imports            = $document->get_imports($full_text);
            my $imported_functions = PLS::Parser::PackageSymbols::get_imported_package_symbols($PLS::Server::State::CONFIG, @{$imports});

            foreach my $package_name (keys %{$imported_functions})
            {
                foreach my $subroutine (@{$imported_functions->{$package_name}})
                {
                    $imported_functions{$package_name}{$subroutine} = 1;
                    my $result = {
                                  kind   => 3,
                                  label  => $subroutine,
                                  data   => $package_name,
                                  detail => "${package_name}::${subroutine}",
                                 };

                    $result->{labelDetails} = {description => "${package_name}::${subroutine}"}
                      if $PLS::Server::State::CLIENT_CAPABILITIES->{textDocument}{completion}{completionItem}{labelDetailsSupport};
                } ## end foreach my $subroutine (@{$imported_functions...})
            } ## end foreach my $package_name (keys...)
        } ## end unless ($arrow)

        my $functions = get_package_functions($package, $filter, $arrow);
        push @results, @{$functions};

        unless (scalar @{$functions})
        {
            $full_text = $document->get_full_text();
            push @results, @{get_subroutines($document, $filter, $full_text)};
            push @results, @{get_constants($document, $filter, $full_text)};
            push @results, @{get_keywords()} unless $arrow;
        } ## end unless (scalar @{$functions...})
    } ## end else [ if ($filter =~ /^[\$\%\@]/...)]

    foreach my $result (@results)
    {
        my $new_text = $result->{label};
        $new_text = $result->{insertText} if (length $result->{insertText});
        delete $result->{insertText};

        push @{$self->{result}}, {%$result, textEdit => {newText => $new_text, range => $range}};
    } ## end foreach my $result (@results...)

    if (not $arrow and not $package and $filter !~ /^\%\@/)
    {
        # Text snippets
        push @{$self->{result}},
          (
            {
             label            => 'sub',
             detail           => 'Insert subroutine',
             kind             => 15,
             insertTextFormat => 2,
             insertText       => "sub \$1\n{\n\t\$0\n}",
            },
            {
             label            => 'foreach',
             detail           => 'Insert foreach loop',
             kind             => 15,
             insertTextFormat => 2,
             insertText       => "foreach my \$1 (\$2)\n{\n\t\$0\n}",
            },
            {
             label            => 'for',
             detail           => 'Insert C-style for loop',
             kind             => 15,
             insertTextFormat => 2,
             insertText       => "for (\$1 ; \$2 ; \$3)\n{\n\t\$0\n}",
            },
            {
             label            => 'while',
             detail           => 'Insert while statement',
             kind             => 15,
             insertTextFormat => 2,
             insertText       => "while (\$1)\n{\n\t\$0\n}",
            },
            {
             label            => 'if',
             detail           => 'Insert if statement',
             kind             => 15,
             insertTextFormat => 2,
             insertText       => "if (\$1)\n{\n\t\$0\n}",
            },
            {
             label            => 'elsif',
             detail           => 'Insert elsif statement',
             kind             => 15,
             insertTextFormat => 2,
             insertText       => "elsif (\$1)\n{\n\t\$0\n}",
            },
            {
             label            => 'else',
             detail           => 'Insert else statement',
             kind             => 15,
             insertTextFormat => 2,
             insertText       => "else\n{\n\t\$0\n}",
            },
            {
             label            => 'package',
             detail           => 'Create a new package',
             kind             => 15,
             insertTextFormat => 2,
             insertText       => "package \$1;\n\nuse strict;\nuse warnings;\n\n\$0\n\n1;",
            },
            {
             label            => 'open my $fh, ...',
             filterText       => 'open',
             sortText         => 'open',
             detail           => 'Insert an open statement',
             kind             => 15,
             insertTextFormat => 2,
             insertText       => q[open $1, '${2|<,>,>>,+<,+>,\|-,-\|,>&,<&=,>>&=|}', $3],
            },
            {
             label            => 'do { local $/; <$fh> }',
             filterText       => 'do',
             sortText         => 'do1',
             detail           => 'Slurp an entire filehandle',
             kind             => 15,
             insertTextFormat => 2,
             insertText       => 'do { local $/; <$1> }'
            },
            {
             label            => 'while (my $line = <$fh>) { ... }',
             filterText       => 'while',
             sortText         => 'while1',
             detail           => 'Iterate through a filehandle line-by-line',
             kind             => 15,
             insertTextFormat => 2,
             insertText       => "while (my \$1 = <\$2>)\n{\n\t\$0\n}"
            },
            {
             label            => 'my ($param1, $param2, ...) = @_;',
             filterText       => 'my',
             sortText         => 'my1',
             detail           => 'Get subroutine parameters',
             kind             => 15,
             insertTextFormat => 2,
             insertText       => "my (\$1) = \@_;\n\n"
            },
            {
             label            => '$? >> 8',
             filterText       => '$?',
             sortText         => '$?',
             detail           => 'Get exit code',
             kind             => 15,
             insertTextFormat => 2,
             insertText       => '? >> 8'
            },
            {
             label            => 'sort { $a <=> $b } ...',
             filterText       => 'sort',
             sortText         => 'sort1',
             detail           => 'Sort numerically ascending',
             kind             => 15,
             insertTextFormat => 2,
             insertText       => 'sort { \$a <=> \$b } $1'
            },
            {
             label            => 'reverse sort { $a <=> $b } ...',
             filterText       => 'sort',
             sortText         => 'sort2',
             detail           => 'Sort numerically descending',
             kind             => 15,
             insertTextFormat => 2,
             insertText       => 'reverse sort { \$a <=> \$b } $1'
            }
          );
    } ## end if (not $arrow and not...)

    return $self;
} ## end sub new

sub get_keywords
{
    state @keywords;

    return \@keywords if (scalar @keywords);

    my %seen_keywords;

    foreach my $family (keys %Pod::Functions::Kinds)
    {
        foreach my $sub (@{$Pod::Functions::Kinds{$family}})
        {
            next if $sub =~ /\s+/;
            next if $seen_keywords{$sub}++;
            push @keywords, {label => $sub, kind => 14};
        } ## end foreach my $sub (@{$Pod::Functions::Kinds...})
    } ## end foreach my $family (keys %Pod::Functions::Kinds...)

    foreach my $keyword (qw(cmp continue default do else elsif eq for foreach ge given gt if le lock lt ne not or package sub unless until when while x xor))
    {
        next if $seen_keywords{$keyword}++;
        push @keywords, {label => $keyword, kind => 14};
    }

    return \@keywords;
} ## end sub get_keywords

sub get_ext_modules
{
    # Can use state here, external modules unlikely to change.
    state @ext_modules;

    return \@ext_modules if (scalar @ext_modules);

    my $include   = PLS::Parser::Pod->get_clean_inc();
    my $installed = ExtUtils::Installed->new(inc_override => $include);

    foreach my $module ($installed->modules)
    {
        my @files = $installed->files($module, 'prog');
        $module =~ s/::/\//g;

        # Find all the packages that are part of this module
        foreach my $file (@files)
        {
            my ($path) = $file =~ /(\Q$module\E(?:\/.+)?)\.pm$/;
            next unless (length $path);
            my $mod_package = $path =~ s/\//::/gr;
            push @ext_modules, $mod_package;
        } ## end foreach my $file (@files)
    } ## end foreach my $module ($installed...)

    return \@ext_modules;
} ## end sub get_ext_modules

sub get_package_functions
{
    my ($package, $filter, $arrow) = @_;

    my $functions = PLS::Parser::PackageSymbols::get_package_symbols($PLS::Server::State::CONFIG, $package);
    return [] if (ref $functions ne 'HASH');

    my $separator = $arrow ? '->' : '::';
    my @functions;

    foreach my $package_name (keys %{$functions})
    {
        foreach my $name (@{$functions->{$package_name}})
        {
            my $fully_qualified = join $separator, $package_name, $name;

            my $result = {
                          label    => $name,
                          sortText => $fully_qualified,
                          kind     => 3
                         };

            if ($arrow)
            {
                $result->{insertText} = $name;
            }
            else
            {
                $result->{insertText} = $fully_qualified;
            }

            if ($arrow)
            {
                if (length $filter)
                {
                    $result->{filterText} = $name;
                }
                else
                {
                    $result->{filterText} = $fully_qualified;
                }
            } ## end if ($arrow)
            else
            {
                $result->{filterText} = $fully_qualified;
            }

            push @functions, $result;
        } ## end foreach my $name (@{$functions...})
    } ## end foreach my $package_name (keys...)

    return \@functions;
} ## end sub get_package_functions

sub get_subroutines
{
    my ($document, $filter, $full_text) = @_;

    my @subroutines;

    foreach my $sub (@{$document->get_subroutines_fast($full_text)})
    {
        next if ($sub =~ /\n/);
        push @subroutines, $sub;
    }

    if (ref $document->{index} eq 'PLS::Parser::Index')
    {
        push @subroutines, @{$document->{index}->get_all_subroutines()};
    }

    @subroutines = map { {label => $_, kind => 3} } List::Util::uniq sort @subroutines;

    return \@subroutines;
} ## end sub get_subroutines

sub get_packages
{
    my ($document, $filter, $full_text) = @_;

    my @packages;

    my $curr_doc_packages = $document->get_packages_fast($full_text);

    # Can use state here, core modules unlikely to change.
    state $core_modules = [Module::CoreList->find_modules(qr//, $])];
    my $ext_modules = get_ext_modules();

    foreach my $pack (@{$curr_doc_packages}, @{$core_modules}, @{$ext_modules})
    {
        next if ($pack =~ /\n/);
        push @packages, $pack;
    }

    if (ref $document->{index} eq 'PLS::Parser::Index')
    {
        push @packages, @{$document->{index}->get_all_packages()};
    }

    @packages = map { {label => $_, kind => 7} } List::Util::uniq sort @packages;

    return \@packages;
} ## end sub get_packages

sub get_constants
{
    my ($document, $filter, $full_text) = @_;

    my %seen_constants;
    my @constants;

    foreach my $constant (@{$document->get_constants_fast($full_text)})
    {
        next if $seen_constants{$constant}++;
        next if ($constant =~ /\n/);
        push @constants, {label => $constant, kind => 21};
    } ## end foreach my $constant (@{$document...})

    return \@constants;
} ## end sub get_constants

sub get_variables
{
    my ($document, $filter, $full_text) = @_;

    my @variables;
    my %seen_variables;

    foreach my $variable (@{$document->get_variables_fast($full_text)})
    {
        next if $seen_variables{$variable}++;
        next if ($variable =~ /\n/);
        push @variables,
          {
            label => $variable,
            kind  => 6
          };

        # add other variable forms to the list for arrays and hashes
        if ($variable =~ /^[\@\%]/)
        {
            my $name   = $variable =~ s/^[\@\%]/\$/r;
            my $append = $variable =~ /^\@/ ? '[' : '{';
            push @variables,
              {
                label      => $variable,
                insertText => $name . $append,
                filterText => $name,
                kind       => 6
              };
        } ## end if ($variable =~ /^[\@\%]/...)
    } ## end foreach my $variable (@{$document...})

    return \@variables;
} ## end sub get_variables

1;
