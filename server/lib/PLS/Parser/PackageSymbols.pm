package PLS::Parser::PackageSymbols;

use strict;
use warnings;
use feature 'state';

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

    state $routine;
    state $channel_in;
    state $channel_out;

    if (ref $routine ne 'IO::Async::Routine')
    {
        ($routine, $channel_in, $channel_out) = _get_routine('get_package_functions', $config);
        IO::Async::Loop->new->add($routine);
    }

    $channel_in->send(\@packages);
    return $channel_out->recv->get;
} ## end sub get_package_symbols

sub get_imported_package_symbols
{
    my ($config, @imports) = @_;

    return {} unless (scalar @imports);

    state $routine;
    state $channel_in;
    state $channel_out;

    if (ref $routine ne 'IO::Async::Routine')
    {
        ($routine, $channel_in, $channel_out) = _get_routine('get_imported_functions', $config);
        IO::Async::Loop->new->add($routine);
    }

    $channel_in->send(\@imports);
    return $channel_out->recv->get;
} ## end sub get_imported_package_symbols

sub _get_setup
{
    my ($config) = @_;

    # Just use the first workspace folder as ROOT_PATH - we don't know
    # which folder the code will ultimately be in, and it doesn't really matter
    # for anyone except me.
    my ($workspace_folder) = @{PLS::Parser::Index->new->workspace_folders};
    my $cwd = $config->{cwd};
    $cwd =~ s/\$ROOT_PATH/$workspace_folder/;
    my @setup;
    push @setup, (chdir => $cwd) if (length $cwd and -d $cwd);

    return \@setup;
} ## end sub _get_setup

sub _get_routine
{
    my ($function_name, $config) = @_;

    my $channel_in  = IO::Async::Channel->new();
    my $channel_out = IO::Async::Channel->new();

    my $routine = IO::Async::Routine->new(
                                          module       => 'PLS::Parser::PackageFunctions',
                                          func         => $function_name,
                                          model        => 'spawn',
                                          setup        => _get_setup($config),
                                          channels_in  => [$channel_in],
                                          channels_out => [$channel_out]
                                         );

    return $routine, $channel_in, $channel_out;
} ## end sub _get_routine

1;
