package PLS::Parser::PackageSymbols;

use strict;
use warnings;

use Fcntl ();
use Storable ();

=head1 NAME

PLS::Parser::PackageSymbols

=head1 DESCRIPTION

This package executes a Perl process to import a package and interrogate
its symbol table to find all of the symbols in the package.

=cut

my $script = do { local $/; <DATA> };

sub get_package_functions
{
    my ($package, $config) = @_;

    return unless (length $package);

    pipe my $read_fh, my $write_fh;
    my $pid = fork;

    if ($pid)
    {
        close $write_fh;

        my $timeout = 0;
        local $SIG{ALRM} = sub { $timeout = 1 };
        alarm 10;
        my $result = eval { Storable::fd_retrieve($read_fh) };
        alarm 0;

        if ($timeout)
        {
            kill 'KILL', $pid;
            waitpid $pid, 0;
            return;
        }

        waitpid $pid, 0;
        return if (ref $result ne 'HASH' or not $result->{ok});
        return $result->{functions};
    }
    else
    {
        close $read_fh;

        my $flags = fcntl $write_fh, Fcntl::F_GETFD, 0;
        fcntl $write_fh, Fcntl::F_SETFD, $flags & ~Fcntl::FD_CLOEXEC;

        my @inc = map { "-I$_" } @{$config->{inc} // []};
        my $perl = $config->{syntax}{perl};
        $perl = $^X unless (-x $perl);
        exec $^X, @inc, '-e', $script, fileno($write_fh), $package;
    }
} ## end sub get_package_functions

1;

__DATA__
use File::Spec;
use Storable ();
use Sub::Util ();

open STDOUT, '>', File::Spec->devnull;
open STDERR, '>', File::Spec->devnull;

open my $write_fh, '>>&=', $ARGV[0];
my $find_package = $ARGV[1];

my @module_parts        = split /::/, $find_package;
my @parent_module_parts = @module_parts;
pop @parent_module_parts;

my %functions;
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
    }
}

foreach my $package (@packages)
{
    my @parts = split /::/, $package;
    my $ref = \%::;

    foreach my $part (@parts)
    {
        $ref = $ref->{"${part}::"};
    }

    foreach my $name (keys %{$ref})
    {
        next if $name =~ /^BEGIN|UNITCHECK|INIT|CHECK|END|VERSION|import|unimport$/;

        my $code_ref = $package->can($name);
        next if (ref $code_ref ne 'CODE');
        next if Sub::Util::subname($code_ref) !~ /^\Q$package\E(?:::.+)*::\Q$name\E$/;

        if ($find_package->isa($package))
        {
            push @{$functions{$find_package}}, $name;
        }
        else
        {
            push @{$functions{$package}}, $name;
        }
    } ## end foreach my $name (keys %{$ref...})
} ## end foreach my $parts (\@parent_module_parts...)

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
}

Storable::nstore_fd({ok => 1, functions => \%functions}, $write_fh);
