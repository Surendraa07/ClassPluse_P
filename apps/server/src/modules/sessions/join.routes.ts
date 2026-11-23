import { Router } from 'express';
import { z } from 'zod';
import { AppError } from '../../lib/errors';
import { prisma } from '../../lib/prisma';
import { generateParticipantToken, hashToken } from '../../lib/tokens';
import { parse } from '../../lib/validate';
import { joinLimiter } from '../../middleware/rateLimit';
import { realtime } from '../../realtime/registry';

const JoinBody = z.object({
  code: z.string().trim().regex(/^\d{6}$/, 'Enter the 6-digit code'),
  /** Optional: a token from an earlier join of the same session, to rejoin as the same participant. */
  participantToken: z.string().min(16).max(128).optional(),
});

const invalidCode = () => new AppError(404, 'SESSION_NOT_FOUND', 'This code is invalid or the session has ended');

export const joinRouter = Router();

joinRouter.post('/', joinLimiter, async (req, res) => {
  const { code, participantToken } = parse(JoinBody, req.body);
  const session = await prisma.session.findFirst({
    where: { code, status: { not: 'ENDED' } },
    select: { id: true },
  });
  if (!session) throw invalidCode();

  if (participantToken) {
    const existing = await prisma.participant.findUnique({ where: { anonToken: hashToken(participantToken) } });
    if (existing && existing.sessionId === session.id) {
      res.json({ participantToken, sessionId: session.id, rejoined: true });
      return;
    }
  }

  const token = generateParticipantToken();
  await prisma.participant.create({ data: { sessionId: session.id, anonToken: hashToken(token) } });
  realtime()?.participantJoined(session.id);
  res.status(201).json({ participantToken: token, sessionId: session.id, rejoined: false });
});
