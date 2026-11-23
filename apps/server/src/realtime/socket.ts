import type http from 'node:http';
import { Server, type Socket } from 'socket.io';
import type { DefaultEventsMap } from 'socket.io/dist/typed-events';
import { z } from 'zod';
import { env } from '../config/env';
import { corsOrigin } from '../app';
import { AppError } from '../lib/errors';
import { verifyLecturerToken } from '../lib/jwt';
import { logger } from '../lib/logger';
import { prisma } from '../lib/prisma';
import { hashToken } from '../lib/tokens';
import {
  buildState,
  loadSession,
  participantCount,
  pulseFor,
  resultsFor,
  type SessionWithSlides,
} from '../modules/sessions/session.service';
import { setRealtime } from './registry';
import { KeyedThrottle } from './throttle';

/** Payloads (validated with zod). */
const AnswerPayload = z.object({ slideId: z.string().min(1).max(64), optionId: z.string().min(1).max(64) });
const PulsePayload = z.object({ state: z.enum(['FOLLOWING', 'LOST']) });
const GotoPayload = z.object({ slideId: z.string().min(1).max(64) });
const TogglePayload = z.object({ show: z.boolean() });

type Ack = (res: { ok: true; [k: string]: unknown } | { ok: false; error: { code: string; message: string } }) => void;

interface SocketData {
  role: 'lecturer' | 'student';
  sessionId: string;
  lecturerId?: string;
  participantId?: string;
}

type AppSocket = Socket<DefaultEventsMap, DefaultEventsMap, DefaultEventsMap, SocketData>;

const room = (sessionId: string) => `session:${sessionId}`;
const lecturerRoom = (sessionId: string) => `session:${sessionId}:lecturer`;

/** Max events a single socket may send per second (spam-tap protection). */
const EVENTS_PER_SECOND = 10;

