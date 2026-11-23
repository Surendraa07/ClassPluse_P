import { Router } from 'express';
import { z } from 'zod';
import { IdParam, parse } from '../../lib/validate';
import { lecturerIdOf, requireLecturer } from '../../middleware/auth';
import { buildState, createSession, getOwnedSession, participantCount, sessionSummary } from './session.service';

const CreateSessionBody = z.object({ presentationId: z.string().min(1).max(64) });

export const sessionsRouter = Router();
sessionsRouter.use(requireLecturer);

/** Start a session from a presentation. Returns the existing one if it's still active. */
sessionsRouter.post('/', async (req, res) => {
  const { presentationId } = parse(CreateSessionBody, req.body);
  const { session, resumed } = await createSession(lecturerIdOf(req), presentationId);
  res.status(resumed ? 200 : 201).json({ sessionId: session.id, code: session.code, status: session.status, resumed });
});

/** Current state for the lecturer (used to restore the waiting room / dashboard). */
sessionsRouter.get('/:id', async (req, res) => {
  const { id } = parse(IdParam, req.params);
  const session = await getOwnedSession(lecturerIdOf(req), id);
  res.json({ ...buildState(session, 'lecturer'), participants: await participantCount(id) });
});

sessionsRouter.get('/:id/summary', async (req, res) => {
  const { id } = parse(IdParam, req.params);
  const session = await getOwnedSession(lecturerIdOf(req), id);
  res.json(await sessionSummary(session));
});
