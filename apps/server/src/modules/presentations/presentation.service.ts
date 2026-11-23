import { AppError } from '../../lib/errors';
import { prisma } from '../../lib/prisma';
import type { Prisma } from '../../generated/prisma/client';

type Db = typeof prisma | Prisma.TransactionClient;

export const slideInclude = {
  options: { orderBy: { order: 'asc' }, select: { id: true, order: true, label: true, isCorrect: true } },
} as const satisfies Prisma.SlideInclude;

export const slideSelect = {
  id: true,
  order: true,
  type: true,
  question: true,
  imageUrl: true,
  options: slideInclude.options,
} as const satisfies Prisma.SlideSelect;

/**
 * Loads a presentation owned by the lecturer. Returns 404 (not 403) for presentations owned
 * by someone else so ids of other lecturers' content are not revealed.
 */
export async function getOwnedPresentation(lecturerId: string, presentationId: string, db: Db = prisma) {
  const presentation = await db.presentation.findUnique({ where: { id: presentationId } });
  if (!presentation || presentation.lecturerId !== lecturerId) throw AppError.notFound('Presentation not found');
  return presentation;
}

/** Content can't change while a session of this presentation is waiting or live. */
export async function assertNoActiveSession(presentationId: string, db: Db = prisma) {
  const active = await db.session.findFirst({
    where: { presentationId, status: { not: 'ENDED' } },
    select: { id: true },
  });
  if (active) {
    throw new AppError(409, 'SESSION_ACTIVE', 'End the live session before editing this presentation');
  }
}

export async function presentationDetail(presentationId: string, db: Db = prisma) {
  return db.presentation.findUniqueOrThrow({
    where: { id: presentationId },
    select: {
      id: true,
      title: true,
      createdAt: true,
      updatedAt: true,
      slides: { orderBy: { order: 'asc' }, select: slideSelect },
    },
  });
}

export async function touchPresentation(presentationId: string, db: Db = prisma) {
  await db.presentation.update({ where: { id: presentationId }, data: { updatedAt: new Date() } });
}
