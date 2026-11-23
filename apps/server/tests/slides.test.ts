import request from 'supertest';
import { createApp } from '../src/app';
import { prisma } from '../src/lib/prisma';
import { auth, mockCloudinary, pollSlide, quizSlide, registerLecturer, resetDb, slideImage } from './helpers';

const app = createApp();

beforeEach(resetDb);
afterEach(() => jest.restoreAllMocks());
afterAll(() => prisma.$disconnect());

interface SlideDto {
  id: string;
  order: number;
  type: 'POLL' | 'QUIZ';
  question: string;
  imageUrl: string | null;
  options: Array<{ id: string; order: number; label: string; isCorrect: boolean }>;
}

async function setup() {
  const { token, lecturer } = await registerLecturer(app);
  const p = await request(app).post('/api/v1/presentations').set(auth(token)).send({ title: 'Loops' });
  return { token, lecturerId: lecturer.id, presentationId: p.body.id as string };
}

async function addSlide(token: string, presentationId: string, body: object) {
  const res = await request(app).post(`/api/v1/presentations/${presentationId}/slides`).set(auth(token)).send(body);
  expect(res.status).toBe(201);
  return res.body as SlideDto;
}

describe('POST /presentations/:id/slides', () => {
  it('creates poll and quiz slides with sequential order', async () => {
    const { token, presentationId } = await setup();
    const poll = await addSlide(token, presentationId, pollSlide);
    const quiz = await addSlide(token, presentationId, quizSlide);

    expect(poll).toMatchObject({ order: 0, type: 'POLL', imageUrl: null });
    expect(poll.options.every((o) => !o.isCorrect)).toBe(true);
    expect(quiz.order).toBe(1);
    expect(quiz.options.map((o) => [o.order, o.label, o.isCorrect])).toEqual([
      [0, 'for', false],
      [1, 'while', false],
      [2, 'do-while', true],
    ]);
  });

  it.each([
    ['1 option', { ...pollSlide, options: [{ label: 'Only' }] }],
    ['7 options', { ...pollSlide, options: Array.from({ length: 7 }, (_, i) => ({ label: `O${i}` })) }],
    ['quiz with no correct option', { ...quizSlide, options: [{ label: 'a' }, { label: 'b' }] }],
    [
      'quiz with two correct options',
      { ...quizSlide, options: [{ label: 'a', isCorrect: true }, { label: 'b', isCorrect: true }] },
    ],
    ['poll with a correct option', { ...pollSlide, options: [{ label: 'a', isCorrect: true }, { label: 'b' }] }],
    ['duplicate labels', { ...pollSlide, options: [{ label: 'Same' }, { label: 'same ' }] }],
    ['empty question', { ...pollSlide, question: '  ' }],
    ['unknown type', { ...pollSlide, type: 'WORD_CLOUD' }],
    ['http image url', { ...pollSlide, imageUrl: 'http://example.com/a.png' }],
  ])('rejects %s', async (_name, body) => {
    const { token, presentationId } = await setup();
    const res = await request(app).post(`/api/v1/presentations/${presentationId}/slides`).set(auth(token)).send(body);
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  it("accepts an image uploaded to the lecturer's folder", async () => {
    mockCloudinary();
    const { token, lecturerId, presentationId } = await setup();
    const slide = await addSlide(token, presentationId, { ...pollSlide, imageUrl: slideImage(lecturerId) });
    expect(slide.imageUrl).toBe(slideImage(lecturerId));
  });
});

describe('PATCH /slides/:id', () => {
  it('updates the question and keeps option ids that are sent back', async () => {
    const { token, presentationId } = await setup();
    const slide = await addSlide(token, presentationId, pollSlide);
    const [yes, no] = slide.options;

    const res = await request(app)
      .patch(`/api/v1/slides/${slide.id}`)
      .set(auth(token))
      .send({
        question: 'Is String primitive in Java?',
        options: [
          { id: no!.id, label: 'No' },
          { id: yes!.id, label: 'Yes!' },
          { label: 'Not sure' },
        ],
      });
    expect(res.status).toBe(200);
    const updated = res.body as SlideDto;
    expect(updated.question).toBe('Is String primitive in Java?');
    expect(updated.options.map((o) => [o.id, o.label])).toEqual([
      [no!.id, 'No'],
      [yes!.id, 'Yes!'],
      [expect.any(String), 'Not sure'],
    ]);
    // "Depends on the language" was removed
    expect(await prisma.option.count({ where: { slideId: slide.id } })).toBe(3);
  });

  it('changes a poll into a quiz when a correct option is provided', async () => {
    const { token, presentationId } = await setup();
    const slide = await addSlide(token, presentationId, pollSlide);
    const opts = slide.options.map((o, i) => ({ id: o.id, label: o.label, isCorrect: i === 1 }));
    const res = await request(app).patch(`/api/v1/slides/${slide.id}`).set(auth(token)).send({ type: 'QUIZ', options: opts });
    expect(res.status).toBe(200);
    expect(res.body.type).toBe('QUIZ');
    expect(res.body.options[1].isCorrect).toBe(true);
  });

  it('validates the merged result (quiz type without a correct option)', async () => {
    const { token, presentationId } = await setup();
    const slide = await addSlide(token, presentationId, pollSlide);
    const res = await request(app).patch(`/api/v1/slides/${slide.id}`).set(auth(token)).send({ type: 'QUIZ' });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  it('rejects option ids from another slide', async () => {
    const { token, presentationId } = await setup();
    const a = await addSlide(token, presentationId, pollSlide);
    const b = await addSlide(token, presentationId, quizSlide);
    const res = await request(app)
      .patch(`/api/v1/slides/${a.id}`)
      .set(auth(token))
      .send({ options: [{ id: b.options[0]!.id, label: 'stolen' }, { label: 'x' }] });
    expect(res.status).toBe(400);
  });

  it('sets and clears the image url', async () => {
    mockCloudinary();
    const { token, lecturerId, presentationId } = await setup();
    const slide = await addSlide(token, presentationId, pollSlide);
    const url = slideImage(lecturerId);
    let res = await request(app).patch(`/api/v1/slides/${slide.id}`).set(auth(token)).send({ imageUrl: url });
    expect(res.body.imageUrl).toBe(url);
    res = await request(app).patch(`/api/v1/slides/${slide.id}`).set(auth(token)).send({ imageUrl: null });
    expect(res.body.imageUrl).toBeNull();
  });

  it('rejects an empty body', async () => {
    const { token, presentationId } = await setup();
    const slide = await addSlide(token, presentationId, pollSlide);
    const res = await request(app).patch(`/api/v1/slides/${slide.id}`).set(auth(token)).send({});
    expect(res.status).toBe(400);
  });

  it("returns 404 for another lecturer's slide", async () => {
    const { token, presentationId } = await setup();
    const slide = await addSlide(token, presentationId, pollSlide);
    const other = await registerLecturer(app);
    const patch = await request(app).patch(`/api/v1/slides/${slide.id}`).set(auth(other.token)).send({ question: 'x' });
    const del = await request(app).delete(`/api/v1/slides/${slide.id}`).set(auth(other.token));
    expect(patch.status).toBe(404);
    expect(del.status).toBe(404);
  });
});

describe('DELETE /slides/:id and reorder', () => {
  it('deletes a slide and keeps order contiguous', async () => {
    const { token, presentationId } = await setup();
    const s0 = await addSlide(token, presentationId, pollSlide);
    const s1 = await addSlide(token, presentationId, quizSlide);
    const s2 = await addSlide(token, presentationId, { ...pollSlide, question: 'Third' });

    await request(app).delete(`/api/v1/slides/${s1.id}`).set(auth(token)).expect(204);
    const detail = await request(app).get(`/api/v1/presentations/${presentationId}`).set(auth(token));
    expect(detail.body.slides.map((s: SlideDto) => [s.id, s.order])).toEqual([
      [s0.id, 0],
      [s2.id, 1],
    ]);
  });

  it('reorders slides', async () => {
    const { token, presentationId } = await setup();
    const a = await addSlide(token, presentationId, pollSlide);
    const b = await addSlide(token, presentationId, quizSlide);
    const c = await addSlide(token, presentationId, { ...pollSlide, question: 'C' });

    const res = await request(app)
      .patch(`/api/v1/presentations/${presentationId}/slides/reorder`)
      .set(auth(token))
      .send({ slideIds: [c.id, a.id, b.id] });
    expect(res.status).toBe(200);
    expect(res.body.slides.map((s: SlideDto) => [s.id, s.order])).toEqual([
      [c.id, 0],
      [a.id, 1],
      [b.id, 2],
    ]);
  });

  it.each([
    ['missing a slide', (ids: string[]) => ids.slice(0, 1)],
    ['unknown id', (ids: string[]) => [...ids.slice(0, 1), 'nope']],
    ['duplicates', (ids: string[]) => [ids[0], ids[0]]],
  ])('rejects reorder with %s', async (_name, build) => {
    const { token, presentationId } = await setup();
    const a = await addSlide(token, presentationId, pollSlide);
    const b = await addSlide(token, presentationId, quizSlide);
    const res = await request(app)
      .patch(`/api/v1/presentations/${presentationId}/slides/reorder`)
      .set(auth(token))
      .send({ slideIds: build([a.id, b.id]) });
    expect(res.status).toBe(400);
  });

  it('blocks slide edits while a session is live', async () => {
    const { token, presentationId } = await setup();
    const slide = await addSlide(token, presentationId, pollSlide);
    await prisma.session.create({ data: { presentationId, code: '654321', status: 'WAITING' } });
    const patch = await request(app).patch(`/api/v1/slides/${slide.id}`).set(auth(token)).send({ question: 'x' });
    const del = await request(app).delete(`/api/v1/slides/${slide.id}`).set(auth(token));
    expect(patch.status).toBe(409);
    expect(del.status).toBe(409);
  });
});
