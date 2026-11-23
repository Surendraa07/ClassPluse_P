import request from 'supertest';
import { createApp } from '../src/app';
import { prisma } from '../src/lib/prisma';
import { auth, pollSlide, quizSlide, registerLecturer, resetDb } from './helpers';

const app = createApp();

beforeEach(resetDb);
afterAll(() => prisma.$disconnect());

async function createPresentation(token: string, title = 'POP Lecture 4: Loops') {
  const res = await request(app).post('/api/v1/presentations').set(auth(token)).send({ title });
  expect(res.status).toBe(201);
  return res.body as { id: string; title: string; slides: unknown[] };
}

describe('presentations', () => {
  it('requires authentication', async () => {
    const res = await request(app).get('/api/v1/presentations');
    expect(res.status).toBe(401);
  });

  it('creates, lists, reads, renames and deletes', async () => {
    const { token } = await registerLecturer(app);
    const created = await createPresentation(token);
    expect(created).toMatchObject({ title: 'POP Lecture 4: Loops', slides: [] });

    await request(app).post(`/api/v1/presentations/${created.id}/slides`).set(auth(token)).send(pollSlide).expect(201);

    const list = await request(app).get('/api/v1/presentations').set(auth(token));
    expect(list.status).toBe(200);
    expect(list.body).toHaveLength(1);
    expect(list.body[0]).toMatchObject({ id: created.id, slideCount: 1 });

    const detail = await request(app).get(`/api/v1/presentations/${created.id}`).set(auth(token));
    expect(detail.status).toBe(200);
    expect(detail.body.slides).toHaveLength(1);
    expect(detail.body.slides[0].options.map((o: { label: string }) => o.label)).toEqual([
      'Yes',
      'No',
      'Depends on the language',
    ]);

    const renamed = await request(app)
      .patch(`/api/v1/presentations/${created.id}`)
      .set(auth(token))
      .send({ title: '  Loops v2  ' });
    expect(renamed.status).toBe(200);
    expect(renamed.body.title).toBe('Loops v2');

    await request(app).delete(`/api/v1/presentations/${created.id}`).set(auth(token)).expect(204);
    await request(app).get(`/api/v1/presentations/${created.id}`).set(auth(token)).expect(404);
    expect(await prisma.slide.count()).toBe(0); // cascade
  });

  it('lists most recently updated first', async () => {
    const { token } = await registerLecturer(app);
    const a = await createPresentation(token, 'A');
    const b = await createPresentation(token, 'B');
    await request(app).post(`/api/v1/presentations/${a.id}/slides`).set(auth(token)).send(quizSlide).expect(201);
    const list = await request(app).get('/api/v1/presentations').set(auth(token));
    expect(list.body.map((p: { id: string }) => p.id)).toEqual([a.id, b.id]);
  });

  it('validates the title', async () => {
    const { token } = await registerLecturer(app);
    const res = await request(app).post('/api/v1/presentations').set(auth(token)).send({ title: '   ' });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  it("hides other lecturers' presentations (404, not 403)", async () => {
    const owner = await registerLecturer(app);
    const intruder = await registerLecturer(app);
    const p = await createPresentation(owner.token);

    const list = await request(app).get('/api/v1/presentations').set(auth(intruder.token));
    expect(list.body).toEqual([]);

    for (const r of [
      request(app).get(`/api/v1/presentations/${p.id}`),
      request(app).patch(`/api/v1/presentations/${p.id}`).send({ title: 'hacked' }),
      request(app).delete(`/api/v1/presentations/${p.id}`),
      request(app).post(`/api/v1/presentations/${p.id}/slides`).send(pollSlide),
      request(app).patch(`/api/v1/presentations/${p.id}/slides/reorder`).send({ slideIds: ['x'] }),
    ]) {
      const res = await r.set(auth(intruder.token));
      expect(res.status).toBe(404);
    }
    const still = await prisma.presentation.findUniqueOrThrow({ where: { id: p.id } });
    expect(still.title).toBe('POP Lecture 4: Loops');
  });

  it('blocks deleting/editing while a session is active', async () => {
    const { token } = await registerLecturer(app);
    const p = await createPresentation(token);
    await prisma.session.create({ data: { presentationId: p.id, code: '123456', status: 'LIVE' } });

    const del = await request(app).delete(`/api/v1/presentations/${p.id}`).set(auth(token));
    expect(del.status).toBe(409);
    expect(del.body.error.code).toBe('SESSION_ACTIVE');

    const add = await request(app).post(`/api/v1/presentations/${p.id}/slides`).set(auth(token)).send(pollSlide);
    expect(add.status).toBe(409);
  });
});
