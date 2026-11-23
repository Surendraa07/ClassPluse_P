import rateLimit from 'express-rate-limit';
import { env } from '../config/env';

const tooMany = (message: string) => ({ error: { code: 'RATE_LIMITED', message } });

export const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: env.AUTH_RATE_LIMIT,
  standardHeaders: 'draft-8',
  legacyHeaders: false,
  message: tooMany('Too many attempts, please try again later'),
});

/**
 * Generous because a whole class often shares one school Wi-Fi IP. 1,000,000 possible codes
 * keep brute force impractical at this rate.
 */
export const joinLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: env.JOIN_RATE_LIMIT,
  standardHeaders: 'draft-8',
  legacyHeaders: false,
  message: tooMany('Too many join attempts, please wait a minute'),
});

/** Upload signatures: plenty for building a deck, stops a leaked token from flooding Cloudinary. */
export const uploadLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: 30,
  standardHeaders: 'draft-8',
  legacyHeaders: false,
  message: tooMany('Too many uploads, please wait a minute'),
});
