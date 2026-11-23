import { Router } from 'express';
import { IdParam, parse } from '../../lib/validate';
import { lecturerIdOf, requireLecturer } from '../../middleware/auth';
import { UpdateSlideBody } from './slide.schemas';
import { deleteSlide, updateSlide } from './slide.service';

export const slidesRouter = Router();
slidesRouter.use(requireLecturer);

slidesRouter.patch('/:id', async (req, res) => {
  const { id } = parse(IdParam, req.params);
  const body = parse(UpdateSlideBody, req.body);
  res.json(await updateSlide(lecturerIdOf(req), id, body));
});

slidesRouter.delete('/:id', async (req, res) => {
  const { id } = parse(IdParam, req.params);
  await deleteSlide(lecturerIdOf(req), id);
  res.status(204).end();
});
