import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { env } from '../../config/env';
import { destroyImage, verifyUploadedImage } from '../../lib/cloudinary';
import { AppError } from '../../lib/errors';
import { signLecturerToken } from '../../lib/jwt';
import { prisma } from '../../lib/prisma';
import { parse } from '../../lib/validate';
import { lecturerIdOf, requireLecturer } from '../../middleware/auth';
import { authLimiter } from '../../middleware/rateLimit';
import { LoginBody, RegisterBody, UpdateMeBody } from './auth.schemas';

const publicLecturer = { id: true, name: true, email: true, avatarUrl: true, createdAt: true } as const;

// Used to keep login timing similar whether or not the email exists.
const DUMMY_HASH = bcrypt.hashSync('dummy-password-for-timing', 4);

export const authRouter = Router();

authRouter.post('/register', authLimiter, async (req, res) => {
  const body = parse(RegisterBody, req.body);
  const existing = await prisma.lecturer.findUnique({ where: { email: body.email }, select: { id: true } });
  if (existing) throw AppError.conflict('An account with this email already exists');

  const passwordHash = await bcrypt.hash(body.password, env.BCRYPT_ROUNDS);
  const lecturer = await prisma.lecturer.create({
    data: { name: body.name, email: body.email, passwordHash },
    select: publicLecturer,
  });
  res.status(201).json({ token: signLecturerToken(lecturer.id), lecturer });
});

authRouter.post('/login', authLimiter, async (req, res) => {
  const body = parse(LoginBody, req.body);
  const lecturer = await prisma.lecturer.findUnique({ where: { email: body.email } });
  const ok = await bcrypt.compare(body.password, lecturer?.passwordHash ?? DUMMY_HASH);
  if (!lecturer || !ok) {
    throw new AppError(401, 'INVALID_CREDENTIALS', 'Email or password is incorrect');
  }
  const { passwordHash: _omit, ...publicData } = lecturer;
  res.json({ token: signLecturerToken(lecturer.id), lecturer: publicData });
});

authRouter.get('/me', requireLecturer, async (req, res) => {
  const lecturer = await prisma.lecturer.findUnique({ where: { id: lecturerIdOf(req) }, select: publicLecturer });
  if (!lecturer) throw AppError.unauthorized();
  res.json({ lecturer });
});

/** Update the lecturer's name and/or avatar (avatarUrl from a signed upload, or null to remove). */
authRouter.patch('/me', requireLecturer, async (req, res) => {
  const body = parse(UpdateMeBody, req.body);
  const id = lecturerIdOf(req);
  const current = await prisma.lecturer.findUnique({ where: { id }, select: { avatarUrl: true } });
  if (!current) throw AppError.unauthorized();

  let avatarUrl = body.avatarUrl;
  if (avatarUrl && avatarUrl !== current.avatarUrl) avatarUrl = await verifyUploadedImage(avatarUrl, 'avatar', id);

  const lecturer = await prisma.lecturer.update({
    where: { id },
    data: {
      ...(body.name !== undefined ? { name: body.name } : {}),
      ...(avatarUrl !== undefined ? { avatarUrl } : {}),
    },
    select: publicLecturer,
  });
  if (avatarUrl !== undefined && current.avatarUrl && current.avatarUrl !== avatarUrl) void destroyImage(current.avatarUrl);
  res.json({ lecturer });
});
