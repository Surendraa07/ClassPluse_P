import { AppError } from '../../lib/errors';
import { prisma } from '../../lib/prisma';
import { generateSessionCode } from '../../lib/tokens';
import { Prisma } from '../../generated/prisma/client';

export type Audience = 'lecturer' | 'student';

export const sessionWithSlides = {
  presentation: {
    select: {
      id: true,
      title: true,
      lecturerId: true,
      slides: {
        orderBy: { order: 'asc' },
        select: {
          id: true,
          order: true,
          type: true,
          question: true,
          imageUrl: true,
          options: { orderBy: { order: 'asc' }, select: { id: true, label: true, isCorrect: true } },
        },
      },
    },
  },
} as const satisfies Prisma.SessionInclude;

export type SessionWithSlides = Prisma.SessionGetPayload<{ include: typeof sessionWithSlides }>;

export async function loadSession(sessionId: string): Promise<SessionWithSlides | null> {
  return prisma.session.findUnique({ where: { id: sessionId }, include: sessionWithSlides });
}

export async function getOwnedSession(lecturerId: string, sessionId: string) {
  const session = await loadSession(sessionId);
  if (!session || session.presentation.lecturerId !== lecturerId) throw AppError.notFound('Session not found');
  return session;
}

/** Shape sent in `session:state`. Students never receive `isCorrect`. */
export function buildState(session: SessionWithSlides, audience: Audience) {
  const slides = session.presentation.slides;
  const index = slides.findIndex((s) => s.id === session.currentSlideId);
  const slide = index >= 0 ? slides[index] : undefined;
  return {
    sessionId: session.id,
    status: session.status,
    showResultsToStudents: session.showResultsToStudents,
    totalSlides: slides.length,
    currentSlide: slide
      ? {
          id: slide.id,
          index,
          type: slide.type,
          question: slide.question,
          imageUrl: slide.imageUrl,
          options: slide.options.map((o) =>
            audience === 'lecturer' ? { id: o.id, label: o.label, isCorrect: o.isCorrect } : { id: o.id, label: o.label },
          ),
        }
      : null,
    presentationTitle: session.presentation.title,
    ...(audience === 'lecturer' ? { code: session.code, isLastSlide: index === slides.length - 1 } : {}),
  };
}

export async function participantCount(sessionId: string) {
  return prisma.participant.count({ where: { sessionId } });
}

/** Aggregated counts only; never which participant chose what. */
export async function resultsFor(sessionId: string, slideId: string) {
  const [options, grouped, participants] = await Promise.all([
    prisma.option.findMany({ where: { slideId }, orderBy: { order: 'asc' }, select: { id: true } }),
    prisma.response.groupBy({ by: ['optionId'], where: { sessionId, slideId }, _count: { _all: true } }),
    participantCount(sessionId),
  ]);
  const byOption = new Map(grouped.map((g) => [g.optionId, g._count._all]));
  const counts = options.map((o) => ({ optionId: o.id, count: byOption.get(o.id) ?? 0 }));
  return { slideId, counts, answered: counts.reduce((a, c) => a + c.count, 0), participants };
}

export async function pulseFor(sessionId: string) {
  const grouped = await prisma.pulseState.groupBy({ by: ['state'], where: { sessionId }, _count: { _all: true } });
  const following = grouped.find((g) => g.state === 'FOLLOWING')?._count._all ?? 0;
  const lost = grouped.find((g) => g.state === 'LOST')?._count._all ?? 0;
  return { following, lost, total: following + lost };
}

/** Creates a WAITING session with a code that is unique among non-ended sessions. */
export async function createSession(lecturerId: string, presentationId: string) {
  const presentation = await prisma.presentation.findUnique({
    where: { id: presentationId },
    select: { lecturerId: true, _count: { select: { slides: true } } },
  });
  if (!presentation || presentation.lecturerId !== lecturerId) throw AppError.notFound('Presentation not found');
  if (presentation._count.slides === 0) {
    throw new AppError(400, 'NO_SLIDES', 'Add at least one slide before starting a session');
  }

  // Resume instead of creating a second active session for the same presentation.
  const active = await prisma.session.findFirst({
    where: { presentationId, status: { not: 'ENDED' } },
    select: { id: true, code: true, status: true },
  });
  if (active) return { session: active, resumed: true };

  for (let attempt = 0; attempt < 10; attempt++) {
    try {
      const session = await prisma.session.create({
        data: { presentationId, code: generateSessionCode() },
        select: { id: true, code: true, status: true },
      });
      return { session, resumed: false };
    } catch (err) {
      if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') continue; // code clash
      throw err;
    }
  }
  throw new AppError(503, 'CODE_UNAVAILABLE', 'Could not allocate a session code, please retry');
}

export async function sessionSummary(session: SessionWithSlides) {
  const [grouped, participants, pulse] = await Promise.all([
    prisma.response.groupBy({ by: ['slideId', 'optionId'], where: { sessionId: session.id }, _count: { _all: true } }),
    participantCount(session.id),
    pulseFor(session.id),
  ]);
  const count = (slideId: string, optionId: string) =>
    grouped.find((g) => g.slideId === slideId && g.optionId === optionId)?._count._all ?? 0;
  const pct = (n: number, d: number) => (d === 0 ? 0 : Math.round((n / d) * 1000) / 10);

  const slides = session.presentation.slides.map((s) => {
    const options = s.options.map((o) => ({ id: o.id, label: o.label, isCorrect: o.isCorrect, count: count(s.id, o.id) }));
    const responses = options.reduce((a, o) => a + o.count, 0);
    const correct = options.filter((o) => o.isCorrect).reduce((a, o) => a + o.count, 0);
    return {
      slideId: s.id,
      index: s.order,
      type: s.type,
      question: s.question,
      responses,
      options: options.map((o) => ({ ...o, percent: pct(o.count, responses) })),
      percentCorrect: s.type === 'QUIZ' ? pct(correct, responses) : null,
    };
  });

  return {
    sessionId: session.id,
    presentationId: session.presentation.id,
    presentationTitle: session.presentation.title,
    status: session.status,
    startedAt: session.startedAt,
    endedAt: session.endedAt,
    participants,
    pulse,
    slides,
  };
}
