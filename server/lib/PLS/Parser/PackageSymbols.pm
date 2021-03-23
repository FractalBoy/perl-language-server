package PLS::Parser::PackageSymbols;

use Fcntl ();
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
        return if ($timeout or ref $result ne 'HASH' or not $result->{ok});
        waitpid $pid, 0;
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
use Storable;

local $SIG{__WARN__} = sub { };

open my $write_fh, '>>&=', %d;
my $package = '%s';

# check to see if we can import it
eval "require $package";

if (length $@)
{
    my @parts = split /::/, $package;
    $package = join '::', @parts[0 .. $#parts - 1];
    eval "require $package";
} ## end if (length $@)

if (length $package and not length $@)
{
    my $ref = \%%::;
    my @module_parts = split /::/, $package;

    foreach my $part (@module_parts)
    {
        $ref = $ref->{"${part}::"};
    }

    my @functions;

    foreach my $name (keys %%{$ref})
    {
        next if $name =~ /^BEGIN|UNITCHECK|INIT|CHECK|END|VERSION|import$/;
        next unless $package->can($name);
        push @functions, $name;
    } ## end foreach my $name (keys %%{$ref...})

    Storable::nstore_fd({ok => 1, functions => \@functions}, $write_fh);
} ## end if (length $package and...)
else
{
    Storable::nstore_fd({ok => 0}, $write_fh);
}
EOF

    return sprintf $script, $fileno, $package;
} ## end sub _get_package_functions_script

1;
