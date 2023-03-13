import * as os from 'os';
import * as path from 'path';
import * as fs from 'fs';
import * as cp from 'child_process';
import * as process from 'process';
import { promisify } from 'util';

const fsExists = promisify(fs.exists);
const readdir = promisify(fs.readdir);
const readlink = promisify(fs.readlink);
const execFile = promisify(cp.execFile);

import * as vscode from 'vscode';

import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
} from 'vscode-languageclient/node';

let client: LanguageClient;

export async function activate(context: vscode.ExtensionContext) {
  const perl = vscode.workspace.getConfiguration('perl');
  const pls = vscode.workspace.getConfiguration('pls');
  let serverCmd = pls.get<string>('cmd') ?? perl.get<string>('pls');
  const serverArgs =
    pls.get<string[]>('args') ?? perl.get<string[]>('plsargs') ?? [];

  if (!serverCmd) {
    let paths = await findAllPerlPaths();
    if (!paths) {
      paths = [{ label: '$(add) Enter Perl installation path...' }];
    }

    const pick = await vscode.window.showQuickPick(paths, {
      placeHolder: 'Select a path to the Perl installation to use for PLS',
    });

    if (pick?.detail) {
      serverCmd = path.resolve(pick.detail, '..', 'pls');
    }
  }

  if (!serverCmd) {
    await vscode.window.showErrorMessage(
      'Unable to start PLS server - no Perl installation configured'
    );
    return;
  }

  if (!(await fsExists(serverCmd))) {
    const usingSystemPerl = /^(?\/usr)?\/bin/.exec(serverCmd) !== null;

    if (usingSystemPerl) {
      await vscode.window.showErrorMessage(
        'The PLS server is not currently installed and you are using system Perl. You must manually install the PLS server.'
      );
      return;
    }

    const response = await vscode.window.showInformationMessage(
      'The PLS server is not currently installed in your selected Perl installation. Install?',
      'Install',
      'Cancel'
    );

    if (response !== 'Install') {
      await vscode.window.showErrorMessage(
        'You cannot use the Perl language server until the server is installed.'
      );
      return;
    }

    try {
      await installPLS(serverCmd);
    } catch {
      await vscode.window.showErrorMessage('Failed to install PLS.');
      return;
    }

    pls.update('cmd', serverCmd);
  }

  const serverOptions: ServerOptions = {
    run: { command: serverCmd, args: serverArgs },
    debug: { command: serverCmd, args: serverArgs },
  };

  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ scheme: 'file', language: 'perl' }],
  };

  client = new LanguageClient(
    'pls',
    'Perl Language Server (PLS)',
    serverOptions,
    clientOptions
  );

  await client.start();
}

export async function installPLS(serverCmd: string) {
  const cpanm = path.resolve(serverCmd, '..', 'cpanm');
  const cpan = path.resolve(serverCmd, '..', 'cpan');
  const perl = path.resolve(serverCmd, '..', 'perl');

  let proc: cp.ChildProcess;

  if (await fsExists(cpanm)) {
    proc = cp.spawn(cpanm, ['PLS'], {});
  } else if (await fsExists(cpan)) {
    proc = cp.spawn(cpan, ['PLS'], { env: { PERL_MM_USE_DEFAULT: '1' } });
  } else {
    proc = cp.spawn(perl, ['-MCPAN', '-e', 'install PLS'], {
      env: { PERL_MM_USE_DEFAULT: '1' },
    });
  }

  return vscode.window.withProgress(
    {
      location: vscode.ProgressLocation.Notification,
      cancellable: false,
      title: 'Installing PLS',
    },
    (progress, _) => {
      proc.stdout?.on('data', (buff: Buffer) => {
        progress.report({ message: buff.toString() });
      });

      return new Promise<undefined>(async (resolve, reject) => {
        proc.on('close', (code, signal) => {
          if (code === 0) {
            resolve(undefined);
          } else {
            reject();
          }
        });
      });
    }
  );
}

export async function findAllPerlPaths(): Promise<
  vscode.QuickPickItem[] | undefined
> {
  if (os.platform() === 'win32') {
    // TODO: PLS doesn't currently support Windows, so no need to implement this right now
    return undefined;
  }

  let systemPerl = { label: 'System', detail: '', picked: false };
  const items = [];

  if (await fsExists('/usr/bin/perl')) {
    systemPerl.detail = '/usr/bin/perl';
    items.push(systemPerl);
  } else if (await fsExists('/bin/perl')) {
    systemPerl.detail = '/bin/perl';
    items.push(systemPerl);
  }

  const perlbrew = await getAllPerlBrewItems();

  if (perlbrew) {
    items.unshift(...perlbrew);
    return items;
  }

  const plenv = await getAllPlenvItems();

  if (plenv) {
    items.unshift(...plenv);
    return items;
  }
}

async function getAllPerlBrewItems(): Promise<
  vscode.QuickPickItem[] | undefined
> {
  if (!process.env.PERLBREW_ROOT) {
    return undefined;
  }

  const perlbrew = path.join(process.env.PERLBREW_ROOT, 'bin', 'perlbrew');
  const result = await execFile(perlbrew, ['list']);
  const items: vscode.QuickPickItem[] = [];

  if (result.stderr || !result.stdout) {
    return undefined;
  }
  const lines = result.stdout.split('\n');

  for (const line of lines) {
    const item = {
      label: line.trim(),
      detail: '',
    };

    if (item.label.charAt(0) === '*') {
      item.label = item.label.substring(2);
    }

    const detail = await getPerlBrewVersionPath(perlbrew, item.label);

    if (!detail) {
      continue;
    }

    item.detail = detail;
    items.push(item);
  }

  return items;
}

async function getPerlBrewVersionPath(
  perlbrew: string,
  version: string
): Promise<string | undefined> {
  const perlPathResult = await execFile(perlbrew, [
    'exec',
    '--with',
    version,
    "perl -e 'print $^X'",
  ]);

  if (perlPathResult.stderr || !perlPathResult.stdout) {
    return undefined;
  }

  return perlPathResult.stdout;
}

async function getAllPlenvItems(): Promise<vscode.QuickPickItem[] | undefined> {
  if (!process.env.PLENV_SHELL) {
    return undefined;
  }

  // plenv has fewer environment variables than perlbrew
  // so we will just look at the versions directory
  const versionsDir = path.join(os.homedir(), '.plenv', 'versions');
  const items: vscode.QuickPickItem[] = [];

  try {
    const dirs = await readdir(versionsDir);

    for (const dir of dirs) {
      const perl = path.join(versionsDir, dir, 'bin', 'perl');

      if (!(await fsExists(perl))) {
        continue;
      }

      items.push({
        label: dir,
        detail: perl,
      });
    }

    return items;
  } catch {
    return undefined;
  }
}

export function deactivate() {
  if (!client) {
    return undefined;
  }

  client.stop();
}
