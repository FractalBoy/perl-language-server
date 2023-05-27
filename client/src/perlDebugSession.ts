import {
  DebugSession,
  ExitedEvent,
  InitializedEvent,
  StoppedEvent,
  TerminatedEvent,
  Thread,
  ThreadEvent,
} from '@vscode/debugadapter';
import { DebugProtocol } from '@vscode/debugprotocol';
import * as net from 'net';
import * as os from 'os';
import { PerlRuntime } from './perlRuntime';

export class PerlDebugSession extends DebugSession {
  private server?: net.Server;
  private runtimes: Map<number, PerlRuntime>;
  private mainPid?: number;

  constructor() {
    super();

    this.setDebuggerLinesStartAt1(true);
    this.setDebuggerColumnsStartAt1(true);

    this.runtimes = new Map();
  }

  protected override initializeRequest(
    response: DebugProtocol.InitializeResponse,
    args: DebugProtocol.InitializeRequestArguments
  ): void {
    if (response.body === undefined) {
      return;
    }

    response.body.supportsConfigurationDoneRequest = true;
    response.body.supportsConditionalBreakpoints = true;
    response.body.supportsFunctionBreakpoints = true;
    response.body.supportsSetVariable = true;
    response.body.supportsTerminateRequest = true;
    response.body.supportTerminateDebuggee = true;
    response.body.supportsEvaluateForHovers = true;
    response.body.supportsSingleThreadExecutionRequests = true;

    response.success = true;
    this.sendResponse(response);
  }

  protected override attachRequest(
    response: DebugProtocol.AttachResponse,
    args: DebugProtocol.AttachRequestArguments,
    request?: DebugProtocol.Request | undefined
  ): void {
    this.server = net
      .createServer(async (socket) => {
        const runtime = new PerlRuntime(socket);
        await runtime.setStartupOptions();
        const pid = await runtime.getPid();

        socket.on('close', () => {
          this.runtimes.delete(pid);

          if (pid === this.mainPid) {
            this.mainPid = this.runtimes.keys().next().value;
          }

          this.sendEvent(new ThreadEvent('exited', pid));
        });

        if (this.runtimes.size) {
          this.sendEvent(new ThreadEvent('started', pid));
        } else {
          this.mainPid = pid;
          this.sendEvent(new InitializedEvent());
        }

        this.runtimes.set(pid, runtime);
        this.sendEvent(new StoppedEvent('entry', pid));
      })
      .on('error', (e) => {
        response.message = e.message;
        response.success = false;
        this.sendResponse(response);
      });

    this.server.listen(request?.arguments.port || 4026, () => {
      response.success = true;
      this.sendResponse(response);
    });
  }

  protected override launchRequest(
    response: DebugProtocol.LaunchResponse,
    args: DebugProtocol.LaunchRequestArguments,
    request?: DebugProtocol.Request | undefined
  ): void {
    this.server = net
      .createServer(async (socket) => {
        const runtime = new PerlRuntime(socket);
        await runtime.setStartupOptions();
        const pid = await runtime.getPid();

        socket.on('close', (hadError) => {
          this.runtimes.delete(pid);
          this.sendEvent(new ThreadEvent('exited', pid));

          if (pid === this.mainPid) {
            this.mainPid = this.runtimes.keys().next().value;
          }

          if (!this.runtimes.size) {
            this.sendEvent(new TerminatedEvent());
            this.sendEvent(new ExitedEvent(hadError ? 1 : 0));
          }
        });

        if (this.runtimes.size) {
          this.sendEvent(new ThreadEvent('started', pid));
        } else {
          this.mainPid = pid;
          this.sendEvent(new InitializedEvent());
        }

        this.runtimes.set(pid, runtime);
        this.sendEvent(new StoppedEvent('entry', pid));
      })
      .on('error', (e) => {
        response.message = e.message;
        response.success = false;
        this.sendResponse(response);
      });

    this.server.listen(0, () => {
      const port = (this.server?.address()! as net.AddressInfo).port;
      response.success = true;
      this.sendResponse(response);

      const args = [];
      let env = {};
      let hostname = 'localhost';

      if (request?.arguments.hostname) {
        args.push('ssh', request?.arguments.hostname);

        if (request?.arguments.localHostname) {
          hostname = request?.arguments.localHostname;
        } else {
          // Determine how to connect back to this host
          const ifaces = os.networkInterfaces();
          for (const iface of Object.keys(ifaces)) {
            for (const net of ifaces[iface]!) {
              if (net.internal) {
                continue;
              }
              hostname = net.address;
              break;
            }
          }
        }

        let perlArgs = (request.arguments.perlArgs || []).join(' ');
        if (perlArgs) {
          perlArgs = ` ${perlArgs} `;
        }

        let programArgs = (request.arguments.args || []).join(' ');
        if (programArgs) {
          programArgs = ` ${programArgs}`;
        }

        const envParts = [`PERLDB_OPTS='RemotePort=${hostname}:${port}'`];

        for (const variable of Object.keys(request.arguments.env || {})) {
          envParts.push(`${variable}='${request.arguments.env}'`);
        }

        const env = envParts.join(' ');

        args.push(
          `${env} ${request.arguments.perl}${perlArgs} -d ${request.arguments.program}${programArgs}`
        );
      } else {
        args.push(
          request?.arguments.perl,
          ...(request?.arguments.perlArgs || []),
          '-d',
          request?.arguments.program,
          ...(request?.arguments.args || [])
        );
        env = {
          ...(request?.arguments.env || {}),
          // eslint-disable-next-line @typescript-eslint/naming-convention
          PERLDB_OPTS: `RemotePort=${hostname}:${port}`,
        };
      }

      this.runInTerminalRequest(
        {
          args,
          env,
          cwd: request?.arguments.cwd,
          kind: 'integrated',
        },
        30000,
        () => {}
      );
    });
  }

