import * as net from 'net';

/**
 * This class creates a simple proxy to send commands to a debuggee.
 *
 * This is used when a process forks. To connect VSCode to the forked process,
 * the following happens
 *
 * 1. This class is created and passed the server end of the socket for the forked process
 * 2. This class starts a new server on a random port which takes debugger commands and
 *    pipes them to the socket.
 * 3. A new debugger is created which will open up a client connection to the server in this
 *    class, and it will send commands and receive results to the process through this server.
 */
export class DebuggerProxy {
  private client: net.Socket;
  private socket?: net.Socket;

  constructor(client: net.Socket) {
    this.client = client;
  }

  async listen(): Promise<number> {
    return new Promise((resolve) => {
      const server = net
        .createServer((socket) => {
          if (!this.socket) {
            this.socket = socket;

            socket.on('close', () => this.client.destroy());
            this.client.on('close', () => socket.destroy());

            socket.pipe(this.client);
            this.client.pipe(socket);
          }
        })
        .on('listening', () => {
          resolve((server.address() as net.AddressInfo).port);
        })
        .listen(0);
    });
  }
}
