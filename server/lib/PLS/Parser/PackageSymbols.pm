package PLS::Parser::PackageSymbols;

use strict;
use warnings;

use Fcntl    ();
use Storable ();

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
        waitpid $pid, 0;
        return if ($timeout or ref $result ne 'HASH' or not $result->{ok});
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

eval "require $package";

if (length $@)
{
    Storable::nstore_fd({ok => 0}, $write_fh);
}
else
{
    my $ref = \%% ::;
    my @module_parts = split /::/, $package;

    foreach my $part (@module_parts)
    {
        $ref = $ref->{"${part}::"};
    }

    my @functions;

    foreach my $name (keys %%{$ref})
    {
        next if $name =~ /^BEGIN|UNITCHECK|INIT|CHECK|END|VERSION|import$/;
        my $code_ref = $package->can($name);
        next unless (ref $code_ref eq 'CODE');
        next unless Sub::Util::subname($code_ref) eq "${package}::${name}";
        push @functions, $name;
    } ## end foreach my $name (keys %%{$ref...})

    Storable::nstore_fd({ok => 1, functions => \@functions}, $write_fh);
} ## end else [ if (length $@) ]
EOF

    return sprintf $script, $fileno, $package;
} ## end sub _get_package_functions_script

1;
