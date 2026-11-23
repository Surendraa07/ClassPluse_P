import request from 'supertest';
import { createApp } from '../src/app';
import { signParams } from '../src/lib/cloudinary';
import { prisma } from '../src/lib/prisma';
import { auth, avatarImage, cloudUrl, mockCloudinary, pollSlide, registerLecturer, resetDb, slideImage } from './helpers';

const app = createApp();

beforeEach(resetDb);
afterEach(() => jest.restoreAllMocks());
afterAll(() => prisma.$disconnect());

const destroyCalls = (spy: jest.SpyInstance) =>
  spy.mock.calls.filter(([url]) => String(url).endsWith('/image/destroy')).map(([, init]) => String((init as RequestInit).body));

describe('POST /uploads/signature', () => {
  it('needs a lecturer token', async () => {
    const res = await request(app).post('/api/v1/uploads/signature').send({ kind: 'slide' });
    expect(res.status).toBe(401);
  });

  it('rejects an unknown kind', async () => {
    const { token } = await registerLecturer(app);
    const res = await request(app).post('/api/v1/uploads/signature').set(auth(token)).send({ kind: 'video' });
    expect(res.status).toBe(400);
  });

  it.each(['slide', 'avatar'] as const)('signs a %s upload into the lecturer folder', async (kind) => {
    const { token, lecturer } = await registerLecturer(app);
    const res = await request(app).post('/api/v1/uploads/signature').set(auth(token)).send({ kind });
    expect(res.status).toBe(200);
    const { params, signature, apiKey, uploadUrl, maxBytes } = res.body;
    expect(uploadUrl).toBe('https://api.cloudinary.com/v1_1/test-cloud/image/upload');
    expect(apiKey).toBe('123456789012345');
    expect(params.folder).toBe(`classpluse/${kind}s/${lecturer.id}`);
    expect(params.allowed_formats).toBe('jpg,jpeg,png,webp');
    expect(params.transformation).toMatch(/^c_limit,/);
    expect(Math.abs(params.timestamp - Date.now() / 1000)).toBeLessThan(5);
    expect(signature).toBe(signParams(params, 'test-cloudinary-secret'));
    expect(maxBytes).toBe(5 * 1024 * 1024);
    // The secret itself is never sent.
    expect(JSON.stringify(res.body)).not.toContain('test-cloudinary-secret');
  });
});

describe('slide images', () => {
  async function setup() {
    const { token, lecturer } = await registerLecturer(app);
    const p = await request(app).post('/api/v1/presentations').set(auth(token)).send({ title: 'Loops' });
    return { token, lecturerId: lecturer.id, presentationId: p.body.id as string };
  }
  const create = (token: string, presentationId: string, imageUrl: string) =>
    request(app).post(`/api/v1/presentations/${presentationId}/slides`).set(auth(token)).send({ ...pollSlide, imageUrl });

  it("rejects an image from another lecturer's folder without calling Cloudinary", async () => {
    const spy = mockCloudinary();
    const { token, presentationId } = await setup();
    const res = await create(token, presentationId, slideImage('someone-else'));
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_IMAGE');
    expect(spy).not.toHaveBeenCalled();
  });

  it.each([
    ['another site', 'https://example.com/pic.jpg'],
    ['another Cloudinary account', 'https://res.cloudinary.com/other-cloud/image/upload/v1/classpluse/slides/x/pic.jpg'],
    ['a path trick', 'https://res.cloudinary.com/test-cloud/image/upload/v1/classpluse/slides/LECTURER/../x/pic.jpg'],
  ])('rejects %s', async (_name, url) => {
    mockCloudinary();
    const { token, lecturerId, presentationId } = await setup();
    const res = await create(token, presentationId, url.replace('LECTURER', lecturerId));
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_IMAGE');
  });

  it('rejects an avatar-folder image on a slide', async () => {
    mockCloudinary();
    const { token, lecturerId, presentationId } = await setup();
    const res = await create(token, presentationId, avatarImage(lecturerId));
    expect(res.status).toBe(400);
  });

  it('rejects an image Cloudinary does not have', async () => {
    mockCloudinary({ status: 404 });
    const { token, lecturerId, presentationId } = await setup();
    const res = await create(token, presentationId, slideImage(lecturerId));
    expect(res.status).toBe(400);
    expect(res.body.error.message).toMatch(/not found/i);
  });

  it('rejects and deletes an image over 5 MB', async () => {
    const spy = mockCloudinary({ bytes: 6 * 1024 * 1024 });
    const { token, lecturerId, presentationId } = await setup();
    const res = await create(token, presentationId, slideImage(lecturerId));
    expect(res.status).toBe(400);
    expect(res.body.error.message).toMatch(/too large/i);
    expect(destroyCalls(spy)).toHaveLength(1);
  });

  it('rejects a non-image format', async () => {
    mockCloudinary({ format: 'gif' });
    const { token, lecturerId, presentationId } = await setup();
    const res = await create(token, presentationId, slideImage(lecturerId));
    expect(res.status).toBe(400);
  });

  it('answers 502 when Cloudinary is down', async () => {
    mockCloudinary({ status: 500 });
    const { token, lecturerId, presentationId } = await setup();
    const res = await create(token, presentationId, slideImage(lecturerId));
    expect(res.status).toBe(502);
    expect(res.body.error.code).toBe('UPLOAD_CHECK_FAILED');
  });

  it('deletes the old image when a slide image is replaced', async () => {
    const spy = mockCloudinary();
    const { token, lecturerId, presentationId } = await setup();
    const first = await create(token, presentationId, slideImage(lecturerId, 'one'));
    const res = await request(app)
      .patch(`/api/v1/slides/${first.body.id}`)
      .set(auth(token))
      .send({ imageUrl: slideImage(lecturerId, 'two') });
    expect(res.body.imageUrl).toBe(slideImage(lecturerId, 'two'));
    await new Promise((r) => setTimeout(r, 20));
    const destroyed = destroyCalls(spy);
    expect(destroyed).toHaveLength(1);
    expect(destroyed[0]).toContain(encodeURIComponent(`classpluse/slides/${lecturerId}/one`));
  });
});

