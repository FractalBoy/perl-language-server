import * as vscode from 'vscode';
import {
    LanguageClient,
    LanguageClientOptions,
    ServerOptions,
} from 'vscode-languageclient/node';
import { bootstrap } from './bootstrap';

let client: LanguageClient;

export async function activate(context: vscode.ExtensionContext) {
    const perl = vscode.workspace.getConfiguration('perl');
    const pls = vscode.workspace.getConfiguration('pls');
    let serverCmd = pls.get<string>('cmd') ?? perl.get<string>('pls') ?? 'pls';
    const serverArgs =
        pls.get<string[]>('args') ?? perl.get<string[]>('plsargs') ?? [];

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


export function deactivate() {
    if (!client) {
        return undefined;
    }

    client.stop();
}
