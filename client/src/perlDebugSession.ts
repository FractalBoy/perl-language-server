import {
  DebugSession,
  ExitedEvent,
  InitializedEvent,
  StoppedEvent,
  TerminatedEvent,
} from '@vscode/debugadapter';
import { DebugProtocol } from '@vscode/debugprotocol';
import * as net from 'net';
import * as os from 'os';
import { PerlRuntime } from './perlRuntime';
import { Proxy } from './proxy';

export class PerlDebugSession extends DebugSession {
  private server?: net.Server;
  private runtime?: PerlRuntime;
  private pid?: number;
  private numRunning: number;

  constructor() {
    super();

    // _sequence not initialized by DebugSession when running as inline debugger.
    // It is a private property, but this lets us workaround the bug.
    this['_sequence'] = 1;

    this.setDebuggerLinesStartAt1(true);
    this.setDebuggerColumnsStartAt1(true);

    this.numRunning = 0;
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
    response.body.supportsBreakpointLocationsRequest = true;

    response.success = true;
    this.sendResponse(response);
  }

  protected override attachRequest(
    response: DebugProtocol.AttachResponse,
    args: DebugProtocol.AttachRequestArguments,
    request?: DebugProtocol.Request | undefined
  ): void {
    this.startDebugger(response, request, 'attach', () => {
      response.success = true;
      this.sendResponse(response);
    });
  }

  protected override launchRequest(
    response: DebugProtocol.LaunchResponse,
    args: DebugProtocol.LaunchRequestArguments,
    request?: DebugProtocol.Request | undefined
  ): void {
    this.startDebugger(response, request, 'launch', () =>
      this.startInTerminal(response, request)
    );
  }

  private startDebugger(
    response: DebugProtocol.LaunchResponse | DebugProtocol.AttachResponse,
    request: DebugProtocol.Request | undefined,
    type: 'launch' | 'attach',
    cb: () => void
  ) {
    if (request?.arguments.__proxy) {
      this.connectToProxy(response, request);
      return;
    }

    this.server = net
      .createServer(async (socket) => {
        this.numRunning++;

        if (this.runtime) {
          this.startProxy(socket, type);
        } else {
          this.startRuntime(socket);
        }
      })
      .on('error', (e) => {
        response.message = e.message;
        response.success = false;
        this.sendResponse(response);
      });

    this.server.listen(0, () => cb());
  }

  private startInTerminal(
    response: DebugProtocol.LaunchResponse,
    request?: DebugProtocol.Request | undefined
  ) {
    if (!this.server || !request) {
      return;
    }

    const port = (this.server.address() as net.AddressInfo).port;

    const args = [];
    let env = {};

    if (request.arguments.hostname) {
      args.push(
        'ssh',
        request.arguments.hostname,
        this.buildRemoteCommand(request, port)
      );
    } else {
      args.push(...this.buildLocalCommand(request));
      env = this.buildLocalEnv(request, port);
    }

    this.runInTerminalRequest(
      {
        args,
        env,
        cwd: request.arguments.cwd ? request.arguments.cwd : '',
        kind: 'integrated',
      },
      30000,
      (runInTerminalResponse) => {
        response.success = runInTerminalResponse.success;
        this.sendResponse(response);
      }
    );
  }

  private determineLocalHostname(request: DebugProtocol.Request): string {
    if (request.arguments.localHostname) {
      return request.arguments.localHostname;
    } else {
      // Determine how to connect back to this host
      const ifaces = os.networkInterfaces();
      for (const iface of Object.keys(ifaces)) {
        for (const net of ifaces[iface]!) {
          if (!net.internal) {
            return net.address;
          }
        }
      }
    }

    return 'localhost';
  }

  private buildRemoteCommand(
    request: DebugProtocol.Request,
    port: number
  ): string {
    const hostname = this.determineLocalHostname(request);

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
    return `${env} ${request.arguments.perl}${perlArgs} -d ${request.arguments.program}${programArgs}`;
  }

  private buildLocalCommand(request: DebugProtocol.Request): string[] {
    return [
      request.arguments.perl,
      ...(request.arguments.perlArgs || []),
      '-d',
      request.arguments.program,
      ...(request.arguments.args || []),
    ];
  }

  private buildLocalEnv(request: DebugProtocol.Request, port: number): any {
    return {
      ...(request?.arguments.env || {}),
      // eslint-disable-next-line @typescript-eslint/naming-convention
      PERLDB_OPTS: `RemotePort=localhost:${port}`,
    };
  }

  private startProxy(socket: net.Socket, type: 'launch' | 'attach') {
    const proxy = new Proxy(socket);

    proxy.listen().then((port) => {
      this.startDebuggingRequest(
        { configuration: { port, __proxy: true }, request: type },
        30000,
        () => {}
      );
    });

    // When this socket closes, check to see if all processes have exited
    // and send TerminatedEvent if so, which will end the debugging session.
    socket.on('close', () => {
      this.numRunning--;

      if (this.numRunning == 0) {
        this.sendEvent(new TerminatedEvent());
      }
    });
  }

