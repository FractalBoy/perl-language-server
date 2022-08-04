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

### Emacs `lsp-mode`

Several LSP client implementations for
[Emacs](https://www.gnu.org/software/emacs/) exist in the form of
Emacs packages. This installation instruction covers the [LSP
Mode](https://emacs-lsp.github.io/lsp-mode/) package.

1. Install the the [LSP Mode](https://emacs-lsp.github.io/lsp-mode/)
   package for Emacs as described in the [`lsp-mode` install
   instructions](https://emacs-lsp.github.io/lsp-mode/page/installation/).

2. Add the following to your Emacs init file:

   ```
   (add-to-list 'lsp-language-id-configuration '(perl-mode . "perl-pls"))
   (add-to-list 'lsp-language-id-configuration '(cperl-mode . "perl-pls"))
   (lsp-register-client
    (make-lsp-client :new-connection (lsp-stdio-connection "pls")
                     :major-modes '(perl-mode cperl-mode)
                     :server-id 'perl-pls))
   ```

That's all. Now, a PLS server instance will be fired up when not
already running, whenever a Perl file is opened in Emacs. For what to
do next, see the extensive [LSP Mode
documentation](https://emacs-lsp.github.io/lsp-mode/page/main-features/).

## Configuration

* Make sure that `perl.pls` is set to the path to the `pls` script on your system.
If you rely on your `$PATH`, ensure that your editor is configured with the correct
path, which may not be the same one that your terminal uses.
* Add any additional arguments needed to execute `pls` to the `perl.plsargs` setting.
For example, if you run `pls` in a docker container, `perl.pls` would be `docker`, and
`perl.plsargs` would be `["run", "--rm", "-i", "<image name>", "pls"]`.
* Optionally, change the current working directory to run PLS in by modifying the `perl.cwd` setting. If you use `$ROOT_PATH` here, it will be replaced by the first or only workspace folder.
* Add paths to `@INC` by modifying the `perl.inc` setting. You can use the `$ROOT_PATH` mnemonic to stand in for your project's root directory, for example `$ROOT_PATH/lib`. If you are using multiple workspace folders and use `$ROOT_PATH`, the path will be multiplied by the number of workspace folders, and will be replaced that many times.
* Configure the path to your `.perltidyrc` file using the `perl.perltidyrc` setting. The default is `~/.perltidyrc` if not configured.
* Configure the path to your `.perlcriticrc` file using the `perl.perlcritic.perlcriticrc` setting. The default is `~/.perlcriticrc` if not configured.
* Disable `perlcritic` checking entirely by setting `perl.perlcritic.enabled` to
`false`.
* Optionally, configure the path to an alternate `perl` to use for syntax checking using the `perl.syntax.perl` setting. By default, the `perl` used to run PLS will be used.
*  Disable syntax checking entirely by setting `perl.syntax.enabled` to `false`.
* Create a `.plsignore` file in your workspace root with Perl glob patterns that you do not wish to index. By default, PLS will index all files ending with `.pl`, `.pm`, or have `perl` in the shebang line that are not `.t` files.
  * If you have a lot of files that are not Perl files in your workspace, it may slow down indexing if they are not ignored. This is the case for PLS itself, where the entire `client` directory is not Perl and contains many small files in `node_modules`.
