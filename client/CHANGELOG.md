# Change Log

All notable changes to the "pls" extension will be documented in this file.

## [0.0.8] - 2021-06-29
- Added `syntax.perl` and `syntax.enabled` options

## [0.0.9] - 2021-07-01
- Added icon - thank you [@kraih](https://github.com/kraih)!

## [0.0.10] - 2021-07-29
- Added LICENSE file

## [0.0.11] - 2021-08-07
- Added new configuration item - perl.plsargs, which
  allows you to pass arguments to your pls command. This is useful
  for using with docker, ssh, or some other, more complex command.

## [0.0.12] - 2021-10-23
- This release contains NPM package security updates only.

## [0.0.13] - 2022-01-19
- Updated copyright

## [0.0.14] - 2022-03-01
- Updated README to include information about syntax related settings.

## [0.0.15] - 2022-08-29
- Added `perl.syntax.args` setting.
- Configuration was moved from the `perl.` to the `pls.` namespace.
  - Support for configuration in `pls.` has been deprecated, but not removed.
- Renamed the `perl.sortImports` command to `pls.sortImports` to match the new settings namespace.

## [0.0.16] - 2022-09-02
- Bumped vscode-languageclient version from 7.0.0 to 8.0.2.

## [0.0.17] - 2023-01-21
- Added `pls.podchecker.enabled` setting, to disable and re-enable podchecker.
