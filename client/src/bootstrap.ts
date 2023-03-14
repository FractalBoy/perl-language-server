import * as os from 'os';
import * as path from 'path';
import * as fs from 'fs';
import * as cp from 'child_process';
import { promisify } from 'util';
import * as https from 'https';
import * as crypto from 'crypto';
import * as stream from 'stream';

import * as vscode from 'vscode';

const fsExists = promisify(fs.exists);
const fsRealpath = promisify(fs.realpath);
const readdir = promisify(fs.readdir);
const execFile = promisify(cp.execFile);

export class Context {
    public environment: NodeJS.ProcessEnv;
    public perl: string;
    public localLib: vscode.Uri;
    public pls: string;

    constructor(context: vscode.ExtensionContext, perl: string, perlIdentifier: string) {
        this.localLib = vscode.Uri.joinPath(context.globalStorageUri, perlIdentifier);

        this.environment = {
            PERL5LIB: vscode.Uri.joinPath(this.localLib, 'lib', 'perl5').fsPath + (process.env.PERL5LIB ? `:${process.env.PERL5LIB}` : ''),
            PERL_MB_OPT: `--install_base "${this.localLib.fsPath}"`,
            PERL_MM_OPT: `INSTALL_BASE="${this.localLib.fsPath}"`,
            PERL_LOCAL_LIB_ROOT: this.localLib.fsPath
        }

        this.perl = perl;
        this.pls = vscode.Uri.joinPath(this.localLib, 'bin', 'pls').fsPath
    }

    async createDirectories() {
        await vscode.workspace.fs.createDirectory(this.localLib)
    }
}

export async function bootstrap(context: vscode.ExtensionContext): Promise<Context> {
    let perlPath = '/usr/bin/perl';
    const ctx = new Context(context, perlPath, await uniquePerlIdentifier(perlPath));

    return ctx;
}

export async function uniquePerlIdentifier(perl: string) {
    const result = await execFile(perl, ['-MConfig', '-e', 'foreach my $key (keys %Config::Config) { print "$key=$Config::Config{$key}\\n" }'])

    if (result.stderr || !result.stdout) {
        throw new Error("unable to execute perl");
    }

    return crypto.createHash('sha256').update(result.stdout).digest('hex');
}

export async function installPLS(context: Context) {
    return vscode.window.withProgress(
        {
            location: vscode.ProgressLocation.Notification,
            cancellable: true,
            title: 'Installing PLS',
        }, (progress, token) => {
            return new Promise((resolve, reject) => {
                https.get('https://cpanmin.us', res => {
                    progress.report({ increment: 0 });
                    const proc = cp.spawn(context.perl, ['-', '-l', context.localLib.fsPath, 'PLS']);
                    res.on('data', chunk => proc.stdin.write(chunk));
                    res.on('end', () => proc.stdin.end());

                    token.onCancellationRequested(() => {
                        proc.kill();
                    });

                    let totalInstalling: number = 1;
                    let finishedInstalling: number = 0;

                    proc.stdout.on('data', chunk => {
                        const data = chunk.toString();
                        let match = /Found dependencies: (.+)/.exec(data);

                        if (match) {
                            totalInstalling += match[1].split(', ').length;
                            return;
                        }

                        if (/Successfully installed/.exec(data)) {
                            finishedInstalling++;
                            progress.report({ message: data, increment: Math.floor(finishedInstalling * 100.0 / totalInstalling) })
                        }
                    });

                    let allErrors = '';

                    proc.stderr.on('data', error => {
                        allErrors += error.toString()
                    });

                    proc.on('exit', code => {
                        if (code === 0) {
                            progress.report({ increment: 100, message: 'Successfully installed PLS' });
                            resolve('Completed installation of PLS')
                        } else {
                            let errorMessage = `Installation exited with code ${code}`;
                            if (allErrors) {
                                errorMessage += `\n${allErrors}`;
                            }
                            reject(allErrors)
                        }
                    });
                });
            });
        });


}

export async function findAllPerlPaths(): Promise<
    vscode.QuickPickItem[] | undefined
> {
    if (os.platform() === 'win32') {
        // TODO: PLS doesn't currently support Windows, so no need to implement this right now
        return undefined;
    }

    const items = [];

    if (await fsExists('/usr/bin/perl') && await fsRealpath('/usr/bin/perl') === '/usr/bin/perl') {
        items.push({ label: 'System', detail: '/usr/bin/perl' });
    }

    if (await fsExists('/bin/perl') && await fsRealpath('/bin/perl') === '/bin/perl') {
        items.push({ label: 'System', detail: '/bin/perl' });
    }

    if (await fsExists('/usr/local/bin/perl') && await fsRealpath('/usr/local/bin/perl') == '/usr/local/bin/perl') {
        items.push({ label: 'System', detail: '/usr/local/bin/perl' })
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

async function getPLSVersion(perl: string): Promise<number> {
    const result = await execFile(perl, ["-MPLS", '-e', 'print $PLS::VERSION']);

    if (result.stderr || !result.stdout) {
        throw new Error("PLS not installed");
    }

    // PLS doesn't currently use semantic versioning, just a float. In the future this could change.
    return Number.parseFloat(result.stdout);
}

async function getNewestPLSVersion(): Promise<number> {
    return httpsGet('https://raw.githubusercontent.com/FractalBoy/perl-language-server/master/server/lib/PLS.pm').then(code => {
        const lines = code.split('\n');

        for (const line of lines) {
            const match = /^our \$VERSION\s*=\s*['"]?(.+)['"]?;$/.exec(line)
            if (match) {
                return Number.parseFloat(match[1])
            }
        }

        throw new Error('Could not determine current PLS version');
    });
}

async function httpsGet(url: string): Promise<string> {
    return new Promise<string>((resolve, reject) => {
        https.get(url, res => {
            let data = '';
            res.on('data', (buff: Buffer) => data += buff.toString()).on('error', e => reject(e)).on('close', () => resolve(data));
        });
    })
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
