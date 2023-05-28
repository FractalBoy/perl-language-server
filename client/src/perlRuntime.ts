import { EventEmitter } from 'stream';
import * as net from 'net';
import { StackFrame, Thread } from '@vscode/debugadapter';

interface PerlBreakpoint {
  path: string;
  line: number;
}

interface PerlFunctionBreakpoint extends PerlBreakpoint {
  name: string;
}

interface Command {
  command: string;
  sym: symbol;
  nextCommand?: Command;
}

export class PerlRuntime extends EventEmitter {
  private socket: net.Socket;
  private breakpoints: PerlBreakpoint[];
  private functionBreakpoints: PerlFunctionBreakpoint[];
  private runningCommand?: Command;

  constructor(socket: net.Socket) {
    super();

    this.socket = socket;
    this.breakpoints = [];
    this.functionBreakpoints = [];

    let buffer = '';
    const regex =
      /^.*?(?:\[pid=(?:\d+->)+\d+\]\s*)?(?:\[\d+\]\s*)?DB<?<\d+>>? (?<result>.*?)(?=\n? {0,2}(?:\[pid=(?:\d+->)+\d+\]\s*)?(?:\[(?<thread>\d+)\]\s*)?DB<?<\d+>>?)/s;

    this.socket.on('data', (data) => {
      buffer += data.toString();

      const match = buffer.match(regex);

      if (match !== null && match?.groups) {
        if (match.groups['thread'] !== undefined) {
          this.emit('thread', Number(match.groups['thread']));
        }

        this.emit(this.runningCommand?.sym!, match.groups['result']);
        buffer = buffer.replace(regex, '');

        if (this.runningCommand?.nextCommand) {
          this.runningCommand = this.runningCommand.nextCommand;
          this.socket.write(this.runningCommand.command);
        } else {
          this.runningCommand = undefined;
        }
      }
    });
  }

  async setStartupOptions(): Promise<void> {
    await Promise.all([
      // Allow the program to exit normally.
      this.runCommand('o inhibit_exit=0'),
      // Need to disable saving to the history file if it is in the .perldb.
      // There is no way to use the 'o' command to undef an option.
      this.runCommand('undef ${$DB::optionVars{HistFile}}'),
    ]);
  }

  async getSource(path: string): Promise<string> {
    return await Promise.all([
      this.runCommand(`f ${path}`),
      // Only grab starting at index 1.
      // Only the file being debugged will have BEGIN { require 'perl5db.pl' } at index 0.
      this.runCommand("p join '', @DB::dbline[1 .. $#DB::dbline]"),
      this.runCommand('.'),
    ]).then(([_file, source, _curr]) => source);
  }

  async getThreads(): Promise<Thread[]> {
    return (
      await this.runCommand(
        'p join "\n", threads->tid, map { $_->tid } threads->list'
      )
    )
      .split('\n')
      .map((t) => ({ id: Number(t), name: `Thread ${t}` }));
  }

  terminate() {
    this.socket.destroy();
  }

  async continue(): Promise<string> {
    return await this.runCommand('c');
  }

  async next(): Promise<string> {
    return await this.runCommand('n');
  }

  async stepInto(): Promise<string> {
    return await this.runCommand('s');
  }

  async stepOut(): Promise<string> {
    return await this.runCommand('r');
  }

  async setBreakpoint(
    path: string,
    line: number,
    condition: string | undefined
  ): Promise<boolean> {
    if (path.endsWith('.pm')) {
      const requireResult = await this.runCommand(`require '${path}'`);

      if (/Can't locate/.test(requireResult)) {
        return false;
      }
    }

    let command = `b ${path}:${line}`;

    if (condition !== undefined) {
      command += ` ${condition}`;
    }

    const breakResult = await this.runCommand(command);

    if (/not breakable/.test(breakResult)) {
      return false;
    }

    this.breakpoints.push({
      line,
      path,
    });
    return true;
  }

