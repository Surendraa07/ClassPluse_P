import { Router } from 'express';
import { healthRouter } from './health';
import { authRouter } from '../modules/auth/auth.routes';
import { presentationsRouter } from '../modules/presentations/presentation.routes';
import { slidesRouter } from '../modules/slides/slide.routes';
import { sessionsRouter } from '../modules/sessions/session.routes';
import { joinRouter } from '../modules/sessions/join.routes';
import { uploadsRouter } from '../modules/uploads/upload.routes';

/** All REST routes under /api/v1. */
export function apiRouter() {
  const api = Router();
  api.use('/health', healthRouter);
  api.use('/auth', authRouter);
  api.use('/presentations', presentationsRouter);
  api.use('/slides', slidesRouter);
  api.use('/sessions', sessionsRouter);
  api.use('/join', joinRouter);
  api.use('/uploads', uploadsRouter);
  return api;
}
