import crypto from 'node:crypto';

/** Random, URL-safe participant token (256 bits). Only its SHA-256 hash is stored. */
export function generateParticipantToken(): string {
  return crypto.randomBytes(32).toString('base64url');
}

export function hashToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}

/** 6-digit numeric code, may start with 0. */
export function generateSessionCode(): string {
  return crypto.randomInt(0, 1_000_000).toString().padStart(6, '0');
}
