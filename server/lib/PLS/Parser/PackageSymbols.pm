package PLS::Parser::PackageSymbols;

use strict;
use warnings;

use Fcntl    ();
use Storable ();

=head1 NAME

PLS::Parser::PackageSymbols

=head1 DESCRIPTION

This package executes a Perl process to import a package and interrogate
its symbol table to find all of the symbols in the package.

=cut

sub get_package_functions
{
    my ($package, $inc) = @_;

    return unless (length $package);

    # Fork off a process that imports the package
    # and gets a list of all the functions available.
    #
    # We fork to avoid polluting our own namespace.
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
        return if $timeout;
        waitpid $pid, 0;
        return if (ref $result ne 'HASH' or not $result->{ok});
        return $result->{functions};
    } ## end if ($pid)
    else
    {
        close $read_fh;

        my $flags = fcntl $write_fh, Fcntl::F_GETFD, 0;
        fcntl $write_fh, Fcntl::F_SETFD, $flags & ~Fcntl::FD_CLOEXEC;

        my $script = _get_package_functions_script(fileno($write_fh), $package);
        my @inc    = map { "-I$_" } @{$inc // []};
        exec $^X, @inc, '-e', $script;
    } ## end else [ if ($pid) ]
} ## end sub get_package_functions

sub _get_package_functions_script
{
    my ($fileno, $package) = @_;

    my $script = << 'EOF';
use File::Spec;
use Storable;
use Sub::Util;

open STDOUT, '>', File::Spec->devnull;
open STDERR, '>', File::Spec->devnull;

open my $write_fh, '>>&=', %d;
my $package = q{%s} =~ s/['"]//gr;

my @module_parts = split /::/, $package;
my @parent_module_parts = @module_parts;
pop @parent_module_parts;

my @functions;

foreach my $parts (\@parent_module_parts, \@module_parts)
{
    my $package = join '::', @{$parts};
    eval "require $package";
    next if $@;

    my $ref = \%%::;

    foreach my $part (@{$parts})
    {
        $ref = $ref->{"${part}::"};
    }

    foreach my $name (keys %%{$ref})
    {
        next if $name =~ /^BEGIN|UNITCHECK|INIT|CHECK|END|VERSION|import$/;
        my $code_ref = $package->can($name);
        next unless (ref $code_ref eq 'CODE');
        next if Sub::Util::subname($code_ref) !~ /^${package}(?:::.+)*::${name}$/;
        push @functions, $name;
    } ## end foreach my $name (keys %%{$ref...})
}

Storable::nstore_fd({ok => 1, functions => \@functions}, $write_fh);
EOF

    return sprintf $script, $fileno, $package;
} ## end sub _get_package_functions_script

1;
