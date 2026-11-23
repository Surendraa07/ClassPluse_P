import http from 'node:http';
import type { AddressInfo } from 'node:net';
import { io as ioClient, type Socket } from 'socket.io-client';
import { createApp } from '../src/app';
import { attachRealtime } from '../src/realtime/socket';

export async function startServer() {
  const app = createApp();
  const server = http.createServer(app);
  const realtime = attachRealtime(server);
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address() as AddressInfo;
  return {
    app,
    url: `http://127.0.0.1:${port}`,
    async close() {
      await realtime.close();
      await new Promise<void>((resolve) => server.close(() => resolve()));
    },
  };
}

interface Received {
  event: string;
  payload: any; // eslint-disable-line @typescript-eslint/no-explicit-any
}

/** Socket.io client that records every event so tests can await them without races. */
export class TestClient {
  readonly history: Received[] = [];
  private waiters: Array<{ event: string; pred: (p: any) => boolean; resolve: (p: any) => void }> = []; // eslint-disable-line @typescript-eslint/no-explicit-any

  constructor(readonly socket: Socket) {
    socket.onAny((event: string, payload: unknown) => {
      this.history.push({ event, payload });
      this.waiters = this.waiters.filter((w) => {
        if (w.event === event && w.pred(payload)) {
          w.resolve(payload);
          return false;
        }
        return true;
      });
    });
  }

  static async connect(url: string, auth: Record<string, string>): Promise<TestClient> {
    const socket = ioClient(url, { auth, transports: ['websocket'], forceNew: true, reconnection: false });
    const client = new TestClient(socket);
    await new Promise<void>((resolve, reject) => {
      socket.once('connect', () => resolve());
      socket.once('connect_error', (err) => reject(err));
    });
    return client;
  }

  /** Resolves with the first event (already received or future) matching the predicate. */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  waitFor(event: string, pred: (payload: any) => boolean = () => true, timeoutMs = 3000): Promise<any> {
    const seen = this.history.find((h) => h.event === event && pred(h.payload));
    if (seen) return Promise.resolve(seen.payload);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error(`Timed out waiting for "${event}"`)), timeoutMs);
      this.waiters.push({
        event,
        pred,
        resolve: (p) => {
          clearTimeout(timer);
          resolve(p);
        },
      });
    });
  }

  received(event: string) {
    return this.history.filter((h) => h.event === event).map((h) => h.payload);
  }

  clear() {
    this.history.length = 0;
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  emit(event: string, payload?: unknown): Promise<any> {
    return new Promise((resolve) => this.socket.emit(event, payload ?? {}, resolve));
  }

  close() {
    this.socket.disconnect();
  }
}

export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
