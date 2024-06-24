package PLS::Util;

use strict;
use warnings;

=head1 NAME

PLS::Util

=head1 DESCRIPTION

Utility functions for PLS

=head1 FUNCTIONS

=head2 resolve_workspace_relative_path

Given a path, potentially with ${workspaceFolder} or $ROOT_PATH,
returns a list of paths with those variables resolved to an actual workspace folder.
Additionally, any needed globbing will be performed.

The returned list will only contain paths that exist.

=head3 PARAMETERS

=over

=item path

The path from user configuration that needs to be resolved.

=item workspace_folders

An array of the workspace folders. If empty or not passed, this list will
be queried from L<PLS::Parser::Index>.

=item no_glob

If true, no globbing will be performed against the path.

=back

=cut

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

        if (not length $resolved)
        {
            next;
        }

        if ($no_glob)
        {
            if (length $resolved and -e $resolved)
            {
                push @resolved, $resolved;
            }
        } ## end if ($no_glob)
        else
        {
            push @resolved, grep { length and -e } glob $resolved;
        }
    } ## end foreach my $workspace_folder...

    return @resolved;
} ## end sub resolve_workspace_relative_path

1;
