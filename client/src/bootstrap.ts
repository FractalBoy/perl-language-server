import * as os from "os";
import * as path from "path";
import * as fs from "fs";
import * as cp from "child_process";
import { promisify } from "util";
import * as https from "https";
import * as crypto from "crypto";

import * as vscode from "vscode";

const fsExists = promisify(fs.exists);
const fsAccess = promisify(fs.access);
const fsRealpath = promisify(fs.realpath);
const readFile = promisify(fs.readFile);
const readdir = promisify(fs.readdir);
const execFile = promisify(cp.execFile);

export class Context {
  public readonly perl: string;
  public readonly localLib: vscode.Uri;

  constructor(
    context: vscode.ExtensionContext,
    perl: string,
    perlIdentifier: string
  ) {
    this.localLib = vscode.Uri.joinPath(
      context.globalStorageUri,
      perlIdentifier
    );

    this.perl = perl;
  }

  get libPath() {
    return vscode.Uri.joinPath(this.localLib, "lib", "perl5");
  }

  get cpanmBuildPath() {
    return vscode.Uri.joinPath(this.localLib, ".cpanm");
  }

  get pls() {
    return vscode.Uri.joinPath(this.localLib, "bin", "pls").fsPath;
  }

  get environment(): NodeJS.ProcessEnv {
    return {
      PERL5LIB:
        this.libPath.fsPath +
        (process.env.PERL5LIB ? `:${process.env.PERL5LIB}` : ""),
      PERL_CPANM_HOME: this.cpanmBuildPath.fsPath,
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
  pls: string
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
    await uniquePerlIdentifier(perlPath)
  );

  let plsInstalled;

  try {
    // Get the PLS version, if it doesn't throw an exception then PLS is already installed.
    await getPLSVersion(ctx);
    plsInstalled = true;
  } catch {
    plsInstalled = false;
  }

  if (plsInstalled) {
    if (await shouldUpgrade(ctx)) {
      await installOrUpgrade(ctx);
    } else {
      await installCpanelJSONXS(ctx);
    }
  } else {
    await installOrUpgrade(ctx);
  }

  return ctx;
}

async function installOrUpgrade(ctx: Context): Promise<void> {
  await ctx.createDirectories();
  await installPLS(ctx, true);
  await installCpanelJSONXS(ctx, true);
}

async function shouldRetry(
  packageNames: string[],
  notRequired: boolean = false
): Promise<boolean> {
  const response = await vscode.window.showErrorMessage(
    `Installation of ${packageNames.join(
      ", "
    )} failed. Review the output for details. ${
      notRequired
        ? "Successful installation is not required for full functionality. "
        : ""
    }Retry?`,
    "Yes",
    "No"
  );
  return response === "Yes";
}

async function shouldUpgrade(ctx: Context): Promise<boolean> {
  const plsVersion = await getPLSVersion(ctx);
  const newestPLSVersion = await getNewestPLSVersion();

  // Not possible to be newer, but just in case.
  if (plsVersion >= newestPLSVersion) {
    return false;
  }

  const response = await vscode.window.showInformationMessage(
    "There is a new version of PLS available. Would you like to upgrade?",
    "Yes",
    "No"
  );

  return response === "Yes";
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
  packageNames: string[],
  notRequired: boolean = false
) {
  while (true) {
    try {
      return await runCpanm(context, packageNames);
    } catch (e) {
      if (!(await shouldRetry(packageNames, notRequired))) {
        throw e;
      }
    }
  }
}

async function runCpanm(
  context: Context,
  packageNames: string[]
): Promise<string> {
  return vscode.window.withProgress(
    {
      location: vscode.ProgressLocation.Notification,
      cancellable: true,
      title: `Installing ${packageNames.join(", ")}`,
    },
    (progress, token) => {
      return new Promise((resolve, reject) => {
        https.get("https://cpanmin.us", (res) => {
          progress.report({ increment: 0 });
          const proc = cp.spawn(
            context.perl,
            ["-", "-l", context.localLib.fsPath, ...packageNames],
            {
              env: {
                ...process.env,
                PERL_CPANM_HOME: context.environment.PERL_CPANM_HOME,
              },
            }
          );

          proc.on("error", (error) =>
            reject(`cpanm exited with an error: ${error}`)
          );
          proc.stdin.on("error", (error) =>
            reject(`cpanm stdin closed with an error: ${error}`)
          );

          res.on("data", (chunk) => proc.stdin.write(chunk));
          res.on("end", () => proc.stdin.end());

          token.onCancellationRequested(() => {
            proc.kill();
          });

          let total: number = 1;
          let finished: number = 0;

          const outputChannel = vscode.window.createOutputChannel(
            `Installing ${packageNames.join(", ")}`
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
                message: `Successfully installed ${packageNames.join(", ")}`,
              });
              resolve(`Completed installation of ${packageNames.join(", ")}`);
            } else {
              outputChannel.show();
              if (code) {
                reject(
                  `Installation of ${packageNames.join(
                    ", "
                  )} exited with code ${code}`
                );
              } else {
                reject(
                  `Installation of ${packageNames.join(
                    ", "
                  )} was killed with signal ${signal}`
                );
              }
            }
          });
        });
      });
    }
  );
}

