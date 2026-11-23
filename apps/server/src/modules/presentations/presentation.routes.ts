import { Router } from 'express';
import { z } from 'zod';
import { destroyImage } from '../../lib/cloudinary';
import { AppError } from '../../lib/errors';
import { prisma } from '../../lib/prisma';
import { IdParam, parse } from '../../lib/validate';
import { lecturerIdOf, requireLecturer } from '../../middleware/auth';
import { createSlide, reorderSlides } from '../slides/slide.service';
import { CreateSlideBody, ReorderBody } from '../slides/slide.schemas';
import { assertNoActiveSession, getOwnedPresentation, presentationDetail } from './presentation.service';

const Title = z.string().trim().min(1, 'Title is required').max(150);
const CreatePresentationBody = z.object({ title: Title });
const UpdatePresentationBody = z.object({ title: Title });

export const presentationsRouter = Router();
presentationsRouter.use(requireLecturer);

presentationsRouter.get('/', async (req, res) => {
  const rows = await prisma.presentation.findMany({
    where: { lecturerId: lecturerIdOf(req) },
    orderBy: { updatedAt: 'desc' },
    select: { id: true, title: true, createdAt: true, updatedAt: true, _count: { select: { slides: true } } },
  });
  res.json(rows.map(({ _count, ...p }) => ({ ...p, slideCount: _count.slides })));
});

presentationsRouter.post('/', async (req, res) => {
  const body = parse(CreatePresentationBody, req.body);
  const created = await prisma.presentation.create({
    data: { title: body.title, lecturerId: lecturerIdOf(req) },
    select: { id: true },
  });
  res.status(201).json(await presentationDetail(created.id));
});

presentationsRouter.get('/:id', async (req, res) => {
  const { id } = parse(IdParam, req.params);
  await getOwnedPresentation(lecturerIdOf(req), id);
  res.json(await presentationDetail(id));
});

presentationsRouter.patch('/:id', async (req, res) => {
  const { id } = parse(IdParam, req.params);
  const body = parse(UpdatePresentationBody, req.body);
  await getOwnedPresentation(lecturerIdOf(req), id);
  await prisma.presentation.update({ where: { id }, data: { title: body.title } });
  res.json(await presentationDetail(id));
});

presentationsRouter.delete('/:id', async (req, res) => {
  const { id } = parse(IdParam, req.params);
  await getOwnedPresentation(lecturerIdOf(req), id);
  await assertNoActiveSession(id);
  const withImages = await prisma.slide.findMany({
    where: { presentationId: id, imageUrl: { not: null } },
    select: { imageUrl: true },
  });
  await prisma.presentation.delete({ where: { id } });
  // Best effort, after the delete succeeded: remove the slides' images from Cloudinary.
  for (const s of withImages) void destroyImage(s.imageUrl);
  res.status(204).end();
});

// --- Slides nested under a presentation ---

presentationsRouter.post('/:id/slides', async (req, res) => {
  const { id } = parse(IdParam, req.params);
  const body = parse(CreateSlideBody, req.body);
  res.status(201).json(await createSlide(lecturerIdOf(req), id, body));
});

presentationsRouter.patch('/:id/slides/reorder', async (req, res) => {
  const { id } = parse(IdParam, req.params);
  const body = parse(ReorderBody, req.body);
  const slides = await reorderSlides(lecturerIdOf(req), id, body.slideIds);
  if (!slides) throw AppError.notFound('Presentation not found');
  res.json({ slides });
});