export function attachRealtime(server: http.Server) {
  const io = new Server(server, {
    cors: { origin: corsOrigin() },
    // Mobile clients reconnect on flaky Wi-Fi; keep detection reasonably quick.
    pingInterval: 10_000,
    pingTimeout: 8_000,
  });
  const throttle = new KeyedThrottle(env.BROADCAST_THROTTLE_MS);

  // ---------- broadcasts ----------

  async function broadcastState(sessionId: string) {
    const session = await loadSession(sessionId);
    if (!session) return;
    io.to(lecturerRoom(sessionId)).emit('session:state', buildState(session, 'lecturer'));
    io.to(room(sessionId)).except(lecturerRoom(sessionId)).emit('session:state', buildState(session, 'student'));
  }

  function scheduleCount(sessionId: string) {
    throttle.run(`count:${sessionId}`, async () => {
      io.to(room(sessionId)).emit('participants:count', { count: await participantCount(sessionId) });
    });
  }

  function scheduleResults(sessionId: string) {
    throttle.run(`results:${sessionId}`, async () => {
      const session = await prisma.session.findUnique({
        where: { id: sessionId },
        select: { currentSlideId: true, showResultsToStudents: true },
      });
      if (!session?.currentSlideId) return;
      const results = await resultsFor(sessionId, session.currentSlideId);
      // Students only receive results when the lecturer has switched them on.
      io.to(session.showResultsToStudents ? room(sessionId) : lecturerRoom(sessionId)).emit('results:update', results);
    });
  }

  function schedulePulse(sessionId: string) {
    throttle.run(`pulse:${sessionId}`, async () => {
      // Pulse totals are for the lecturer only.
      io.to(lecturerRoom(sessionId)).emit('pulse:update', await pulseFor(sessionId));
    });
  }

  setRealtime({ participantJoined: scheduleCount });

  // ---------- authentication on connect ----------

  io.use(async (socket: AppSocket, next) => {
    try {
      const authData = (socket.handshake.auth ?? {}) as Record<string, unknown>;
      if (typeof authData.participantToken === 'string') {
        const participant = await prisma.participant.findUnique({
          where: { anonToken: hashToken(authData.participantToken) },
          include: { session: { select: { status: true } } },
        });
        if (!participant) return next(socketError('UNAUTHORIZED', 'Invalid participant token'));
        if (participant.session.status === 'ENDED') return next(socketError('SESSION_ENDED', 'This session has ended'));
        socket.data = { role: 'student', sessionId: participant.sessionId, participantId: participant.id };
        return next();
      }
      if (typeof authData.token === 'string' && typeof authData.sessionId === 'string') {
        const lecturerId = verifyLecturerToken(authData.token);
        if (!lecturerId) return next(socketError('UNAUTHORIZED', 'Invalid or expired token'));
        const session = await prisma.session.findUnique({
          where: { id: authData.sessionId },
          select: { presentation: { select: { lecturerId: true } } },
        });
        if (!session || session.presentation.lecturerId !== lecturerId) {
          return next(socketError('NOT_FOUND', 'Session not found'));
        }
        socket.data = { role: 'lecturer', sessionId: authData.sessionId, lecturerId };
        return next();
      }
      return next(socketError('UNAUTHORIZED', 'Missing credentials'));
    } catch (err) {
      logger.error({ err }, 'socket auth failed');
      return next(socketError('INTERNAL_ERROR', 'Could not authenticate'));
    }
  });

  // ---------- connection ----------

  io.on('connection', (socket: AppSocket) => {
    const { sessionId, role } = socket.data;

    // Handlers are registered synchronously (below) so events sent right after connecting, such as
    // a queued offline answer, are not lost; each handler waits for this setup to finish first.
    const ready = (async () => {
      await socket.join(room(sessionId));
      if (role === 'lecturer') await socket.join(lecturerRoom(sessionId));
      // Send the latest state on (re)connect.
      try {
        await sendSnapshot(socket);
      } catch (err) {
        logger.error({ err }, 'snapshot failed');
      }
    })();

    const allow = rateGate();
    const on = (event: string, roleRequired: SocketData['role'], handler: (payload: unknown) => Promise<object | void>) => {
      socket.on(event, async (payload: unknown, maybeAck?: unknown) => {
        const ack: Ack = typeof maybeAck === 'function' ? (maybeAck as Ack) : () => undefined;
        await ready;
        if (!allow()) return ack({ ok: false, error: { code: 'RATE_LIMITED', message: 'Slow down' } });
        if (socket.data.role !== roleRequired) {
          return ack({ ok: false, error: { code: 'FORBIDDEN', message: 'Not allowed for this role' } });
        }
        try {
          const result = await handler(payload);
          ack({ ok: true, ...(result ?? {}) });
        } catch (err) {
          ack({ ok: false, error: toSocketError(err) });
        }
      });
    };

    // ----- lecturer -----

    on('session:start', 'lecturer', async () => {
      const session = await requireSession(sessionId);
      if (session.status === 'ENDED') throw new AppError(409, 'SESSION_ENDED', 'This session has ended');
      if (session.status === 'WAITING') {
        const first = session.presentation.slides[0];
        if (!first) throw new AppError(400, 'NO_SLIDES', 'This presentation has no slides');
        await prisma.session.update({ where: { id: sessionId }, data: { status: 'LIVE', currentSlideId: first.id } });
      }
      await broadcastState(sessionId);
      scheduleResults(sessionId);
    });

    on('slide:next', 'lecturer', async () => {
      const session = await requireLive(sessionId);
      const slides = session.presentation.slides;
      const index = slides.findIndex((s) => s.id === session.currentSlideId);
      const next = slides[index + 1];
      if (!next) throw new AppError(409, 'NO_MORE_SLIDES', 'This is the last slide');
      await prisma.session.update({ where: { id: sessionId }, data: { currentSlideId: next.id } });
      await broadcastState(sessionId);
      scheduleResults(sessionId);
    });

    on('slide:goto', 'lecturer', async (payload) => {
      const { slideId } = GotoPayload.parse(payload);
      const session = await requireLive(sessionId);
      if (!session.presentation.slides.some((s) => s.id === slideId)) {
        throw new AppError(404, 'NOT_FOUND', 'Slide not found in this session');
      }
      await prisma.session.update({ where: { id: sessionId }, data: { currentSlideId: slideId } });
      await broadcastState(sessionId);
      scheduleResults(sessionId);
    });

    on('results:toggle', 'lecturer', async (payload) => {
      const { show } = TogglePayload.parse(payload);
      const session = await requireSession(sessionId);
      if (session.status === 'ENDED') throw new AppError(409, 'SESSION_ENDED', 'This session has ended');
      await prisma.session.update({ where: { id: sessionId }, data: { showResultsToStudents: show } });
      await broadcastState(sessionId);
      scheduleResults(sessionId);
      return { show };
    });

    on('session:end', 'lecturer', async () => {
      const session = await requireSession(sessionId);
      if (session.status !== 'ENDED') {
        await prisma.session.update({ where: { id: sessionId }, data: { status: 'ENDED', endedAt: new Date() } });
      }
      io.to(room(sessionId)).emit('session:ended', { sessionId });
      // Students are done; lecturers stay connected to read the summary if they want.
      const sockets = await io.in(room(sessionId)).except(lecturerRoom(sessionId)).fetchSockets();
      for (const s of sockets) s.disconnect(true);
    });

    // ----- student -----

    on('answer:submit', 'student', async (payload) => {
      const { slideId, optionId } = AnswerPayload.parse(payload);
      const session = await requireLive(sessionId);
      if (session.currentSlideId !== slideId) {
        throw new AppError(409, 'SLIDE_CLOSED', 'This question is closed');
      }
      const slide = session.presentation.slides.find((s) => s.id === slideId);
      if (!slide?.options.some((o) => o.id === optionId)) {
        throw new AppError(400, 'INVALID_OPTION', 'That option does not belong to this question');
      }
      const participantId = socket.data.participantId!;
      await prisma.response.upsert({
        where: { participantId_slideId: { participantId, slideId } },
        create: { sessionId, slideId, participantId, optionId },
        update: { optionId },
      });
      scheduleResults(sessionId);
      return { slideId, optionId };
    });

    on('pulse:set', 'student', async (payload) => {
      const { state } = PulsePayload.parse(payload);
      const session = await requireSession(sessionId);
      if (session.status === 'ENDED') throw new AppError(409, 'SESSION_ENDED', 'This session has ended');
      const participantId = socket.data.participantId!;
      // Only the current state per student counts.
      await prisma.pulseState.upsert({
        where: { participantId },
        create: { participantId, sessionId, state },
        update: { state },
      });
      schedulePulse(sessionId);
      return { state };
    });
  });

  // ---------- helpers ----------

  async function sendSnapshot(socket: AppSocket) {
    const { sessionId, role, participantId } = socket.data;
    const session = await requireSession(sessionId);
    socket.emit('session:state', buildState(session, role));
    socket.emit('participants:count', { count: await participantCount(sessionId) });

    const canSeeResults = role === 'lecturer' || session.showResultsToStudents;
    if (session.currentSlideId && canSeeResults) {
      socket.emit('results:update', await resultsFor(sessionId, session.currentSlideId));
    }
    if (role === 'lecturer') {
      socket.emit('pulse:update', await pulseFor(sessionId));
    } else if (participantId) {
      // Let a reconnecting student restore their own selection and pulse.
      const [answer, pulse] = await Promise.all([
        session.currentSlideId
          ? prisma.response.findUnique({
              where: { participantId_slideId: { participantId, slideId: session.currentSlideId } },
              select: { slideId: true, optionId: true },
            })
          : null,
        prisma.pulseState.findUnique({ where: { participantId }, select: { state: true } }),
      ]);
      socket.emit('me:state', { answer, pulse: pulse?.state ?? null });
    }
  }

  return {
    io,
    async close() {
      throttle.clear();
      setRealtime(null);
      await new Promise<void>((resolve) => io.close(() => resolve()));
    },
  };
}

