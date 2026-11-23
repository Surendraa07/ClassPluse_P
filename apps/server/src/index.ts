import http from 'node:http';
import { env } from './config/env';
import { createApp } from './app';
import { logger } from './lib/logger';
import { prisma } from './lib/prisma';
import { attachRealtime } from './realtime/socket';

const app = createApp();
const server = http.createServer(app);
const realtime = attachRealtime(server);

// Listen on all interfaces so phones on the same Wi-Fi can reach the dev server.
server.listen(env.PORT, '0.0.0.0', () => {
  logger.info(`ClassPluse server listening on http://localhost:${env.PORT} (REST + Socket.io)`);
});

async function shutdown(signal: string) {
  logger.info(`${signal} received, shutting down`);
  await realtime.close();
  server.close();
  await prisma.$disconnect();
  process.exit(0);
}
process.on('SIGINT', () => void shutdown('SIGINT'));
process.on('SIGTERM', () => void shutdown('SIGTERM'));
