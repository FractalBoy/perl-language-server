package PLS::Parser::PackageSymbols;

use strict;
use warnings;

use IO::Async::Loop;
use IO::Async::Routine;

use PLS::Parser::Index;
use PLS::Parser::Pod;

=head1 NAME

PLS::Parser::PackageSymbols

=head1 DESCRIPTION

This package executes a Perl process to import a package and interrogate
its symbol table to find all of the symbols in the package.

=cut

sub get_package_symbols
{
    my ($config, @packages) = @_;

    return {} unless (scalar @packages);
    return _execute_routine('get_package_functions', $config, \@packages);
} ## end sub get_package_symbols

sub get_imported_package_symbols
{
    my ($config, @imports) = @_;

    return {} unless (scalar @imports);
    return _execute_routine('get_imported_functions', $config, \@imports);
} ## end sub get_imported_package_symbols

sub _execute_routine
{
    my ($function_name, $config, $args) = @_;

    my $loop = IO::Async::Loop->new();

    # Just use the first workspace folder as ROOT_PATH - we don't know
    # which folder the code will ultimately be in, and it doesn't really matter
    # for anyone except me.
    my ($workspace_folder) = @{PLS::Parser::Index->new->workspace_folders};
    my $cwd = $config->{cwd};
    $cwd =~ s/\$ROOT_PATH/$workspace_folder/;
    my @setup;
    push @setup, (chdir => $cwd) if (length $cwd and -d $cwd);

    local @INC = @{PLS::Parser::Pod->get_clean_inc()};

    my $channel_in  = IO::Async::Channel->new();
    my $channel_out = IO::Async::Channel->new();

    my $routine = IO::Async::Routine->new(
                                          module       => 'PLS::Parser::PackageFunctions',
                                          func         => $function_name,
                                          model        => 'spawn',
                                          setup        => \@setup,
                                          channels_in  => [$channel_in],
                                          channels_out => [$channel_out]
                                         );
    $loop->add($routine);

    $channel_in->send($args);
    return $channel_out->recv->get();
} ## end sub _execute_routine

1;
