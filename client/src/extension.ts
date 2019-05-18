// The module 'vscode' contains the VS Code extensibility API
// Import the module and reference it with the alias vscode in your code below
import * as vscode from 'vscode';

import { LanguageClient, LanguageClientOptions, ServerOptions } from 'vscode-languageclient';

// this method is called when your extension is activated
// your extension is activated the very first time the command is executed
export function activate(context: vscode.ExtensionContext) {
	const serverCmd = "pls"

	const serverOptions: ServerOptions = {
		run: { command: serverCmd },
		debug: { command: serverCmd }
	};

	const clientOptions: LanguageClientOptions = {
		documentSelector: [{ scheme: 'file', language: 'perl' }]
	};

	const disposable = new LanguageClient('pls', 'Perl Language Server (PLS)', serverOptions, clientOptions).start();
}
