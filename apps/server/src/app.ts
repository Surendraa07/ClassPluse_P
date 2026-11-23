import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import pinoHttp from 'pino-http';
import { env } from './config/env';
import { logger } from './lib/logger';
import { healthRouter } from './routes/health';
import { apiRouter } from './routes';
import { errorHandler, notFoundHandler } from './middleware/error';

export function corsOrigin(): cors.CorsOptions['origin'] {
  if (env.CORS_ORIGIN.trim() === '*') return true;
  return env.CORS_ORIGIN.split(',').map((o) => o.trim());
}

export function createApp() {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', 1);

  app.use(helmet());
  app.use(cors({ origin: corsOrigin() }));
  app.use(express.json({ limit: '100kb' }));
  app.use(pinoHttp({ logger, autoLogging: env.NODE_ENV !== 'test' }));

  app.use('/health', healthRouter);
  app.use('/api/v1', apiRouter());

  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}