  protected override stackTraceRequest(
    response: DebugProtocol.StackTraceResponse,
    args: DebugProtocol.StackTraceArguments,
    request?: DebugProtocol.Request | undefined
  ): void {
    const runtime = this.runtimes.get(args.threadId);

    if (!runtime) {
      response.success = false;
      response.message = `Thread ${args.threadId} not found.`;
      return;
    }

    runtime.getStackTrace().then((trace) => {
      response.body = { stackFrames: trace };
      response.success = true;
      this.sendResponse(response);
    });
  }

  protected override threadsRequest(
    response: DebugProtocol.ThreadsResponse,
    request?: DebugProtocol.Request | undefined
  ): void {
    if (!this.runtimes.size) {
      this.sendResponse(response);
      return;
    }

    const promises: Promise<Thread>[] = [];

    for (const [pid, runtime] of this.runtimes) {
      promises.push(
        runtime.getName().then((name) => ({
          id: pid,
          name,
        }))
      );
    }

    Promise.all(promises).then((threads) => {
      response.body = { threads };
      this.sendResponse(response);
    });
  }

  private flowControlRequest(
    response:
      | DebugProtocol.ContinueResponse
      | DebugProtocol.NextResponse
      | DebugProtocol.StepInResponse
      | DebugProtocol.StepOutResponse,
    args:
      | DebugProtocol.ContinueArguments
      | DebugProtocol.NextArguments
      | DebugProtocol.StepInArguments
      | DebugProtocol.StepOutArguments,
    cb: (runtime: PerlRuntime) => Promise<any>,
    stoppedReason: 'breakpoint' | 'step'
  ) {
    const runtimes = [];

    if (args.singleThread) {
      if (this.runtimes.has(args.threadId)) {
        runtimes.push(this.runtimes.get(args.threadId)!);
      } else {
        response.success = false;
        response.message = `Thread ${args.threadId} not found.`;
        this.sendResponse(response);
        return;
      }
    } else {
      runtimes.push(...this.runtimes.values());
    }

    for (const runtime of runtimes) {
      cb(runtime).then(() => {
        this.sendEvent(new StoppedEvent(stoppedReason, args.threadId));
      });
    }

    response.success = true;
    this.sendResponse(response);
  }

  protected override continueRequest(
    response: DebugProtocol.ContinueResponse,
    args: DebugProtocol.ContinueArguments,
    request?: DebugProtocol.Request | undefined
  ): void {
    this.flowControlRequest(
      response,
      args,
      (runtime) => runtime.continue(),
      'breakpoint'
    );
  }

  protected override nextRequest(
    response: DebugProtocol.NextResponse,
    args: DebugProtocol.NextArguments,
    request?: DebugProtocol.Request | undefined
  ): void {
    this.flowControlRequest(
      response,
      args,
      (runtime) => runtime.next(),
      'step'
    );
  }

  protected override stepInRequest(
    response: DebugProtocol.NextResponse,
    args: DebugProtocol.NextArguments,
    request?: DebugProtocol.Request | undefined
  ): void {
    this.flowControlRequest(
      response,
      args,
      (runtime) => runtime.stepInto(),
      'step'
    );
  }