  async setFunctionBreakpoint(
    name: string,
    condition: string | undefined
  ): Promise<{ path: string; name: string; line: number } | undefined> {
    const parts = name.split('::');

    if (parts.length > 1) {
      const pack = parts.slice(0, -1).join('::');
      const requireResult = await this.runCommand(`require ${pack}`);

      if (/Can't locate/.test(requireResult)) {
        return;
      }
    }

    let command = `b ${name}`;
    if (condition !== undefined) {
      command += ` ${condition}`;
    }

    const breakResult = await this.runCommand(command);

    if (/not found/.test(breakResult)) {
      return;
    }

    command =
      `if (!$INC{'B.pm'}) { require B; $requiredB = 1; } ` +
      `$cv = B::svref_2object(\\&${name}); ` +
      `print {$DB::OUT} q[{"file":"].$cv->FILE.q[","line":].$cv->START->line.q[}]; ` +
      `undef $cv; if ($requiredB) { delete $INC{'B.pm'}; undef %B::; undef $requiredB }`;

    const result = await this.runCommand(command);
    const fileAndLine: { file: string; line: number } = JSON.parse(result);
    const breakpoint = { path: fileAndLine.file, name, line: fileAndLine.line };

    this.functionBreakpoints.push(breakpoint);

    return breakpoint;
  }

  async clearAllBreakpoints(): Promise<void> {
    for (const breakpoint of this.breakpoints) {
      await this.clearBreakpoint(breakpoint);
    }

    this.breakpoints = [];
  }

  async clearAllFunctionBreakpoints(): Promise<void> {
    for (const breakpoint of this.functionBreakpoints) {
      await this.clearBreakpoint(breakpoint);
    }

    this.functionBreakpoints = [];
  }

  async clearBreakpoint(breakpoint: PerlBreakpoint): Promise<void> {
    await Promise.all([
      this.runCommand(`f ${breakpoint.path}`),
      this.runCommand(`B ${breakpoint.line}`),
      this.runCommand('.'),
    ]);
  }

  getBreakpointLocations(
    path: string,
    startLine: number,
    endLine?: number
  ): Promise<PerlBreakpoint[]> {
    return Promise.all([
      this.runCommand(`f ${path}`),
      endLine
        ? this.runCommand(
            `p join "\n", grep { $DB::dbline[$_] != 0 } (${startLine}..${endLine})`
          )
        : this.runCommand(
            `p $DB::dbline[${startLine}] == 0 ? '': ${startLine}`
          ),
    ]).then(([_, lines]) => {
      return lines
        .split('\n')
        .filter((line) => line.length)
        .map((line) => ({ path, line: Number(line) }));
    });
  }

  async getStackTrace(): Promise<StackFrame[]> {
    const trace = [];
    const stack = await this.runCommand('T');

    for (const [index, line] of stack.split('\n').entries()) {
      let match;
      if (
        (match = line.match(
          /^\s*[\.$@] = (?<sub>\S+) called from file '(?<file>.+?)' line (?<line>\d+)\s*$/
        )) === null
      ) {
        continue;
      }

      trace.push(
        new StackFrame(
          index,
          match.groups?.sub!,
          {
            path: match.groups?.file!,
            name: match.groups?.file!,
            sourceReference: 0,
          },
          Number(match.groups?.line!)
        )
      );
    }

    return trace;
  }

  public addCommand(command: string): symbol {
    const newCommand = {
      sym: Symbol(command),
      command,
    };

    if (this.runningCommand) {
      let lastCommand = this.runningCommand;

      while (lastCommand.nextCommand) {
        lastCommand = lastCommand.nextCommand;
      }

      lastCommand.nextCommand = newCommand;
    } else {
      this.runningCommand = newCommand;
      this.socket.write(command);
    }

    return newCommand.sym;
  }

  public runCommand(command: string): Promise<string> {
    return new Promise((resolve) => {
      const sym = this.addCommand(command + '\n');
      this.once(sym, resolve);
    });
  }

  public async evaluateVariable(variable: string): Promise<string> {
    variable = variable.replace(/^"|"$/g, '');
    // Assume hash if no sigil, as that is the most important sigil
    // that is not passed by the client.
    if (
      !variable.startsWith('$') &&
      !variable.startsWith('@') &&
      !variable.startsWith('%') &&
      !variable.startsWith('&') &&
      !variable.startsWith('*') &&
      !variable.startsWith('\\')
    ) {
      variable = `%${variable}`;
    }

    if (variable.startsWith('$')) {
      const ref = await this.runCommand(`p ref ${variable}`);

      if (ref.trim().length) {
        return await this.runCommand(`x ${variable}`);
      } else {
        return await this.runCommand(`p ${variable}`);
      }
    }

    if (
      variable.startsWith('@') ||
      variable.startsWith('%') ||
      variable.startsWith('&') ||
      variable.startsWith('*')
    ) {
      variable = `\\${variable}`;
    }

    return await this.runCommand(`x ${variable}`);
  }
}
