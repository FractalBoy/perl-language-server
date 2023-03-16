import * as cp from "child_process";
import * as crypto from "crypto";
import * as fs from "fs";
import { IncomingMessage } from "http";
import * as https from "https";
import * as os from "os";
import * as path from "path";
import { promisify } from "util";
import * as vscode from "vscode";

const fsExists = promisify(fs.exists);
const fsAccess = promisify(fs.access);
const fsRealpath = promisify(fs.realpath);
const readFile = promisify(fs.readFile);
const execFile = promisify(cp.execFile);

export class Context {
  public readonly perl: string;
  public readonly localLib: vscode.Uri;
  private readonly plsOverride?: string;

  constructor(
    context: vscode.ExtensionContext,
    perl: string,
    perlIdentifier: string,
    plsOverride?: string
  ) {
    this.localLib = vscode.Uri.joinPath(
      context.globalStorageUri,
      perlIdentifier
    );

    this.perl = perl;
    this.plsOverride = plsOverride;
  }

  get libPath() {
    return vscode.Uri.joinPath(this.localLib, "lib", "perl5");
  }

  get cpanmBuildPath() {
    return vscode.Uri.joinPath(this.localLib, ".cpanm");
  }

  get pls() {
    if (this.plsOverride) {
      return this.plsOverride;
    }

    return vscode.Uri.joinPath(this.localLib, "bin", "pls").fsPath;
  }

  get environment(): NodeJS.ProcessEnv {
    return {
      PERL5LIB:
        this.libPath.fsPath +
        (process.env.PERL5LIB ? `:${process.env.PERL5LIB}` : ""),
      PERL_CPANM_HOME: this.cpanmBuildPath.fsPath,
      PATH: `${vscode.Uri.joinPath(this.localLib, "bin").fsPath}:${
        process.env.PATH
      }`,
    };
  }

  async createDirectories() {
    return Promise.all([
      vscode.workspace.fs.createDirectory(this.localLib),
      vscode.workspace.fs.createDirectory(this.cpanmBuildPath),
    ]);
  }
}

export async function bootstrap(
  context: vscode.ExtensionContext,
  pls: string | undefined
): Promise<Context> {
  if (os.platform() === "win32") {
    throw new Error("Platform not supported");
  }

  let perlPath;

  if (pls && path.isAbsolute(pls)) {
    const file = await readFile(pls);

    for (const line of file.toString().split("\n")) {
      const match = /^\s*#!(.+)$/.exec(line);
      if (match) {
        perlPath = match[1];
        break;
      }
    }
  }

  if (!perlPath) {
    perlPath = await getPerlPathFromUser(context);

    if (perlPath === "") {
      return new Context(context, "", "");
    }
  }

  const ctx = new Context(
    context,
    perlPath,
    await uniquePerlIdentifier(perlPath),
    pls
  );

  await installCpanm(ctx);
  await ctx.createDirectories();
  await runCpanmWithRetry(ctx, "PLS");
  await runCpanmWithRetry(ctx, "Cpanel::JSON::XS", false);

  return ctx;
}

async function installCpanm(ctx: Context): Promise<void> {
  return new Promise(async (resolve, reject) => {
    const res = await httpsGet("https://cpanmin.us");

    const proc = cp.spawn(
      ctx.perl,
      ["-", "-l", ctx.localLib.fsPath, "App::cpanminus"],
      {
        env: {
          ...process.env,
          PERL_CPANM_HOME: ctx.environment.PERL_CPANM_HOME,
        },
      }
    );

    proc.on("error", (error) => reject(`cpanm exited with an error: ${error}`));
    proc.stdin.on("error", (error) =>
      reject(`cpanm stdin closed with an error: ${error}`)
    );

    res.on("data", (chunk) => proc.stdin.write(chunk));
    res.on("end", () => proc.stdin.end());

    proc.on("exit", (code, signal) => {
      if (code === 0) {
        resolve();
      } else {
        if (signal) {
          reject(`cpanm exited with code ${code}`);
        } else {
          reject(`cpanm was killed with signal ${signal}`);
        }
      }
    });
  });
}

async function shouldRetry(
  module: string,
  notRequired: boolean = false
): Promise<boolean> {
  const response = await vscode.window.showErrorMessage(
    `Installation of ${module} failed. Review the output for details. ${
      notRequired
        ? "Successful installation is not required for full functionality. "
        : ""
    }Retry?`,
    "Yes",
    "No"
  );
  return response === "Yes";
}

async function CpanelJSONXSInstalled(ctx: Context): Promise<boolean> {
  try {
    await execFile(ctx.perl, ["-MCpanel::JSON::XS", "-e", "1"], {
      env: { ...process.env, ...ctx.environment },
    });
    return true;
  } catch {
    return false;
  }
}

async function getPerlPathFromUser(
  context: vscode.ExtensionContext
): Promise<string> {
  const items = await findAllPerlPaths();
  items.unshift(
    {
      label: "$(add) Choose a Perl installation not on this list",
    },
    {
      label: "I am using a container",
    }
  );

  const result = await vscode.window.showQuickPick(items, {
    placeHolder: "Choose a Perl installation",
  });

  if (result === items[0]) {
    const customPath = await vscode.window.showInputBox({
      placeHolder: "Enter a custom path to a perl binary",
      ignoreFocusOut: true,
      validateInput: async (value) => {
        if (!(await fsExists(value))) {
          return "Path does not exist";
        }

        try {
          await fsAccess(value, fs.constants.X_OK);
        } catch {
          return "Path is not executable";
        }
      },
    });

    if (customPath) {
      return customPath;
    }

    throw new Error("You must select a Perl installation to use");
  }

  if (result == items[1]) {
    // Using docker, we can't/shouldn't help here.
    // They should have built their docker image with the PLS installation
    return "";
  }

  if (!result?.detail) {
    throw new Error("You must select a Perl installation to use.");
  }

  return result.detail;
}