  private startDebuggingRequest(
    args: any,
    timeout: number,
    cb: (response: DebugProtocol.Response) => void
  ) {
    this.sendRequest('startDebugging', args, timeout, cb);
  }

  private connectToProxy(
    response: DebugProtocol.LaunchResponse | DebugProtocol.AttachResponse,
    request: DebugProtocol.Request
  ) {
    const socket = net
      .createConnection({
        port: request?.arguments.port,
        host: 'localhost',
      })
      .on('connect', async () => {
        this.runtime = new PerlRuntime(socket);
        this.pid = await this.runtime.getPid();

        // This is a child process, and should not have any child processes of its own
        // as all child processes connect to the same port. Send the TerminatedEvent as
        // soon as the socket closes.
        socket.on('close', (hadError) => {
          this.sendEvent(new ExitedEvent(hadError ? 1 : 0));
          this.sendEvent(new TerminatedEvent());
        });

        response.success = true;
        this.sendResponse(response);
        this.sendEvent(new InitializedEvent());
        this.sendEvent(new StoppedEvent('entry', this.pid));
      });
  }

  private async startRuntime(socket: net.Socket) {
    this.runtime = new PerlRuntime(socket);

    await this.runtime.setStartupOptions();
    this.pid = await this.runtime.getPid();
    this.sendEvent(new InitializedEvent());
    this.sendEvent(new StoppedEvent('entry', this.pid));

    // When this socket closes send ExitedEvent, and TerminatedEvent
    // if no child processes are still running.
    socket.on('close', (hadError) => {
      this.numRunning--;
      this.sendEvent(new ExitedEvent(hadError ? 1 : 0));

      if (this.numRunning == 0) {
        this.sendEvent(new TerminatedEvent());
      }
    });
  }

  protected override stackTraceRequest(
    response: DebugProtocol.StackTraceResponse,
    args: DebugProtocol.StackTraceArguments,
    request?: DebugProtocol.Request | undefined
  ): void {
    this.runtime?.getStackTrace().then((trace) => {
      response.body = { stackFrames: trace };
      response.success = true;
      this.sendResponse(response);
    });
  }

  protected override threadsRequest(
    response: DebugProtocol.ThreadsResponse,
    request?: DebugProtocol.Request | undefined
  ): void {
    this.runtime?.getName().then((name) => {
      response.success = true;
      response.body = {
        threads: [
          {
            id: this.pid!,
            name,
          },
        ],
      };
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
    cb: () => Promise<any>,
    stoppedReason: 'breakpoint' | 'step'
  ) {
    cb().then(() => {
      this.sendEvent(new StoppedEvent(stoppedReason, args.threadId));
    });

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
      () => this.runtime?.continue()!,
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
      () => this.runtime?.next()!,
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
      () => this.runtime?.stepInto()!,
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
      () => this.runtime?.stepOut()!,
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

    this.runtime?.getSource(args.source?.path).then((content) => {
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

  protected override breakpointLocationsRequest(
    response: DebugProtocol.BreakpointLocationsResponse,
    args: DebugProtocol.BreakpointLocationsArguments,
    request?: DebugProtocol.Request | undefined
  ): void {
    this.runtime
      ?.getBreakpointLocations(args.source.path!, args.line, args.endLine)
      .then((breakpoints) => {
        response.success = true;
        response.body = { breakpoints };
        this.sendResponse(response);
      });
  }

  protected override disconnectRequest(
    response: DebugProtocol.DisconnectResponse,
    args: DebugProtocol.DisconnectArguments,
    request?: DebugProtocol.Request | undefined
  ): void {
    this.terminateRequest(response, args, request);
  }

  protected override terminateRequest(
    response: DebugProtocol.TerminateResponse,
    args: DebugProtocol.TerminateArguments,
    request?: DebugProtocol.Request | undefined
  ): void {
    this.runtime?.terminate();

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
    let promise;

    if (args.context === 'repl') {
      promise = this.runtime?.runCommand(args.expression);
    } else {
      promise = this.runtime?.evaluateVariable(args.expression);
    }

    promise?.then((result) => {
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
    await this.runtime?.clearAllBreakpoints();

    if (
      args.source.path === undefined ||
      args.breakpoints === undefined ||
      args.breakpoints.length === 0
    ) {
      return response;
    }

    response.body = { breakpoints: [] };

    for (const breakpoint of args.breakpoints) {
      response.body.breakpoints.push({
        verified: await this.runtime?.setBreakpoint(
          args.source.path,
          breakpoint.line,
          breakpoint.condition
        )!,
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
    await this.runtime?.clearAllFunctionBreakpoints();

    response.body = { breakpoints: [] };

    for (const breakpoint of args.breakpoints) {
      const location = await this.runtime?.setFunctionBreakpoint(
        breakpoint.name,
        breakpoint.condition
      );

      response.body.breakpoints.push({
        verified: location === undefined ? false : true,
        line: location?.line,
        source: {
          path: location?.path,
          name: location?.path,
        },
      });
    }

    return response;
  }
}
