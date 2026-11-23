// Cloudinary signed uploads.
//
// Flow: the app asks POST /uploads/signature for a short-lived signature, uploads the file
// straight to Cloudinary with it, then saves the returned secure_url on the lecturer/slide.
// The API secret never leaves the server. The signature pins the folder (per lecturer),
// the allowed image formats and a resize-on-upload transformation; when a URL is saved we
// check it points into that lecturer's folder and ask Cloudinary for the real size/format.
import crypto from 'node:crypto';
import { env } from '../config/env';
import { AppError } from './errors';
import { logger } from './logger';

export type UploadKind = 'avatar' | 'slide';

export const ALLOWED_FORMATS = ['jpg', 'jpeg', 'png', 'webp'] as const;
/** Largest stored image we accept (after Cloudinary's resize). */
export const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
/** Cloudinary rejects signatures older than 1 hour; we tell the client to finish within 10 min. */
export const SIGNATURE_TTL_SECONDS = 10 * 60;

const TRANSFORMATION: Record<UploadKind, string> = {
  avatar: 'c_limit,w_512,h_512',
  slide: 'c_limit,w_1600,h_1600',
};

export function cloudinaryConfigured(): boolean {
  return Boolean(env.CLOUDINARY_CLOUD_NAME && env.CLOUDINARY_API_KEY && env.CLOUDINARY_API_SECRET);
}

function assertConfigured() {
  if (!cloudinaryConfigured()) {
    throw new AppError(503, 'UPLOADS_DISABLED', 'Image uploads are not set up on this server');
  }
}

/** Cloudinary's signature: sorted `key=value` pairs joined with `&`, plus the secret, SHA-1. */
export function signParams(params: Record<string, string | number>, secret = env.CLOUDINARY_API_SECRET): string {
  const toSign = Object.keys(params)
    .filter((k) => params[k] !== '' && params[k] !== undefined)
    .sort()
    .map((k) => `${k}=${params[k]}`)
    .join('&');
  return crypto.createHash('sha1').update(toSign + secret).digest('hex');
}

export function uploadFolder(kind: UploadKind, lecturerId: string): string {
  return `${env.CLOUDINARY_FOLDER}/${kind === 'avatar' ? 'avatars' : 'slides'}/${lecturerId}`;
}

export function createUploadSignature(kind: UploadKind, lecturerId: string) {
  assertConfigured();
  const timestamp = Math.floor(Date.now() / 1000);
  // Every field the client sends (except file, api_key) must be in the signed set.
  const params = {
    allowed_formats: ALLOWED_FORMATS.join(','),
    folder: uploadFolder(kind, lecturerId),
    timestamp,
    transformation: TRANSFORMATION[kind],
  };
  return {
    uploadUrl: `https://api.cloudinary.com/v1_1/${env.CLOUDINARY_CLOUD_NAME}/image/upload`,
    apiKey: env.CLOUDINARY_API_KEY,
    signature: signParams(params),
    params,
    maxBytes: MAX_IMAGE_BYTES,
    expiresAt: new Date((timestamp + SIGNATURE_TTL_SECONDS) * 1000).toISOString(),
  };
}

/**
 * Pulls the public_id out of one of our delivery URLs, or null if the URL isn't ours:
 * https://res.cloudinary.com/<cloud>/image/upload/v123/<public_id>.<ext>
 */
export function publicIdFromUrl(url: string): { publicId: string; format: string } | null {
  let u: URL;
  try {
    u = new URL(url);
  } catch {
    return null;
  }
  if (u.protocol !== 'https:' || u.hostname !== 'res.cloudinary.com' || u.search || u.hash) return null;
  const prefix = `/${env.CLOUDINARY_CLOUD_NAME}/image/upload/`;
  if (!env.CLOUDINARY_CLOUD_NAME || !u.pathname.startsWith(prefix)) return null;
  const rest = u.pathname.slice(prefix.length).replace(/^v\d+\//, '');
  const m = /^([A-Za-z0-9_\-/]+)\.([a-z0-9]+)$/.exec(rest);
  if (!m || rest.includes('..')) return null;
  return { publicId: m[1]!, format: m[2]! };
}

const adminAuth = () =>
  'Basic ' + Buffer.from(`${env.CLOUDINARY_API_KEY}:${env.CLOUDINARY_API_SECRET}`).toString('base64');

const invalidImage = (message: string) => new AppError(400, 'INVALID_IMAGE', message);

/**
 * Checks that `url` is an image this lecturer uploaded through a signature of this kind:
 * right cloud, right folder, allowed format, under the size limit. Returns the normalised URL.
 */
export async function verifyUploadedImage(url: string, kind: UploadKind, lecturerId: string): Promise<string> {
  assertConfigured();
  const parsed = publicIdFromUrl(url);
  if (!parsed) throw invalidImage('Image must be uploaded through ClassPluse');
  if (!parsed.publicId.startsWith(`${uploadFolder(kind, lecturerId)}/`)) {
    throw invalidImage('Image must be uploaded through ClassPluse');
  }

  let res: Response;
  try {
    res = await fetch(
      `https://api.cloudinary.com/v1_1/${env.CLOUDINARY_CLOUD_NAME}/resources/image/upload/${parsed.publicId
        .split('/')
        .map(encodeURIComponent)
        .join('/')}`,
      { headers: { Authorization: adminAuth() }, signal: AbortSignal.timeout(15000) },
    );
  } catch (err) {
    logger.warn({ err }, 'cloudinary lookup failed');
    throw new AppError(502, 'UPLOAD_CHECK_FAILED', "Couldn't check the image, please try again");
  }
  if (res.status === 404) throw invalidImage('Image not found, please upload it again');
  if (!res.ok) {
    logger.warn({ status: res.status }, 'cloudinary lookup error');
    throw new AppError(502, 'UPLOAD_CHECK_FAILED', "Couldn't check the image, please try again");
  }
  const info = (await res.json()) as { bytes?: number; format?: string; secure_url?: string };
  if (!info.format || !(ALLOWED_FORMATS as readonly string[]).includes(info.format)) {
    void destroyImage(url);
    throw invalidImage('Only JPG, PNG or WebP images are allowed');
  }
  if (typeof info.bytes !== 'number' || info.bytes > MAX_IMAGE_BYTES) {
    void destroyImage(url);
    throw invalidImage('Image is too large (max 5 MB)');
  }
  return info.secure_url ?? url;
}

/** Best-effort delete of an image we own (e.g. a replaced avatar). Never throws. */
export async function destroyImage(url: string | null | undefined): Promise<void> {
  if (!url || !cloudinaryConfigured()) return;
  const parsed = publicIdFromUrl(url);
  if (!parsed || !parsed.publicId.startsWith(`${env.CLOUDINARY_FOLDER}/`)) return;
  try {
    const timestamp = Math.floor(Date.now() / 1000);
    const body = new URLSearchParams({
      public_id: parsed.publicId,
      timestamp: String(timestamp),
      api_key: env.CLOUDINARY_API_KEY,
      signature: signParams({ public_id: parsed.publicId, timestamp }),
    });
    await fetch(`https://api.cloudinary.com/v1_1/${env.CLOUDINARY_CLOUD_NAME}/image/destroy`, {
      method: 'POST',
      body,
      signal: AbortSignal.timeout(15000),
    });
  } catch (err) {
    logger.warn({ err }, 'cloudinary destroy failed');
  }
}
