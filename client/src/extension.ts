// The module 'vscode' contains the VS Code extensibility API
// Import the module and reference it with the alias vscode in your code below
import * as vscode from 'vscode';

import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
} from 'vscode-languageclient/node';

// this method is called when your extension is activated
// your extension is activated the very first time the command is executed
export function activate(context: vscode.ExtensionContext) {
  const perl = vscode.workspace.getConfiguration('perl');
  const pls = vscode.workspace.getConfiguration('pls');
  const serverCmd = pls.get<string>('cmd') ?? perl.get<string>('pls') ?? 'pls';
  const serverArgs =
    pls.get<string[]>('args') ?? perl.get<string[]>('plsargs') ?? [];

  const serverOptions: ServerOptions = {
    run: { command: serverCmd, args: serverArgs },
    debug: { command: serverCmd, args: serverArgs },
  };

  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ scheme: 'file', language: 'perl' }],
  };

  const disposable = new LanguageClient(
    'pls',
    'Perl Language Server (PLS)',
    serverOptions,
    clientOptions
  ).start();
}
