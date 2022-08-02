package PLS::Parser::PackageSymbols;

use strict;
use warnings;
use feature 'state';

use Future;
use IO::Async::Loop;
use IO::Async::Process;

use PLS::JSON;
use PLS::Parser::Index;
use PLS::Parser::Pod;

=head1 NAME

PLS::Parser::PackageSymbols

=head1 DESCRIPTION

This package executes a Perl process to import a package and interrogate
its symbol table to find all of the symbols in the package.

=cut

my $package_symbols_process;
my $imported_symbols_process;

sub get_package_symbols
{
    my ($config, @packages) = @_;

    return Future->done({}) unless (scalar @packages);

    start_package_symbols_process($config) if (ref $package_symbols_process ne 'IO::Async::Process');

    return $package_symbols_process->stdin->write(encode_json(\@packages) . "\n")->then(sub { $package_symbols_process->stdout->read_until("\n") })->then(
        sub {
            my ($json) = @_;

            return Future->done(eval { decode_json $json } // {});
        },
        sub { Future->done({}) }
    );
} ## end sub get_package_symbols

sub get_imported_package_symbols
{
    my ($config, @imports) = @_;

    return Future->done({}) unless (scalar @imports);

    start_imported_package_symbols_process($config) if (ref $imported_symbols_process ne 'IO::Async::Process');

    return $imported_symbols_process->stdin->write(encode_json(\@imports) . "\n")->then(sub { $imported_symbols_process->stdout->read_until("\n") })->then(
        sub {
            my ($json) = @_;

            return Future->done(eval { decode_json $json } // {});
        },
        sub { Future->done({}) }
    );
} ## end sub get_imported_package_symbols

sub _start_process
{
    my ($config, $code) = @_;

    my $perl = PLS::Parser::Pod->get_perl_exe();
    my @inc  = map { "-I$_" } @{$config->{inc}};
    my $args = PLS::Parser::Pod->get_perl_args();
    my $process = IO::Async::Process->new(
                                          command => [$perl, @inc, '-e', $code, @{$args}],
                                          setup   => _get_setup($config),
                                          stdin   => {via => 'pipe_write'},
                                          stdout  => {
                                                     on_read => sub { 0 }
                                                    },
                                          on_finish => sub { }
                                         );

    IO::Async::Loop->new->add($process);

    return $process;
} ## end sub _start_process

sub start_package_symbols_process
{
    my ($config) = @_;

    eval { $package_symbols_process->kill('TERM') } if (ref $package_symbols_process eq 'IO::Async::Process');
    $package_symbols_process = _start_process($config, get_package_symbols_code());
} ## end sub start_package_symbols_process

sub start_imported_package_symbols_process
{
    my ($config) = @_;

    eval { $imported_symbols_process->kill('TERM') } if (ref $package_symbols_process eq 'IO::Async::Process');
    $imported_symbols_process = _start_process($config, get_imported_package_symbols_code());
} ## end sub start_imported_package_symbols_process

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
use B;

STDOUT->autoflush();

my $json = JSON::PP->new->utf8;

package PackageSymbols;

while (my $line = <STDIN>)
{
    my $packages_to_find = $json->decode($line);
    my %functions;

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
            my $ref   = \%{"${package}::"};

            foreach my $name (keys %{$ref})
            {
                next if $name =~ /^BEGIN|UNITCHECK|INIT|CHECK|END|VERSION|import|unimport$/;

                my $code_ref = $package->can($name);
                next if (ref $code_ref ne 'CODE');
                my $defined_in = eval { B::svref_2object($code_ref)->GV->STASH->NAME };
                next if ($defined_in ne $package and not $package->isa($defined_in));

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

my %mtimes;
my %inc;
my %symbol_cache;

while (my $line = <STDIN>)
{
    my $imports = $json->decode($line);

    my %functions;

    foreach my $import (@{$imports})
    {
        if (-f $inc{$import->{module}} and $mtimes{$import->{use}} and (stat $inc{$import->{module}})[9] == $mtimes{$import->{use}} and ref $symbol_cache{$import->{use}} eq 'HASH')
        {
            foreach my $subroutine (keys %{$symbol_cache{$import->{use}}})
            {
                $functions{$import->{module}}{$subroutine} = 1;
            }
            next;
        } ## end if (-f $inc{$import->{...}})

        my %symbol_table_before = %ImportedPackageSymbols::;
        eval $import->{use};
        my %symbol_table_after = %ImportedPackageSymbols::;
        delete @symbol_table_after{keys %symbol_table_before};

        $functions{$import->{module}} = {};

        foreach my $subroutine (keys %symbol_table_after)
        {
            # Constants are created as scalar refs in the symbol table
            next if (ref $symbol_table_after{$subroutine} ne 'SCALAR' and ref $symbol_table_after{$subroutine} ne 'GLOB' and ref \($symbol_table_after{$subroutine}) ne 'GLOB');
            next if ((ref $symbol_table_after{$subroutine} eq 'GLOB' or ref \($symbol_table_after{$subroutine}) eq 'GLOB') and ref *{$symbol_table_after{$subroutine}}{CODE} ne 'CODE');
            $functions{$import->{module}}{$subroutine} = 1;
        } ## end foreach my $subroutine (keys...)

        # Reset symbol table and %INC
        %ImportedPackageSymbols:: = %symbol_table_before;
        my $module_path = $import->{module} =~ s/::/\//gr;
        $module_path .= '.pm';

        $mtimes{$import->{use}}       = (stat $INC{$module_path})[9];
        $inc{$import->{module}}       = $INC{$module_path};
        $symbol_cache{$import->{use}} = $functions{$import->{module}};

        delete $INC{$module_path};
    } ## end foreach my $import (@{$imports...})

    foreach my $module (keys %functions)
    {
        $functions{$module} = [keys %{$functions{$module}}];
    }

    print $json->encode(\%functions);
    print "\n";
} ## end while (my $line = <STDIN>...)
EOF

    return $code;
} ## end sub get_imported_package_symbols_code

1;
