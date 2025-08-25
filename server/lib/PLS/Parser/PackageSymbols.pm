package PLS::Parser::PackageSymbols;

use strict;
use warnings;
use feature 'state';

use Future;
use IO::Async::Loop;
use IO::Async::Process;

use PLS::JSON;

=head1 NAME

PLS::Parser::PackageSymbols

=head1 DESCRIPTION

This package executes a Perl process to import a package and interrogate
its symbol table to find all of the symbols in the package.

=cut

sub get_package_symbols
{
    my ($config, @packages) = @_;

    return Future->done({}) unless (scalar @packages);

    state ($channel_in, $channel_out);

    if (not $channel_in or not $channel_out)
    {
        ($channel_in, $channel_out) = start_package_symbols_process($config);
    }

    $channel_in->send(\@packages);
    return $channel_out->recv();
} ## end sub get_package_symbols

sub get_imported_package_symbols
{
    my ($config, @imports) = @_;

    return Future->done({}) unless (scalar @imports);

    state ($channel_in, $channel_out);

    if (not $channel_in or not $channel_out)
    {
        ($channel_in, $channel_out) = start_imported_package_symbols_process($config);
    }

    $channel_in->send(\@imports);
    return $channel_out->recv();
} ## end sub get_imported_package_symbols

sub _start_process
{
    my ($config, $module) = @_;

    my $perl = PLS::Parser::Pod->get_perl_exe();

    my $channel_in  = IO::Async::Channel->new();
    my $channel_out = IO::Async::Channel->new();

    local $^X  = $perl;
    local @INC = (@INC, @{$config->{inc} // []});

    my $routine = IO::Async::Routine->new(
                                          channels_in  => [$channel_in],
                                          channels_out => [$channel_out],
                                          module       => $module,
                                          func         => 'get',
                                         );

    IO::Async::Loop->new->add($routine);

    my $setup = _get_setup($config);
    $channel_in->send($setup);

    return ($channel_in, $channel_out);
} ## end sub _start_process

sub start_package_symbols_process
{
    my ($config) = @_;

    return _start_process($config, 'PLS::Parser::GetPackageSymbols');
}

sub start_imported_package_symbols_process
{
    my ($config) = @_;

    return _start_process($config, 'PLS::Parser::GetImportedPackageSymbols');
}

sub _get_setup
{
    my ($config) = @_;

    my ($cwd) = PLS::Util::resolve_workspace_relative_path($config->{cwd}, undef, 1);
    my @setup;
    push @setup, (chdir => $cwd) if (length $cwd and -d $cwd);

    return \@setup;
} ## end sub _get_setup

1;
