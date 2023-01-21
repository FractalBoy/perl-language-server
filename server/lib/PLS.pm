package PLS;

use strict;
use warnings;

our $VERSION = '0.905';

=head1 NAME

PLS - Perl Language Server

=head1 DESCRIPTION

The Perl Language Server implements a subset of the Language Server Protocol
for the Perl language. Features currently implemented are:

=over

=item * Go to definition (for packages, subroutines, and variables)

=item * Listing all symbols in a document

=item * Hovering to show documentation

=item * Signature help (showing parameters for a function as you type)

=item * Formatting

=item * Range Formatting

=item * Auto-completion

=item * Syntax checking

=item * Linting (using perlcritic)

=item * Sorting imports

=back

=head1 OPTIONS

This application does not take any command line options.
The following settings may be configured using your text editor:

=over

=item pls.cmd - path to pls

Make sure that C<pls.cmd> is set to the path to the C<pls> script on your system.
If you rely on your C<$PATH>, ensure that your editor is configured with the correct
path, which may not be the same one that your terminal uses.

=item pls.args - args to pass to the pls command

Add any additional arguments needed to execute C<pls> to the C<pls.args> setting.
For example, if you run C<pls> in a docker container, C<pls.cmd> would be C<docker>, and
C<pls.args> would be C<< ["run", "--rm", "-i", "<image name>", "pls"] >>.

=item pls.inc - a list of paths to add to C<@INC>

You can use the C<$ROOT_PATH> mnemonic to stand in for your project's root directory,
for example C<$ROOT_PATH/lib>. If you are using multiple workspace folders and use
C<$ROOT_PATH>, the path will be multiplied by the number of workspace folders,
and will be replaced that many times. This is useful if you use SVN and check out
each branch to a different directory.

=item pls.cwd - the working directory to use for pls

If you use C<$ROOT_PATH>, it will be replaced by your workspace's first
or only folder.

=item pls.perltidy.perltidyrc - the location of your C<.perltidyrc> file.

Defaults to C<~/.perltidyrc> if not configured.

=item pls.perlcritic.enabled - whether to enable linting using L<perlcritic>.

=item pls.perlcritic.perlcriticrc - the location of your C<.perlcriticrc> file.

Defaults to C<~/.perlcriticrc> if not configured.

=item pls.syntax.enabled - whether to enable syntax checking.

=item pls.syntax.perl - path to an alternate C<perl> to use for syntax checking.

Defaults to the C<perl> used to run PLS.

=item pls.syntax.args - additional arguments to pass when syntax checking.

This is useful if there is a BEGIN block in your code that changes
behavior depending on the contents of @ARGV.

=back

You may configure a .plsignore file in your project's root directory, with
a list of Perl glob patterns which you do not want pls to index.

By default, PLS will index all files ending with `.pl`, `.pm`,
or have `perl` in the shebang line that are not `.t` files.

=head1 CAVEATS

pls is known to be compatible with Visual Studio Code, Neovim, and BBEdit.

pls will perform much better if you have an XS JSON module installed.
If you install L<Cpanel::JSON::XS> or L<JSON::XS>, it will use one of those
before falling back to L<JSON::PP>, similar to L<JSON::MaybeXS>.

=head1 NOTES

Refer to this README for instructions on configuring your specific editor:
L<https://marketplace.visualstudio.com/items?itemName=FractalBoy.pls>

=head1 COPYRIGHT

Copyright 2022 Marc Reisner

=head1 LICENSE

This library is free software; you may redistribute it and/or
modify it under the same terms as Perl itself.

=cut

1;