export async function installPLS(
  context: Context,
  retry: boolean = false
): Promise<string> {
  if (retry) {
    return await runCpanmWithRetry(context, ["PLS"]);
  } else {
    return await runCpanm(context, ["PLS"]);
  }
}

export async function installCpanelJSONXS(
  context: Context,
  retry: boolean = false
): Promise<string> {
  if (retry) {
    return await runCpanmWithRetry(context, ["Cpanel::JSON::XS"], true);
  } else {
    return await runCpanm(context, ["Cpanel::JSON::XS"]);
  }
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

async function getPLSVersion(ctx: Context): Promise<number> {
  const result = await execFile(
    ctx.perl,
    ["-MPLS", "-e", "print $PLS::VERSION"],
    { env: { ...process.env, ...ctx.environment } }
  );

  if (result.stderr || !result.stdout) {
    throw new Error("PLS not installed");
  }

  // PLS doesn't currently use semantic versioning, just a float. In the future this could change.
  return Number.parseFloat(result.stdout);
}

async function getNewestPLSVersion(): Promise<number> {
  const code = await httpsGet(
    "https://raw.githubusercontent.com/FractalBoy/perl-language-server/master/server/lib/PLS.pm"
  );

  const lines = code.split("\n");

  for (const line of lines) {
    const match = /^our \$VERSION\s*=\s*['"]?(.+)['"]?;$/.exec(line);
    if (match) {
      return Number.parseFloat(match[1]);
    }
  }

  throw new Error("Could not determine current PLS version");
}

async function httpsGet(url: string): Promise<string> {
  return new Promise<string>((resolve, reject) => {
    https.get(url, (res) => {
      let data = "";
      res
        .on("data", (buff: Buffer) => (data += buff.toString()))
        .on("error", (e) => reject(e))
        .on("close", () => resolve(data));
    });
  });
}

async function getAllPerlBrewItems(): Promise<
  vscode.QuickPickItem[] | undefined
> {
  const perlbrewRoot = process.env.PERLBREW_ROOT
    ? process.env.PERLBREW_ROOT
    : path.join(os.homedir(), "perl5", "perlbrew");
  const perlbrew = path.join(perlbrewRoot, "bin", "perlbrew");
  if (!(await fsExists(perlbrew))) {
    return undefined;
  }

  const result = await execFile(perlbrew, ["list"]);
  const items: vscode.QuickPickItem[] = [];

  if (result.stderr || !result.stdout) {
    return undefined;
  }
  const lines = result.stdout.split("\n");

  for (const line of lines) {
    const item = {
      label: line.trim(),
      detail: "",
    };

    if (!item.label) {
      continue;
    }

    if (item.label.charAt(0) === "*") {
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
    "exec",
    "--with",
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
  const versionsDir = path.join(os.homedir(), ".plenv", "versions");
  const items: vscode.QuickPickItem[] = [];

  try {
    const dirs = await readdir(versionsDir);

    for (const dir of dirs) {
      const perl = path.join(versionsDir, dir, "bin", "perl");

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
