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

    return _send_data_and_recv_result($package_symbols_process, \@packages);
} ## end sub get_package_symbols

sub get_imported_package_symbols
{
    my ($config, @imports) = @_;

    return Future->done({}) unless (scalar @imports);

    start_imported_package_symbols_process($config) if (ref $imported_symbols_process ne 'IO::Async::Process');

    return _send_data_and_recv_result($imported_symbols_process, \@imports);
} ## end sub get_imported_package_symbols

sub _start_process
{
    my ($config, $code) = @_;

    my $perl = PLS::Parser::Pod->get_perl_exe();
    my @inc  = map { "-I$_" } @{$config->{inc}};
    my $args = PLS::Parser::Pod->get_perl_args();

    my $script_name = $0 =~ s/'/\'/gr;
    $code = "\$0 = '$script_name';\n$code";

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

sub _send_data_and_recv_result
{
    my ($process, $data) = @_;

    $data = encode_json $data;

    return $process->stdin->write("$data\n")->then(sub { $process->stdout->read_until("\n") })->then(
        sub {
            my ($json) = @_;

            return Future->done(eval { decode_json $json } // {});
        },
        sub { Future->done({}) }
    );
} ## end sub _send_data_and_recv_result

sub start_package_symbols_process
{
    my ($config) = @_;

    eval { $package_symbols_process->kill('TERM') } if (ref $package_symbols_process eq 'IO::Async::Process');
    $package_symbols_process = _start_process($config, get_package_symbols_code());

    return;
} ## end sub start_package_symbols_process

sub start_imported_package_symbols_process
{
    my ($config) = @_;

    eval { $imported_symbols_process->kill('TERM') } if (ref $package_symbols_process eq 'IO::Async::Process');
    $imported_symbols_process = _start_process($config, get_imported_package_symbols_code());

    return;
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

use B;

my $json_package = 'JSON::PP';

if (eval { require Cpanel::JSON::XS; 1 })
{
    $json_package = 'Cpanel::JSON::XS';
}
elsif (eval { require JSON::XS; 1 })
{
    $json_package = 'JSON::XS';
}
else
{
    require JSON::PP;
}

$| = 1;

my $json = $json_package->new->utf8;

package PackageSymbols;

my %mtimes;

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

            my $package_path = $package =~ s/::/\//gr;
            $package_path .= '.pm';

            if (exists $mtimes{$package_path} and $mtimes{$package_path} != (stat $INC{$package_path})[9])
            {
                delete $INC{$package_path};
            }

            eval "require $package";
            next unless (length $INC{$package_path});

            $mtimes{$package_path} = (stat $INC{$package_path})[9];

            push @packages, $package;

            my @isa = add_parent_classes($package);

            foreach my $isa (@isa)
            {
                my $isa_path = $isa =~ s/::/\//gr;
                $isa_path .= '.pm';

                if (exists $mtimes{$isa_path} and $mtimes{$isa_path} != (stat $INC{$isa_path})[9])
                {
                    delete $INC{$isa_path};
                }

                eval "require $isa";
                next if (length $@);

                $mtimes{$isa_path} = (stat $INC{$isa_path})[9];

                push @packages, $isa;
            } ## end foreach my $isa (@isa)
        } ## end foreach my $parts (\@parent_module_parts...)

        foreach my $package (@packages)
        {
            my @parts = split /::/, $package;
            my $ref   = \%{"${package}::"};

            foreach my $name (keys %{$ref})
            {
                next if $name =~ /^BEGIN|UNITCHECK|INIT|CHECK|END|VERSION|DESTROY|import|unimport|can|isa$/;
                next if $name =~ /^_/;                                                                         # hide private subroutines
                next if $name =~ /^\(/; # overloaded operators start with a parenthesis

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
        } ## end foreach my $package (@packages...)
    } ## end foreach my $find_package (@...)

    print $json->encode(\%functions);
    print "\n";
} ## end while (my $line = <STDIN>...)

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
#close STDERR;

my $json_package = 'JSON::PP';

if (eval { require Cpanel::JSON::XS; 1 })
{
    $json_package = 'Cpanel::JSON::XS';
}
elsif (eval { require JSON::XS; 1 })
{
    $json_package = 'JSON::XS';
}
else
{
    require JSON::PP;
}

$| = 1;

my $json = $json_package->new->utf8;

package ImportedPackageSymbols;

my %mtimes;
my %symbol_cache;

while (my $line = <STDIN>)
{
    my $imports = $json->decode($line);

    my %functions;

    foreach my $import (@{$imports})
    {
        my $module_path = $import->{module} =~ s/::/\//gr;
        $module_path .= '.pm';

        if (exists $mtimes{$module_path})
        {
            if ($mtimes{$module_path} == (stat $INC{$module_path})[9])
            {
                if (ref $symbol_cache{$module->{use}} eq 'ARRAY')
                {
                    foreach my $subroutine (@{$symbol_cache{$module->{use}}})
                    {
                        $functions{$import->{module}}{$subroutine} = 1;
                    }

                    next;
                } ## end if (ref $symbol_cache{...})
            } ## end if (length $module_abs_path...)
            else
            {
                delete $INC{$module_path};
            }
        }

        my %symbol_table_before = %ImportedPackageSymbols::;
        eval $import->{use};
        my %symbol_table_after = %ImportedPackageSymbols::;
        delete @symbol_table_after{keys %symbol_table_before};

        my @subroutines;

        foreach my $subroutine (keys %symbol_table_after)
        {
            # Constants are created as scalar refs in the symbol table
            next if (ref $symbol_table_after{$subroutine} ne 'SCALAR' and ref $symbol_table_after{$subroutine} ne 'GLOB' and ref \($symbol_table_after{$subroutine}) ne 'GLOB');
            next if ((ref $symbol_table_after{$subroutine} eq 'GLOB' or ref \($symbol_table_after{$subroutine}) eq 'GLOB') and ref *{$symbol_table_after{$subroutine}}{CODE} ne 'CODE');
            $functions{$import->{module}}{$subroutine} = 1;
            push @subroutines, $subroutine;
        } ## end foreach my $subroutine (keys...)

        # Reset symbol table
        %ImportedPackageSymbols:: = %symbol_table_before;

        $mtimes{$module_path} = (stat $INC{$module_path})[9];
        $symbol_cache{$import->{use}} = \@subroutines;
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