describe('PATCH /auth/me (avatar)', () => {
  it('sets, replaces and removes the avatar', async () => {
    const spy = mockCloudinary();
    const { token, lecturer } = await registerLecturer(app);

    let res = await request(app).patch('/api/v1/auth/me').set(auth(token)).send({ avatarUrl: avatarImage(lecturer.id, 'a') });
    expect(res.status).toBe(200);
    expect(res.body.lecturer.avatarUrl).toBe(avatarImage(lecturer.id, 'a'));

    res = await request(app).get('/api/v1/auth/me').set(auth(token));
    expect(res.body.lecturer.avatarUrl).toBe(avatarImage(lecturer.id, 'a'));

    res = await request(app).patch('/api/v1/auth/me').set(auth(token)).send({ avatarUrl: avatarImage(lecturer.id, 'b') });
    expect(res.body.lecturer.avatarUrl).toBe(avatarImage(lecturer.id, 'b'));

    res = await request(app).patch('/api/v1/auth/me').set(auth(token)).send({ avatarUrl: null });
    expect(res.body.lecturer.avatarUrl).toBeNull();

    await new Promise((r) => setTimeout(r, 20));
    expect(destroyCalls(spy)).toHaveLength(2);
  });

  it('updates the name', async () => {
    const { token } = await registerLecturer(app);
    const res = await request(app).patch('/api/v1/auth/me').set(auth(token)).send({ name: '  Dr. Rai ' });
    expect(res.body.lecturer.name).toBe('Dr. Rai');
  });

  it("rejects another lecturer's avatar and a slide image", async () => {
    mockCloudinary();
    const { token, lecturer } = await registerLecturer(app);
    for (const url of [avatarImage('someone-else'), slideImage(lecturer.id), cloudUrl('elsewhere/pic')]) {
      const res = await request(app).patch('/api/v1/auth/me').set(auth(token)).send({ avatarUrl: url });
      expect(res.status).toBe(400);
    }
  });

  it('rejects an empty body and needs auth', async () => {
    const { token } = await registerLecturer(app);
    expect((await request(app).patch('/api/v1/auth/me').set(auth(token)).send({})).status).toBe(400);
    expect((await request(app).patch('/api/v1/auth/me').send({ name: 'x' })).status).toBe(401);
  });
});

describe('deleting removes images from Cloudinary', () => {
  async function presentationWithImages(n: number) {
    const { token, lecturer } = await registerLecturer(app);
    const p = await request(app).post('/api/v1/presentations').set(auth(token)).send({ title: 'Loops' });
    const slides: string[] = [];
    for (let i = 0; i < n; i++) {
      const res = await request(app)
        .post(`/api/v1/presentations/${p.body.id}/slides`)
        .set(auth(token))
        .send({ ...pollSlide, imageUrl: slideImage(lecturer.id, `img${i}`) });
      slides.push(res.body.id);
    }
    // plus one slide without an image
    await request(app).post(`/api/v1/presentations/${p.body.id}/slides`).set(auth(token)).send(pollSlide);
    return { token, lecturerId: lecturer.id, presentationId: p.body.id as string, slides };
  }

  it('deletes the image of a deleted slide', async () => {
    const spy = mockCloudinary();
    const { token, lecturerId, slides } = await presentationWithImages(1);
    const res = await request(app).delete(`/api/v1/slides/${slides[0]}`).set(auth(token));
    expect(res.status).toBe(204);
    await new Promise((r) => setTimeout(r, 20));
    const destroyed = destroyCalls(spy);
    expect(destroyed).toHaveLength(1);
    expect(destroyed[0]).toContain(encodeURIComponent(`classpluse/slides/${lecturerId}/img0`));
  });

  it('deletes every slide image of a deleted presentation', async () => {
    const spy = mockCloudinary();
    const { token, presentationId } = await presentationWithImages(2);
    const res = await request(app).delete(`/api/v1/presentations/${presentationId}`).set(auth(token));
    expect(res.status).toBe(204);
    await new Promise((r) => setTimeout(r, 20));
    expect(destroyCalls(spy)).toHaveLength(2);
  });

  it('keeps the images when the delete is refused', async () => {
    const spy = mockCloudinary();
    const { presentationId } = await presentationWithImages(1);
    const other = await registerLecturer(app);
    const res = await request(app).delete(`/api/v1/presentations/${presentationId}`).set(auth(other.token));
    expect(res.status).toBe(404);
    await new Promise((r) => setTimeout(r, 20));
    expect(destroyCalls(spy)).toHaveLength(0);
  });

  it('still deletes the slide when Cloudinary is unreachable', async () => {
    mockCloudinary();
    const { token, slides } = await presentationWithImages(1);
    jest.spyOn(global, 'fetch').mockRejectedValue(new Error('offline'));
    const res = await request(app).delete(`/api/v1/slides/${slides[0]}`).set(auth(token));
    expect(res.status).toBe(204);
  });
});
