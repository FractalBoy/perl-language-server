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

Install the PLS package from CPAN: https://metacpan.org/pod/PLS

## Setup

### VSCode

Install the fractalboy.pls extension in Visual Studio Code: https://marketplace.visualstudio.com/items?itemName=FractalBoy.pls

### Neovim

This assumes Neovim 0.5.0 or greater.

Install [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig).

nvim-lspconfig comes with a default configuration for PLS and its name is `perlpls` (do not confuse this with `perlls` which is the default configuration for Perl::LanguageServer). 

The simplest means of configuring PLS is to place the following somewhere in your Neovim config:
```
require'lspconfig'.perlpls.setup()
```
This will set you up with the defaults. It assumes that `pls` is in your $PATH. By default Perl Critic integration will be turned off.

A more complex configuration will look like this:
```
local config = {
  cmd = { '/opt/bin/pls' }, -- complete path to where PLS is located
  settings = { 
    perl = { 
      inc = { '/my/perl/5.34/lib', '/some/other/perl/lib' },  -- add list of dirs to @INC
      cwd = { '/my/projects' },   -- working directory for PLS
      perlcritic = { enabled = true, perlcriticrc = '/my/projects/.perlcriticrc' },  -- use perlcritic and pass a non-default location for its config
      syntax = { enabled = true, perl = '/usr/bin/perl' }, -- enable syntax checking and use a non-default perl binary
      perltidyrc = '/my/projects/.perltidyrc'  -- non-default location for perltidy's config
    } 
  }
}
require'lspconfig'.perlpls.setup(config)
```
See `perldoc PLS` for more details about the configuration items.

The above assumes a Lua configuration. If you are using a Vimscript configuration remember to wrap everything in a Lua here-doc, e.g.:
```
lua <<EOF
...config...
EOF
```

### BBEdit

BBEdit version 14.0 and higher adds support for Language Server Protocols, including PLS. Add the following JSON configuration file, adjusting paths accordingly, to the folder `~/Library/Application Support/BBEdit/Language Servers/Configuration/`. Then enable the language server support for Perl following their [recommendations](https://www.barebones.com/support/bbedit/lsp-notes.html), selecting the file you saved for the configuration.

```
{
  "initializationOptions": {},
  "workspaceConfigurations": {
    "*": {
      "perl": {
        "inc": [],
        "syntax": {
          "enabled": true,
          "perl": "/usr/bin/perl"
        },
        "perltidyrc": "~/.perltidyrc",
        "perlcritic": {
          "enabled": true,
          "perlcriticrc": "~/.perlcriticrc"
        },
        "cwd": "."
      }
    }
  }
}
```


## Configuration

1. Optionally, add paths to `@INC` by modifying the `perl.inc` setting. You can use the `$ROOT_PATH` mnemonic to stand in for your project's root directory, for example `$ROOT_PATH/lib`. PLS does not yet support multiple workspace folders.
2. Optionally, change the current working directory to run PLS in by modifying the `perl.cwd` setting.
3. Optionally, configure the path to your `.perltidyrc` file using the `perl.perltidyrc` setting. By default, `~/.perltidyrc` is used.
4. Optionally, configure the path to your `.perlcriticrc` file using the `perl.perlcritic.perlcriticrc` setting. By default, `~/.perlcriticrc` is used. You can also disable `perlcritic` checking entirely by disabling the `perl.perlcritic.enabled` setting.
5. Optionally, configure the path to an alternate `perl` to use for syntax checking using the `perl.syntax.perl` setting. By default, the `perl` used to run PLS will be used. You can also disable syntax checking entirely by disabling the `perl.syntax.enabled` setting. 
6. Optionally, create a `.plsignore` file in your workspace root with Perl glob patterns that you do not wish to index. By default, PLS will index all files that look like Perl files, with the exception of `.t` files. If you have a lot of files that are not Perl files in your workspace, it may slow down indexing unless they are ignored. This is the case for PLS itself, where the entire `client` directory is not Perl and contains many small files in `node_modules`.