async function requireSession(sessionId: string): Promise<SessionWithSlides> {
  const session = await loadSession(sessionId);
  if (!session) throw AppError.notFound('Session not found');
  return session;
}

async function requireLive(sessionId: string) {
  const session = await requireSession(sessionId);
  if (session.status !== 'LIVE') {
    throw new AppError(409, session.status === 'ENDED' ? 'SESSION_ENDED' : 'SESSION_NOT_LIVE', `Session is ${session.status.toLowerCase()}`);
  }
  return session;
}

function rateGate() {
  let windowStart = Date.now();
  let count = 0;
  return () => {
    const now = Date.now();
    if (now - windowStart >= 1000) {
      windowStart = now;
      count = 0;
    }
    count += 1;
    return count <= EVENTS_PER_SECOND;
  };
}

function socketError(code: string, message: string) {
  const err = new Error(message) as Error & { data: { code: string } };
  err.data = { code };
  return err;
}

function toSocketError(err: unknown): { code: string; message: string } {
  if (err instanceof AppError) return { code: err.code, message: err.message };
  if (err instanceof z.ZodError) return { code: 'VALIDATION_ERROR', message: err.issues.map((i) => i.message).join('; ') };
  logger.error({ err }, 'socket handler failed');
  return { code: 'INTERNAL_ERROR', message: 'Something went wrong' };
}
