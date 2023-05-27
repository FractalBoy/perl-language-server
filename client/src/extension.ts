// The module 'vscode' contains the VS Code extensibility API
// Import the module and reference it with the alias vscode in your code below
import * as vscode from 'vscode';

import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
} from 'vscode-languageclient/node';
import { PerlDebugSession } from './perlDebugSession';

let client: LanguageClient;

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

  context.subscriptions.push(
    vscode.debug.registerDebugConfigurationProvider(
      'perl',
      {
        provideDebugConfigurations() {
          return [
            {
              type: 'perl',
              request: 'launch',
              name: 'Start debugger',
              perl: 'perl',
              program: '${file}',
              cwd: '${workspaceFolder}',
            },
            {
              type: 'perl',
              request: 'attach',
              name: 'Start debugger for manual attach',
              port: 4026,
            },
          ];
        },
      },
      vscode.DebugConfigurationProviderTriggerKind.Dynamic
    )
  );

  const factory = new DebugAdapterFactory();
  context.subscriptions.push(
    vscode.debug.registerDebugAdapterDescriptorFactory('perl', factory)
  );

  client = new LanguageClient(
    'pls',
    'Perl Language Server (PLS)',
    serverOptions,
    clientOptions
  );

  client.start();
}

export function deactivate(): Thenable<void> | undefined {
  if (!client) {
    return;
  }
  return client.stop();
}

class DebugAdapterFactory implements vscode.DebugAdapterDescriptorFactory {
  createDebugAdapterDescriptor(
    session: vscode.DebugSession,
    executable: vscode.DebugAdapterExecutable | undefined
  ): vscode.ProviderResult<vscode.DebugAdapterDescriptor> {
    return new vscode.DebugAdapterInlineImplementation(new PerlDebugSession());
  }
}
