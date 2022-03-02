package PLS;

use strict;
use warnings;

our $VERSION = '0.899';

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

=item perl.inc - a list of paths to include in @INC

You can use $ROOT_PATH to stand in for your project's root directory,
to allow for configuration to work the same for multiple directories
of the same project. This is useful if you use SVN and check out each
branch to a different directory.

=item perl.pls - path to pls

Configure this option if pls is not available in your path.

=item perl.cwd - the working directory to use for pls

=item perl.perltidyrc - the location of your C<.perltidyrc> file.

Defaults to C<~/.perltidyrc> if not configured.

=item perl.perlcritic.enabled - whether to enable linting using L<perlcritic>.

=item perl.perlcritic.perlcriticrc - the location of your C<.perlcriticrc> file.

Defaults to C<~/.perlcriticrc> if not configured.

=back

You may configure a .plsignore file in your project's root directory, with
a list of Perl glob patterns which you do not want pls to index.

By default, pls will index everything that looks like a Perl file, with the
exception of C<.t> files.

=head1 CAVEATS

pls has not been tested with editors other than Visual Studio Code and Neovim.

=head1 NOTES

Install the L<fractalboy.pls|https://marketplace.visualstudio.com/items?itemName=FractalBoy.pls>
extension to Visual Studio Code in order to use this language server.

=head1 COPYRIGHT

Copyright 2022 Marc Reisner

=head1 LICENSE

This library is free software; you may redistribute it and/or
modify it under the same terms as Perl itself.

=cut

1;
