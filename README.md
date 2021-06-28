Perl Language Server
====================

PLS implements features of the [Language Server Protocol](https://microsoft.github.io/language-server-protocol/) for Perl 5.

It is still very much in its early stages and Pull Requests are more than welcome.

The features currently implemented are:

* Go to definition (for packages, subroutines, and variables)
* Listing all symbols in a document
* Hovering to show documentation
* Signature help (showing parameters for a function as you type)
* Formatting
* Range Formatting
* Auto-completion
* Syntax checking
* Linting (using perlcritic)
* Sorting imports

## Installation

1. Install the fractalboy.pls extension in Visual Studio Code: https://marketplace.visualstudio.com/items?itemName=FractalBoy.pls
2. Install the PLS package from CPAN: https://metacpan.org/pod/PLS

## Configuration

1. Optionally, add paths to @INC by modifying the `perl.inc` setting. You can use the $ROOT_PATH mnemonic to stand in for your project's root directory. PLS does not yet support multiple workspace folders.
2. Optionally, change the current working directory to run PLS in by modifying the `perl.cwd` setting.
3. Optionally, configure the path to your .perltidyrc file using the `perl.perltidyrc` setting. By default, `~/.perltidyrc` is used.
4. Optionally, configure the path to your .perlcriticrc file using the `perl.perlcritic.perlcriticrc` setting. By default, `~/.perlcriticrc` is used. You can also disable perlcritic checking entirely by disabling the `perl.perlcritic.enabled` setting.
5. Optionally, create a .plsignore file in your workspace root with Perl glob patterns that you do not wish to index. By default, PLS will index all files that look like Perl files, with the exception of `.t` files. If you have a lot of files that are not Perl files in your workspace, it may slow down indexing unless they are ignored. This is the case for PLS itself, where the entire `client` directory is not Perl and contains many small files in `node_modules`.
