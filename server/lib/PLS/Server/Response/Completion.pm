package PLS::Server::Response::Completion;

use strict;
use warnings;

use parent q(PLS::Server::Response);

use Fcntl;
use Pod::Functions;
use Module::CoreList;
use Module::Metadata;
use ExtUtils::Installed;
use Storable;

use PLS::Parser::Document;
use PLS::Parser::Pod;
use Trie;

sub new
{
    my ($class, $request) = @_;

    my $self = bless {id => $request->{id}, result => undef}, $class;

    my $document = PLS::Parser::Document->new(uri => $request->{params}{textDocument}{uri}, line => $request->{params}{position}{line});
    return $self unless (ref $document eq 'PLS::Parser::Document');

    my ($range, $arrow, $package, $filter) = $document->find_word_under_cursor(@{$request->{params}{position}}{qw(line character)});

    if (ref $range eq 'HASH')
    {
        $range->{start}{line} = $request->{params}{position}{line};
        $range->{end}{line}   = $request->{params}{position}{line};
    }

    return $self unless (ref $range eq 'HASH');
    $package =~ s/::$// if (length $package);

    my @results;
    my %seen_subs;
    my $functions;

    if (length $package)
    {
        # Fork off a process that imports the package
        # and gets a list of all the functions available.
        #
        # We fork to avoid polluting our own namespace.
        # This will only work for core modules.
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
            $functions = $result->{functions} if (not $timeout and ref $result eq 'HASH' and $result->{ok});
            waitpid $pid, 0;
        } ## end if ($pid)
        else
        {
            close $read_fh;

            my $flags = fcntl $write_fh, F_GETFD, 0;
            fcntl $write_fh, F_SETFD, $flags & ~FD_CLOEXEC;

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

            $script = sprintf $script, fileno($write_fh), $package;
            exec $^X, '-e', $script;
        } ## end else [ if ($pid) ]
    } ## end if (length $package)

    if (ref $functions eq 'ARRAY')
    {
        my $separator = $arrow ? '->' : '::';

        foreach my $name (@{$functions})
        {
            next if $seen_subs{$name}++;

            my $fully_qualified = join $separator, $package, $name;
            my $result = {
                          label    => $name,
                          sortText => $fully_qualified,
                          kind     => 3
                         };

            unless ($arrow)
            {
                $result->{filterText} = $fully_qualified;
                $result->{insertText} = $fully_qualified;
            }

            push @results, $result;
        } ## end foreach my $name (@{$functions...})
    } ## end if (ref $functions eq ...)

    my $subs     = $document->{index}{subs_trie}->find($filter);
    my $packages = $document->{index}{packages_trie}->find($filter);

    foreach my $family (keys %Pod::Functions::Kinds)
    {
        foreach my $sub (@{$Pod::Functions::Kinds{$family}})
        {
            next if $sub =~ /\s+/;
            next if $seen_subs{$sub}++;
            push @results,
              {
                label => $sub,
                kind  => 3
              };
        } ## end foreach my $sub (@{$Pod::Functions::Kinds...})
    } ## end foreach my $family (keys %Pod::Functions::Kinds...)

    my %seen_packages;

    foreach my $module (Module::CoreList->find_modules(qr//, $]))
    {
        next if $seen_packages{$module}++;
        push @results,
          {
            label => $module,
            kind  => 7
          };
    } ## end foreach my $module (Module::CoreList...)

    my $include  = PLS::Parser::Pod->get_clean_inc();
    my $extutils = ExtUtils::Installed->new(inc_override => $include);

    foreach my $module ($extutils->modules)
    {
        next if $seen_packages{$module}++;
        push @results,
          {
            label => $module,
            kind  => 7
          };
    } ## end foreach my $module ($extutils...)

    foreach my $sub (@{$document->get_subroutines_fast()})
    {
        next if $seen_subs{$sub}++;

        push @results,
          {
            label => $sub,
            kind  => 3
          };
    } ## end foreach my $sub (@{$document...})

    my %seen_constants;

    foreach my $constant (@{$document->get_constants_fast()})
    {
        next if $seen_constants{$constant}++;
        push @results,
          {
            label => $constant,
            kind  => 21
          };
    } ## end foreach my $constant (@{$document...})

    my %seen_variables;

    foreach my $variable (@{$document->get_variables_fast()})
    {
        next if $seen_variables{$variable}++;
        push @results,
          {
            label => $variable,
            kind  => 6
          };

        # add other variable forms to the list for arrays and hashes
        if ($variable =~ /^[\@\%]/)
        {
            my $name   = $variable =~ s/^[\@\%]/\$/r;
            my $append = $variable =~ /^\@/ ? '[' : '{';
            push @results,
              {
                label      => $variable,
                insertText => $name . $append,
                filterText => $name,
                kind       => 6
              };
        } ## end if ($variable =~ /^[\@\%]/...)
    } ## end foreach my $variable (@{$document...})

    foreach my $pack (@{$document->get_packages_fast()})
    {
        next if $seen_packages{$pack}++;
        push @results,
          {
            label => $pack,
            kind  => 7
          };
    } ## end foreach my $pack (@{$document...})

    $subs     = [] unless (ref $subs eq 'ARRAY');
    $packages = [] unless (ref $packages eq 'ARRAY');

    @$subs     = map { {label => $_, kind => 3} } grep { not $seen_subs{$_}++ } @$subs;
    @$packages = map { {label => $_, kind => 7} } grep { not $seen_packages{$_}++ } @$packages;

    @results = (@results, @$subs, @$packages);

    foreach my $result (@results)
    {
        my $new_text = $result->{label};
        $new_text = $result->{insertText} if (length $result->{insertText});
        delete $result->{insertText};

        push @{$self->{result}},
          {
            %$result,
            textEdit => {newText => $new_text, range => $range},
            data     => $request->{params}{textDocument}{uri}
          };
    } ## end foreach my $result (@results...)

    return $self;
} ## end sub new

1;