/**
 * Create a unique identifier for an installation of perl.
 * @param perl Path to perl binary
 * @returns String that is unique for every installation of perl on the system.
 */
export async function uniquePerlIdentifier(perl: string): Promise<string> {
  const result = await execFile(perl, [
    "-MConfig",
    "-e",
    'foreach my $key (keys %Config::Config) { print "$key=$Config::Config{$key}\\n" }',
  ]);

  if (result.stderr || !result.stdout) {
    throw new Error("unable to execute perl");
  }

  return crypto.createHash("sha256").update(result.stdout).digest("hex");
}

async function runCpanmWithRetry(
  context: Context,
  module: string,
  notRequired: boolean = false
) {
  while (true) {
    try {
      return await runCpanm(context, module);
    } catch (e) {
      if (!(await shouldRetry(module, notRequired))) {
        throw e;
      }
    }
  }
}

async function runCpanm(context: Context, module: string): Promise<string> {
  return vscode.window.withProgress(
    {
      location: vscode.ProgressLocation.Notification,
      cancellable: true,
      title: `Installing ${module}`,
    },
    (progress, token) => {
      return new Promise((resolve, reject) => {
        progress.report({ increment: 0 });
        const proc = cp.spawn(
          "cpanm",
          ["-", "-l", context.localLib.fsPath, module],
          {
            env: {
              ...process.env,
              ...context.environment,
            },
          }
        );

        proc.on("error", (error) =>
          reject(`cpanm exited with an error: ${error}`)
        );
        proc.stdin.on("error", (error) =>
          reject(`cpanm stdin closed with an error: ${error}`)
        );

        token.onCancellationRequested(() => {
          proc.kill();
        });

        let total: number = 1;
        let finished: number = 0;

        const outputChannel = vscode.window.createOutputChannel(
          `Installing ${module}`
        );

        proc.stdout.on("data", (chunk) => {
          const data = chunk.toString();

          let match = /Found dependencies: (.+)$/m.exec(data);

          if (match) {
            total += match[1].split(", ").length;
            return;
          }

          match = /^(Successfully installed.*)$/m.exec(data);

          if (match) {
            finished++;
            progress.report({
              message: match[1],
              increment: Math.floor((finished * 100) / total),
            });
          }
        });

        proc.stderr.on("data", (error) => {
          outputChannel.append(error.toString());
        });

        proc.on("exit", (code, signal) => {
          if (code === 0) {
            progress.report({
              increment: 100,
              message: `Successfully installed ${module}`,
            });
            resolve(`Completed installation of ${module}`);
          } else {
            outputChannel.show();
            if (code) {
              reject(`Installation of ${module} exited with code ${code}`);
            } else {
              reject(
                `Installation of ${module} was killed with signal ${signal}`
              );
            }
          }
        });
      });
    }
  );
}

export async function findAllPerlPaths(): Promise<vscode.QuickPickItem[]> {
  const items = [];

  if (
    (await fsExists("/usr/bin/perl")) &&
    (await fsRealpath("/usr/bin/perl")) === "/usr/bin/perl"
  ) {
    items.push({ label: "System", detail: "/usr/bin/perl" });
  }

  if (
    (await fsExists("/bin/perl")) &&
    (await fsRealpath("/bin/perl")) === "/bin/perl"
  ) {
    items.push({ label: "System", detail: "/bin/perl" });
  }

  if (
    (await fsExists("/usr/local/bin/perl")) &&
    (await fsRealpath("/usr/local/bin/perl")) == "/usr/local/bin/perl"
  ) {
    items.push({ label: "System", detail: "/usr/local/bin/perl" });
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

  return items;
}

async function httpsGet(url: string): Promise<IncomingMessage> {
  return new Promise<IncomingMessage>((resolve) => {
    https.get(url, (res) => resolve(res));
  });
}

async function getAllPerlBrewItems(): Promise<
  vscode.QuickPickItem[] | undefined
> {
  const result = await execFile("perlbrew", ["list"]);

  const items: vscode.QuickPickItem[] = [];

  const versions = result.stdout
    .split("\n")
    .map((s) => s.replace(/^\*?\s*(\S+).*/, "$1"))
    .filter((s) => s.length > 0);

  for (const version of versions) {
    items.push({
      label: version,
      detail: await getPerlBrewVersionPath(version),
    });
  }

  return items;
}

async function getPerlBrewVersionPath(
  version: string
): Promise<string | undefined> {
  return (
    await execFile("perlbrew", [
      "exec",
      "--with",
      version,
      "perl",
      "-e",
      "print $^X",
    ])
  ).stdout;
}

async function getAllPlenvItems(): Promise<vscode.QuickPickItem[]> {
  const result = await execFile("plenv", ["versions"]);

  const versions = result.stdout
    .split("\n")
    .map((s) => s.replace(/^(?:\*?\s*)(\S+).*/, "$1"))
    .filter((s) => s.length > 0);

  const items: vscode.QuickPickItem[] = [];

  for (const version of versions) {
    items.push({
      label: version,
      detail: await getPlenvVersionPath(version),
    });
  }

  return items;
}

async function getPlenvVersionPath(version: string): Promise<string> {
  return (await execFile("plenv", ["exec", "perl", "-e", "print $^X"])).stdout;
}
