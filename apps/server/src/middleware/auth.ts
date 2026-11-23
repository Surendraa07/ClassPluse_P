import type { Request, RequestHandler } from 'express';
import { AppError } from '../lib/errors';
import { verifyLecturerToken } from '../lib/jwt';
import { prisma } from '../lib/prisma';

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      lecturerId?: string;
    }
  }
}

export function bearerToken(header: string | undefined): string | null {
  if (!header) return null;
  const [scheme, token] = header.split(' ');
  return scheme?.toLowerCase() === 'bearer' && token ? token : null;
}

/** Requires a valid lecturer JWT whose lecturer still exists. */
export const requireLecturer: RequestHandler = async (req, _res, next) => {
  const token = bearerToken(req.headers.authorization);
  const lecturerId = token ? verifyLecturerToken(token) : null;
  if (!lecturerId) throw AppError.unauthorized();
  const exists = await prisma.lecturer.findUnique({ where: { id: lecturerId }, select: { id: true } });
  if (!exists) throw AppError.unauthorized();
  req.lecturerId = lecturerId;
  next();
};

export function lecturerIdOf(req: Request): string {
  if (!req.lecturerId) throw AppError.unauthorized();
  return req.lecturerId;
}
