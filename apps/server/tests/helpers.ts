import request from 'supertest';
import type { Express } from 'express';
import { prisma } from '../src/lib/prisma';

/** Wipes every table in the test database. */
export async function resetDb() {
  await prisma.$executeRawUnsafe(
    'TRUNCATE "PulseState", "Response", "Participant", "Session", "Option", "Slide", "Presentation", "Lecturer" RESTART IDENTITY CASCADE',
  );
}

let counter = 0;

export async function registerLecturer(app: Express, overrides: Partial<{ name: string; email: string; password: string }> = {}) {
  counter += 1;
  const body = {
    name: overrides.name ?? `Lecturer ${counter}`,
    email: overrides.email ?? `lecturer${counter}-${Date.now()}@example.com`,
    password: overrides.password ?? 'Password123!',
  };
  const res = await request(app).post('/api/v1/auth/register').send(body);
  if (res.status !== 201) throw new Error(`register failed: ${res.status} ${JSON.stringify(res.body)}`);
  return { token: res.body.token as string, lecturer: res.body.lecturer as { id: string; email: string }, password: body.password };
}

export const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

export const pollSlide = {
  type: 'POLL',
  question: 'Is a string a primitive type?',
  options: [{ label: 'Yes' }, { label: 'No' }, { label: 'Depends on the language' }],
};

export const quizSlide = {
  type: 'QUIZ',
  question: 'Which loop always runs at least once?',
  options: [{ label: 'for' }, { label: 'while' }, { label: 'do-while', isCorrect: true }],
};

/** A delivery URL in the test Cloudinary account (see setup-env.ts). */
export const cloudUrl = (publicId: string, ext = 'jpg') =>
  `https://res.cloudinary.com/test-cloud/image/upload/v1700000000/${publicId}.${ext}`;

export const slideImage = (lecturerId: string, name = 'pic') => cloudUrl(`classpluse/slides/${lecturerId}/${name}`);
export const avatarImage = (lecturerId: string, name = 'me') => cloudUrl(`classpluse/avatars/${lecturerId}/${name}`);

/**
 * Stubs fetch for the Cloudinary Admin API lookup and destroy calls.
 * `lookup` controls what the resource lookup answers.
 */
export function mockCloudinary(lookup: { status?: number; bytes?: number; format?: string } = {}) {
  return jest.spyOn(global, 'fetch').mockImplementation(async (input) => {
    const url = String(input);
    const marker = '/resources/image/upload/';
    if (url.includes(marker)) {
      if (lookup.status && lookup.status !== 200) return new Response('{}', { status: lookup.status });
      const publicId = decodeURIComponent(url.split(marker)[1]!);
      const format = lookup.format ?? 'jpg';
      return new Response(
        JSON.stringify({ public_id: publicId, format, bytes: lookup.bytes ?? 120_000, secure_url: cloudUrl(publicId, format) }),
        { status: 200, headers: { 'content-type': 'application/json' } },
      );
    }
    if (url.endsWith('/image/destroy')) return new Response('{"result":"ok"}', { status: 200 });
    throw new Error(`unexpected fetch: ${url}`);
  });
}
