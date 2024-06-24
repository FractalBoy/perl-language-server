package PLS::Util;

use strict;
use warnings;

sub resolve_workspace_relative_path
{
    my ($path, $workspace_folders, $no_glob) = @_;

    if (not length $path)
    {
        return;
    }

    if (ref $workspace_folders ne 'ARRAY' or not scalar @{$workspace_folders})
    {
        require PLS::Parser::Index;
        $workspace_folders = PLS::Parser::Index->new->workspace_folders;
    }

    my @resolved;

    foreach my $workspace_folder (@{$workspace_folders})
    {
        my $resolved = $path =~ s/\$ROOT_PATH/$workspace_folder/r;
        $resolved =~ s/\$\{workspaceFolder\}/$workspace_folder/;

        if (not $no_glob)
        {
            ($resolved) = glob $resolved;
        }

        if (length $resolved)
        {
            push @resolved, $resolved;
        }
    } ## end foreach my $workspace_folder...

    return @resolved;
} ## end sub resolve_workspace_relative_path

1;
