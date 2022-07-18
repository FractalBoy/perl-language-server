package PLS::Parser::PackageFunctions;

use strict;

use Sub::Util ();

## no critic (ProhibitStringyEval, RequireCheckingReturnValueOfEval, RequireUseWarnings)

$SIG{__WARN__} = sub { };

sub get_package_functions
{
    my ($channel_in, $channel_out) = @_;

    while (my $packages_to_find = $channel_in->recv)
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

                # Unrequire packages
                my $package_path = $package =~ s/::/\//gr;
                $package_path .= '.pm';
                delete $INC{$package_path};
            } ## end foreach my $package (@packages...)
        } ## end foreach my $find_package (@...)

        $channel_out->send(\%functions);
    } ## end while (my $packages_to_find...)

    return;
} ## end sub get_package_functions

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

sub get_imported_functions
{
    my ($channel_in, $channel_out) = @_;

    while (my $imports = $channel_in->recv)
    {
        my %functions;

        foreach my $import (@{$imports})
        {
            my %symbol_table_before = %PLS::Parser::PackageFunctions::;
            eval $import->{use};
            my %symbol_table_after = %PLS::Parser::PackageFunctions::;
            delete @symbol_table_after{keys %symbol_table_before};

            foreach my $subroutine (keys %symbol_table_after)
            {
                next if (ref eval { *{$symbol_table_after{$subroutine}}{CODE} } ne 'CODE');
                push @{$functions{$import->{module}}}, $subroutine;
            }

            # Reset symbol table and %INC
            %PLS::Parser::PackageFunctions:: = %symbol_table_before;
            my $module_path = $import->{module} =~ s/::/\//gr;
            $module_path .= '.pm';
            delete $INC{$module_path};
        } ## end foreach my $import (@{$imports...})

        $channel_out->send(\%functions);
    } ## end while (my $imports = $channel_in...)

    return;
} ## end sub get_imported_functions

1;
