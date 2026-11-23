import jwt, { type SignOptions } from 'jsonwebtoken';
import { env } from '../config/env';

export interface LecturerTokenPayload {
  sub: string;
  typ: 'lecturer';
}

export function signLecturerToken(lecturerId: string): string {
  const payload: LecturerTokenPayload = { sub: lecturerId, typ: 'lecturer' };
  return jwt.sign(payload, env.JWT_SECRET, {
    expiresIn: env.JWT_EXPIRES_IN as SignOptions['expiresIn'],
    algorithm: 'HS256',
  });
}

/** Returns the lecturer id, or null if the token is invalid/expired/not a lecturer token. */
export function verifyLecturerToken(token: string): string | null {
  try {
    const decoded = jwt.verify(token, env.JWT_SECRET, { algorithms: ['HS256'] });
    if (typeof decoded === 'object' && decoded.typ === 'lecturer' && typeof decoded.sub === 'string') {
      return decoded.sub;
    }
    return null;
  } catch {
    return null;
  }
}
