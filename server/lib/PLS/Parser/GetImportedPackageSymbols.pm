package PLS::Parser::GetImportedPackageSymbols;

## no critic (RequireUseStrict, RequireUseWarnings)

my %mtimes;
my %symbol_cache;

sub get
{
    my ($in, $out) = @_;

    my $setup = $in->recv();

    if (scalar @{$setup})
    {
        my %setup = @{$setup};
        chdir $setup{chdir};
    }

    while (defined(my $imports = $in->recv()))
    {
        my %functions;

        foreach my $import (@{$imports})
        {
            my $module_path = $import->{module} =~ s/::/\//gr;
            $module_path .= '.pm';

            if (exists $mtimes{$module_path})
            {
                if ($mtimes{$module_path} == (stat $INC{$module_path})[9])
                {
                    if (ref $symbol_cache{$import->{use}} eq 'ARRAY')
                    {
                        foreach my $subroutine (@{$symbol_cache{$import->{use}}})
                        {
                            $functions{$import->{module}}{$subroutine} = 1;
                        }

                        next;
                    } ## end if (ref $symbol_cache{...})
                } ## end if ($mtimes{$module_path...})
                else
                {
                    delete $INC{$module_path};
                }
            } ## end if (exists $mtimes{$module_path...})

            package    ## no critic (ProhibitMultiplePackages) # hide from PAUSE
              ___ImportedPackageSymbols;
            my %symbol_table_before = %___ImportedPackageSymbols::;
            eval $import->{use};    ## no critic (ProhibitStringyEval)

            if ($@)
            {
                %___ImportedPackageSymbols:: = %symbol_table_before;
                $out->send({});
                next;
            } ## end if ($@)

            my %symbol_table_after = %___ImportedPackageSymbols::;
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
            %___ImportedPackageSymbols:: = %symbol_table_before;

            package PLS::Parser::GetImportedPackageSymbols;    ## no critic (ProhibitMultiplePackages)

            $mtimes{$module_path} = (stat $INC{$module_path})[9];
            $symbol_cache{$import->{use}} = \@subroutines;
        } ## end foreach my $import (@{$imports...})

        foreach my $module (keys %functions)
        {
            $functions{$module} = [keys %{$functions{$module}}];
        }

        $out->send(\%functions);
    } ## end while (defined(my $imports...))

    return;
} ## end sub get

1;

