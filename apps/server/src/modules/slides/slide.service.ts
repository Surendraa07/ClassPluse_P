import type { z } from 'zod';
import { destroyImage, verifyUploadedImage } from '../../lib/cloudinary';
import { AppError } from '../../lib/errors';
import { prisma } from '../../lib/prisma';
import {
  assertNoActiveSession,
  getOwnedPresentation,
  slideSelect,
  touchPresentation,
} from '../presentations/presentation.service';
import { type CreateSlideBody, slideRuleIssues, type UpdateSlideBody } from './slide.schemas';

type CreateInput = z.infer<typeof CreateSlideBody>;
type UpdateInput = z.infer<typeof UpdateSlideBody>;

const slideNotFound = () => AppError.notFound('Slide not found');

/** Loads a slide whose presentation belongs to the lecturer (404 otherwise). */
async function getOwnedSlide(lecturerId: string, slideId: string) {
  const slide = await prisma.slide.findUnique({
    where: { id: slideId },
    include: { presentation: { select: { lecturerId: true } }, options: { orderBy: { order: 'asc' } } },
  });
  if (!slide || slide.presentation.lecturerId !== lecturerId) throw slideNotFound();
  return slide;
}

export async function createSlide(lecturerId: string, presentationId: string, input: CreateInput) {
  await getOwnedPresentation(lecturerId, presentationId);
  await assertNoActiveSession(presentationId);
  const imageUrl = input.imageUrl ? await verifyUploadedImage(input.imageUrl, 'slide', lecturerId) : null;

  return prisma.$transaction(async (tx) => {
    const last = await tx.slide.findFirst({
      where: { presentationId },
      orderBy: { order: 'desc' },
      select: { order: true },
    });
    const slide = await tx.slide.create({
      data: {
        presentationId,
        order: (last?.order ?? -1) + 1,
        type: input.type,
        question: input.question,
        imageUrl,
        options: {
          create: input.options.map((o, i) => ({ order: i, label: o.label, isCorrect: o.isCorrect })),
        },
      },
      select: slideSelect,
    });
    await touchPresentation(presentationId, tx);
    return slide;
  });
}

export async function updateSlide(lecturerId: string, slideId: string, input: UpdateInput) {
  const slide = await getOwnedSlide(lecturerId, slideId);
  await assertNoActiveSession(slide.presentationId);

  const type = input.type ?? slide.type;
  const options = input.options ?? slide.options.map((o) => ({ id: o.id, label: o.label, isCorrect: o.isCorrect }));

  const issues = slideRuleIssues(type, options);
  if (issues.length > 0) {
    throw new AppError(400, 'VALIDATION_ERROR', 'Request validation failed', issues);
  }

  if (input.options) {
    const existingIds = new Set(slide.options.map((o) => o.id));
    const givenIds = input.options.flatMap((o) => (o.id ? [o.id] : []));
    if (new Set(givenIds).size !== givenIds.length) throw AppError.badRequest('Duplicate option ids');
    const foreign = givenIds.filter((id) => !existingIds.has(id));
    if (foreign.length > 0) throw AppError.badRequest('Option ids must belong to this slide', { ids: foreign });
  }

  // Only new images need checking; re-sending the current URL is a no-op.
  let imageUrl = input.imageUrl;
  if (imageUrl && imageUrl !== slide.imageUrl) {
    imageUrl = await verifyUploadedImage(imageUrl, 'slide', lecturerId);
  }

  const updated = await prisma.$transaction(async (tx) => {
    if (input.options) {
      const keep = new Set(input.options.flatMap((o) => (o.id ? [o.id] : [])));
      // Removing an option also removes the past responses that chose it (cascade).
      await tx.option.deleteMany({ where: { slideId, id: { notIn: [...keep] } } });
      for (const [i, o] of input.options.entries()) {
        if (o.id) {
          await tx.option.update({ where: { id: o.id }, data: { order: i, label: o.label, isCorrect: o.isCorrect } });
        } else {
          await tx.option.create({ data: { slideId, order: i, label: o.label, isCorrect: o.isCorrect } });
        }
      }
    }
    const updated = await tx.slide.update({
      where: { id: slideId },
      data: {
        ...(input.type !== undefined ? { type: input.type } : {}),
        ...(input.question !== undefined ? { question: input.question } : {}),
        ...(imageUrl !== undefined ? { imageUrl } : {}),
      },
      select: slideSelect,
    });
    await touchPresentation(slide.presentationId, tx);
    return updated;
  });
  if (imageUrl !== undefined && slide.imageUrl && slide.imageUrl !== imageUrl) void destroyImage(slide.imageUrl);
  return updated;
}

export async function deleteSlide(lecturerId: string, slideId: string) {
  const slide = await getOwnedSlide(lecturerId, slideId);
  await assertNoActiveSession(slide.presentationId);

  await prisma.$transaction(async (tx) => {
    await tx.slide.delete({ where: { id: slideId } });
    // Keep order contiguous (0..n-1).
    const remaining = await tx.slide.findMany({
      where: { presentationId: slide.presentationId },
      orderBy: { order: 'asc' },
      select: { id: true },
    });
    for (const [i, s] of remaining.entries()) {
      await tx.slide.update({ where: { id: s.id }, data: { order: i } });
    }
    await touchPresentation(slide.presentationId, tx);
  });
  void destroyImage(slide.imageUrl);
}

/** slideIds must be exactly the presentation's slides, in the new order. */
export async function reorderSlides(lecturerId: string, presentationId: string, slideIds: string[]) {
  await getOwnedPresentation(lecturerId, presentationId);
  await assertNoActiveSession(presentationId);

  return prisma.$transaction(async (tx) => {
    const current = await tx.slide.findMany({ where: { presentationId }, select: { id: true } });
    const currentIds = new Set(current.map((s) => s.id));
    const sameSet = slideIds.length === currentIds.size && slideIds.every((id) => currentIds.has(id));
    if (!sameSet) {
      throw AppError.badRequest('slideIds must list every slide of this presentation exactly once');
    }
    for (const [i, id] of slideIds.entries()) {
      await tx.slide.update({ where: { id }, data: { order: i } });
    }
    await touchPresentation(presentationId, tx);
    return tx.slide.findMany({ where: { presentationId }, orderBy: { order: 'asc' }, select: slideSelect });
  });
}
