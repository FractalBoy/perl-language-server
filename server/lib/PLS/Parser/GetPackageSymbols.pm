package PLS::Parser::GetPackageSymbols;

## no critic (RequireUseStrict, RequireUseWarnings)

use B;

my %mtimes;

sub get
{
    my ($in, $out) = @_;

    my $setup = $in->recv();

    if (scalar @{$setup})
    {
        my %setup = @{$setup};
        chdir $setup{chdir};
    }

    while (defined(my $packages_to_find = $in->recv()))
    {
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
                    next if $name =~ /^\(/;                                                                        # overloaded operators start with a parenthesis

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

        $out->send(\%functions);
    } ## end while (defined(my $packages_to_find...))

    return;
} ## end sub get

sub add_parent_classes
{
    my ($package) = @_;

    my @isa = @{${"${package}::"}{ISA}};
    return unless (scalar @isa);

    foreach my $isa (@isa)
    {
        push @isa, add_parent_classes($isa);
    }

    return @isa;
} ## end sub add_parent_classes

1;
