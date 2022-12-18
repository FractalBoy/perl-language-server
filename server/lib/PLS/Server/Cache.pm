package PLS::Server::Cache;

use strict;
use warnings;

use feature 'state';

use ExtUtils::Installed;
use Module::CoreList;

use PLS::Parser::Pod;

sub warm_up
{
    get_builtin_variables();
    get_core_modules();
    get_ext_modules();

    return;
} ## end sub warm_up

sub get_ext_modules
{
    state $include = [];
    state $modules = [];

    my $curr_include    = join ':', @{$include};
    my $clean_inc       = PLS::Parser::Pod->get_clean_inc();
    my $updated_include = join ':', @{$clean_inc};

    if ($curr_include ne $updated_include or not scalar @{$modules})
    {
        $include = $clean_inc;
        my $installed = ExtUtils::Installed->new(inc_override => $clean_inc);

        foreach my $module ($installed->modules)
        {
            my @files = $installed->files($module);
            $module =~ s/::/\//g;

            # Find all the packages that are part of this module
            foreach my $file (@files)
            {
                next if ($file !~ /\.pm$/);
                my $valid = 0;

                foreach my $path (@{$clean_inc})
                {
                    $valid = 1 if ($file =~ s/^\Q$path\E\/?(?:auto\/)?//);
                }

                next unless ($valid);
                next unless (length $file);
                $file =~ s/\.pm$//;
                my $mod_package = $file =~ s/\//::/gr;

                # Skip private packages
                next if ($mod_package =~ /^_/ or $mod_package =~ /::_/);
                push @{$modules}, $mod_package;
            } ## end foreach my $file (@files)
        } ## end foreach my $module ($installed...)
    } ## end if ($curr_include ne $updated_include...)

    return $modules;
} ## end sub get_ext_modules

sub get_core_modules
{
    state $core_modules = [Module::CoreList->find_modules(qr//, $])];
    return $core_modules;
}

sub get_builtin_variables
{
    my $perldoc = PLS::Parser::Pod->get_perldoc_location();
    state $builtin_variables = [];

    return $builtin_variables if (scalar @{$builtin_variables});

    if (open my $fh, '-|', $perldoc, '-Tu', 'perlvar')
    {
        while (my $line = <$fh>)
        {
            if ($line =~ /=item\s*(C<)?([\$\@\%]\S+)\s*/)
            {
                # If variable started with pod sequence "C<" remove ">" from the end
                my $variable = $2;
                $variable = substr $variable, 0, -1 if (length $1);

                # Remove variables indicated by pod sequences
                next if ($variable =~ /^\$</ and $variable ne '$<');
                push @{$builtin_variables}, $variable;
            } ## end if ($line =~ /=item\s*(C<)?([\$\@\%]\S+)\s*/...)
        } ## end while (my $line = <$fh>)
    } ## end if (open my $fh, '-|',...)

    return $builtin_variables;
} ## end sub get_builtin_variables

1;
