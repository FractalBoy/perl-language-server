package PLS::Parser::PackageSymbols;

use strict;
use warnings;

use Fcntl ();
use File::Spec;
use List::Util;
use Storable ();

=head1 NAME

PLS::Parser::PackageSymbols

=head1 DESCRIPTION

This package executes a Perl process to import a package and interrogate
its symbol table to find all of the symbols in the package.

=cut

my $loop = IO::Async::Loop->new();
my $function = IO::Async::Function->new(
    min_workers => 1,      # Always keep one process running, for better performance.
    code        => sub {
        my ($package, $inc) = @_;

        push @INC, @{$inc};
        @INC = List::Util::uniq @INC;

        open STDOUT, '>', File::Spec->devnull;
        open STDERR, '>', File::Spec->devnull;

        my @module_parts        = split /::/, $package;
        my @parent_module_parts = @module_parts;
        pop @parent_module_parts;

        my %functions;
        my %already_imported = map { $_ => 1 } map { s/\.pm$//r } map { s/\//::/gr } keys %INC;

        foreach my $parts (\@parent_module_parts, \@module_parts)
        {
            my $package = join '::', @{$parts};
            next unless (length $package);

            unless ($already_imported{$package})
            {
                eval "require $package";
                next if (length $@);
            }

            my $ref = \%::;

            foreach my $part (@{$parts})
            {
                $ref = $ref->{"${part}::"};
            }

            foreach my $name (keys %{$ref})
            {
                next if $name =~ /^BEGIN|UNITCHECK|INIT|CHECK|END|VERSION|import|unimport$/;
                my $code_ref = $package->can($name);
                next if (ref $code_ref ne 'CODE');
                next if Sub::Util::subname($code_ref) !~ /^\Q$package\E(?:::.+)*::\Q$name\E$/;
                push @{$functions{$package}}, $name;
            } ## end foreach my $name (keys %{$ref...})
        } ## end foreach my $parts (\@parent_module_parts...)

        return \%functions;
    }
);

$loop->add($function);

sub get_package_functions
{
    my ($package, $inc) = @_;

    return unless (length $package);

    return $function->call(args => [$package, $inc])->get;
} ## end sub get_package_functions

1;
