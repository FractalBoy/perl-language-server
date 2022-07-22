package PLS::Parser::PackageSymbols;

use strict;
use warnings;
use feature 'state';

use IO::Async::Loop;
use IO::Async::Process;
use JSON::PP;

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

    state $process;

    if (ref $process ne 'IO::Async::Process')
    {
        my $perl = PLS::Parser::Pod->get_perl_exe();
        my @inc  = map { "-I$_" } @{PLS::Parser::Pod->get_clean_inc()};
        my $args = PLS::Parser::Pod->get_perl_args();
        $process = IO::Async::Process->new(
            command => [$perl, @inc, '-e', get_package_symbols_code(), @{$args}],
            setup   => _get_setup($config),
            stdin   => {via => 'pipe_write'},
            stdout  => {
                       on_read => sub { 0 }
                      },
            on_finish => sub { }
                                          );

        IO::Async::Loop->new->add($process);
    } ## end if (ref $process ne 'IO::Async::Process'...)

    return $process->stdin->write(JSON::PP->new->utf8->encode(\@packages) . "\n")->then(sub { $process->stdout->read_until("\n") }, sub { Future->done('{}') })->then(
        sub {
            my ($json) = @_;

            return Future->done(eval { JSON::PP->new->utf8->decode($json) } // {});
        },
        sub { Future->done({}) }
                                                                                                                                                                     );
} ## end sub get_package_symbols

sub get_imported_package_symbols
{
    my ($config, @imports) = @_;

    return {} unless (scalar @imports);

    state $process;

    if (ref $process ne 'IO::Async::Process')
    {
        my $perl = PLS::Parser::Pod->get_perl_exe();
        my @inc  = map { "-I$_" } @{PLS::Parser::Pod->get_clean_inc()};
        my $args = PLS::Parser::Pod->get_perl_args();
        $process = IO::Async::Process->new(
            command => [$perl, @inc, '-e', get_imported_package_symbols_code(), @{$args}],
            setup   => _get_setup($config),
            stdin   => {via => 'pipe_write'},
            stdout  => {
                       on_read => sub { 0 }
                      },
            on_finish => sub { }
                                          );

        IO::Async::Loop->new->add($process);
    } ## end if (ref $process ne 'IO::Async::Process'...)

    return $process->stdin->write(JSON::PP->new->utf8->encode(\@imports) . "\n")->then(sub { $process->stdout->read_until("\n") }, sub { Future->done('{}') })->then(
        sub {
            my ($json) = @_;

            return Future->done(eval { JSON::PP->new->utf8->decode($json) } // {});
        },
        sub { Future->done({}) }
                                                                                                                                                                    );
} ## end sub get_imported_package_symbols

sub _get_setup
{
    my ($config) = @_;

    # Just use the first workspace folder as ROOT_PATH - we don't know
    # which folder the code will ultimately be in, and it doesn't really matter
    # for anyone except me.
    my ($workspace_folder) = @{PLS::Parser::Index->new->workspace_folders};
    my $cwd = $config->{cwd} // '';
    $cwd =~ s/\$ROOT_PATH/$workspace_folder/;
    my @setup;
    push @setup, (chdir => $cwd) if (length $cwd and -d $cwd);

    return \@setup;
} ## end sub _get_setup

sub get_package_symbols_code
{
    my $code = <<'EOF';
close STDERR;

use IO::Handle;
use JSON::PP;
use Sub::Util;

STDOUT->autoflush();

my $json = JSON::PP->new->utf8;

package PackageSymbols;

while (my $line = <STDIN>)
{
    my $packages_to_find = $json->decode($line);
    my %functions;

    my %symbol_table = %PackageSymbols::;

    foreach my $find_package (@{$packages_to_find})
    {
        my @module_parts        = split /::/, $find_package;
        my @parent_module_parts = @module_parts;
        pop @parent_module_parts;

        my @packages;

        foreach my $parts (\@parent_module_parts, \@module_parts)
        {
            my $package = join '::', @{$parts};
            next unless (length $package);

            eval "require $package";
            next if (length $@);

            push @packages, $package;

            my @isa = add_parent_classes($package);

            foreach my $isa (@isa)
            {
                eval "require $isa";
                next if (length $@);
                push @packages, $isa;
            } ## end foreach my $isa (@isa)
        } ## end foreach my $parts (\@parent_module_parts...)

        foreach my $package (@packages)
        {
            my @parts = split /::/, $package;
            my $ref   = \%::;

            foreach my $part (@parts)
            {
                $ref = $ref->{"${part}::"};
            }

            foreach my $name (keys %{$ref})
            {
                next if $name =~ /^BEGIN|UNITCHECK|INIT|CHECK|END|VERSION|import|unimport$/;

                my $code_ref = $package->can($name);
                next if (ref $code_ref ne 'CODE');
                next if Sub::Util::subname($code_ref) !~ /^\Q$package\E(?:::.+)*::(?:\Q$name\E|__ANON__)$/;

                if ($find_package->isa($package))
                {
                    push @{$functions{$find_package}}, $name;
                }
                else
                {
                    push @{$functions{$package}}, $name;
                }
            } ## end foreach my $name (keys %{$ref...})

            # Unrequire packages
            my $package_path = $package =~ s/::/\//gr;
            $package_path .= '.pm';
            delete $INC{$package_path};
        } ## end foreach my $package (@packages...)
    } ## end foreach my $find_package (@...)

    %PackageSymbols:: = %symbol_table;

    print $json->encode(\%functions);
    print "\n";
} ## end while (my $packages_to_find...)

sub add_parent_classes
{
    my ($package) = @_;

    my @isa = eval "\@${package}::ISA";
    return unless (scalar @isa);

    foreach my $isa (@isa)
    {
        push @isa, add_parent_classes($isa);
    }

    return @isa;
} ## end sub add_parent_classes
EOF

    return $code;
} ## end sub get_package_symbols_code

sub get_imported_package_symbols_code
{
    my $code = <<'EOF';
close STDERR;

use IO::Handle;
use JSON::PP;

STDOUT->autoflush();

my $json = JSON::PP->new->utf8;

package ImportedPackageSymbols;

while (my $line = <STDIN>)
{
    my $imports = $json->decode($line);

    my %functions;

    foreach my $import (@{$imports})
    {
        my %symbol_table_before = %ImportedPackageSymbols::;
        eval $import->{use};
        my %symbol_table_after = %ImportedPackageSymbols::;
        delete @symbol_table_after{keys %symbol_table_before};

        foreach my $subroutine (keys %symbol_table_after)
        {
            next if (ref eval { *{$symbol_table_after{$subroutine}}{CODE} } ne 'CODE');
            $functions{$import->{module}}{$subroutine} = 1;
        }

        # Reset symbol table and %INC
        %ImportedPackageSymbols:: = %symbol_table_before;
        my $module_path = $import->{module} =~ s/::/\//gr;
        $module_path .= '.pm';
        delete $INC{$module_path};
    } ## end foreach my $import (@{$imports...})

    foreach my $module (keys %functions)
    {
        $functions{$module} = [keys %{$functions{$module}}];
    }

    print $json->encode(\%functions);
    print "\n";
} ## end while (my $imports = $channel_in...)
EOF

    return $code;
} ## end sub get_imported_package_symbols_code

1;