  protected override stepOutRequest(
    response: DebugProtocol.StepOutResponse,
    args: DebugProtocol.StepOutArguments,
    request?: DebugProtocol.Request | undefined
  ): void {
    this.flowControlRequest(
      response,
      args,
      (runtime) => runtime.stepOut(),
      'step'
    );
  }

  protected override sourceRequest(
    response: DebugProtocol.SourceResponse,
    args: DebugProtocol.SourceArguments,
    request?: DebugProtocol.Request | undefined
  ): void {
    if (!args.source?.path) {
      this.sendResponse(response);
      return;
    }

    const promises = [];

    for (const runtime of this.runtimes.values()) {
      promises.push(runtime.getSource(args.source?.path));
    }

    Promise.race(promises).then((content) => {
      response.success = true;
      response.body = { content };
      this.sendResponse(response);
    });
  }

  protected override setBreakPointsRequest(
    response: DebugProtocol.SetBreakpointsResponse,
    args: DebugProtocol.SetBreakpointsArguments,
    request?: DebugProtocol.Request | undefined
  ): void {
    this.setBreakpoints(response, args).then((resp) => this.sendResponse(resp));
  }

  protected override setFunctionBreakPointsRequest(
    response: DebugProtocol.SetFunctionBreakpointsResponse,
    args: DebugProtocol.SetFunctionBreakpointsArguments,
    request?: DebugProtocol.Request | undefined
  ): void {
    this.setFunctionBreakpoints(response, args).then((resp) =>
      this.sendResponse(resp)
    );
  }

  protected override disconnectRequest(
    response: DebugProtocol.DisconnectResponse,
    args: DebugProtocol.DisconnectArguments,
    request?: DebugProtocol.Request | undefined
  ): void {
    for (const runtime of this.runtimes.values()) {
      runtime.terminate();
    }

    this.server?.close(() => {
      response.success = true;
      this.sendResponse(response);
    });
  }

  protected override evaluateRequest(
    response: DebugProtocol.EvaluateResponse,
    args: DebugProtocol.EvaluateArguments,
    request?: DebugProtocol.Request | undefined
  ): void {
    const runtime = this.runtimes.get(this.mainPid!)!;
    let promise;

    if (args.context === 'repl') {
      promise = runtime.runCommand(args.expression);
    } else {
      promise = runtime.evaluateVariable(args.expression);
    }

    promise.then((result) => {
      response.success = true;
      response.body = {
        result,
        variablesReference: 0,
      };
      this.sendResponse(response);
    });
  }

  private async setBreakpoints(
    response: DebugProtocol.SetBreakpointsResponse,
    args: DebugProtocol.SetBreakpointsArguments
  ): Promise<DebugProtocol.SetBreakpointsResponse> {
    response.success = true;
    for (const runtime of this.runtimes.values()) {
      await runtime.clearAllBreakpoints();
    }

    if (
      args.source.path === undefined ||
      args.breakpoints === undefined ||
      args.breakpoints.length === 0
    ) {
      return response;
    }

    response.body = { breakpoints: [] };

    for (const breakpoint of args.breakpoints) {
      let breakpointSet = true;

      for (const runtime of this.runtimes.values()) {
        if (
          !(await runtime.setBreakpoint(
            args.source.path,
            breakpoint.line,
            breakpoint.condition
          ))
        ) {
          breakpointSet = false;
          break;
        }
      }

      response.body.breakpoints.push({
        verified: breakpointSet,
        line: breakpoint.line,
        source: args.source,
      });
    }

    return response;
  }

  private async setFunctionBreakpoints(
    response: DebugProtocol.SetFunctionBreakpointsResponse,
    args: DebugProtocol.SetFunctionBreakpointsArguments
  ): Promise<DebugProtocol.SetFunctionBreakpointsResponse> {
    response.success = true;
    for (const runtime of this.runtimes.values()) {
      await runtime.clearAllFunctionBreakpoints();
    }

    response.body = { breakpoints: [] };

    for (const breakpoint of args.breakpoints) {
      let location;

      for (const runtime of this.runtimes.values()) {
        location = await runtime.setFunctionBreakpoint(
          breakpoint.name,
          breakpoint.condition
        );
      }

      response.body.breakpoints.push({
        verified: location === undefined ? false : true,
        line: location?.line,
        source: {
          path: location?.path,
        },
      });
    }

    return response;
  }
}
