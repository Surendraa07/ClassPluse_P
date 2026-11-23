import request from 'supertest';
import { createApp } from '../src/app';
import { prisma } from '../src/lib/prisma';
import { hashToken } from '../src/lib/tokens';
import { auth, pollSlide, quizSlide, registerLecturer, resetDb } from './helpers';

const app = createApp();

beforeEach(resetDb);
afterAll(() => prisma.$disconnect());

async function presentationWithSlides(token: string, slides = [pollSlide, quizSlide]) {
  const p = await request(app).post('/api/v1/presentations').set(auth(token)).send({ title: 'Loops' });
  for (const s of slides) {
    await request(app).post(`/api/v1/presentations/${p.body.id}/slides`).set(auth(token)).send(s).expect(201);
  }
  return p.body.id as string;
}

describe('POST /sessions', () => {
  it('creates a WAITING session with a 6-digit code', async () => {
    const { token } = await registerLecturer(app);
    const presentationId = await presentationWithSlides(token);
    const res = await request(app).post('/api/v1/sessions').set(auth(token)).send({ presentationId });
    expect(res.status).toBe(201);
    expect(res.body).toMatchObject({ sessionId: expect.any(String), status: 'WAITING', resumed: false });
    expect(res.body.code).toMatch(/^\d{6}$/);
  });

  it('resumes the active session instead of creating a second one', async () => {
    const { token } = await registerLecturer(app);
    const presentationId = await presentationWithSlides(token);
    const first = await request(app).post('/api/v1/sessions').set(auth(token)).send({ presentationId });
    const second = await request(app).post('/api/v1/sessions').set(auth(token)).send({ presentationId });
    expect(second.status).toBe(200);
    expect(second.body).toMatchObject({ sessionId: first.body.sessionId, code: first.body.code, resumed: true });
  });

  it('refuses a presentation without slides', async () => {
    const { token } = await registerLecturer(app);
    const presentationId = await presentationWithSlides(token, []);
    const res = await request(app).post('/api/v1/sessions').set(auth(token)).send({ presentationId });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('NO_SLIDES');
  });

  it("404 for someone else's presentation; 401 without auth", async () => {
    const owner = await registerLecturer(app);
    const other = await registerLecturer(app);
    const presentationId = await presentationWithSlides(owner.token);
    await request(app).post('/api/v1/sessions').set(auth(other.token)).send({ presentationId }).expect(404);
    await request(app).post('/api/v1/sessions').send({ presentationId }).expect(401);
  });
});

describe('session code uniqueness (DB level)', () => {
  it('allows a code to be reused only after the earlier session ended', async () => {
    const { token } = await registerLecturer(app);
    const a = await presentationWithSlides(token);
    const b = await presentationWithSlides(token);
    await prisma.session.create({ data: { presentationId: a, code: '111111' } });
    await expect(prisma.session.create({ data: { presentationId: b, code: '111111' } })).rejects.toThrow();
    await prisma.session.updateMany({ where: { code: '111111' }, data: { status: 'ENDED' } });
    await expect(prisma.session.create({ data: { presentationId: b, code: '111111' } })).resolves.toBeTruthy();
  });

  it('rejects codes that are not 6 digits', async () => {
    const { token } = await registerLecturer(app);
    const a = await presentationWithSlides(token);
    await expect(prisma.session.create({ data: { presentationId: a, code: '12ab56' } })).rejects.toThrow();
  });
});

describe('POST /join', () => {
  async function liveCode() {
    const { token } = await registerLecturer(app);
    const presentationId = await presentationWithSlides(token);
    const res = await request(app).post('/api/v1/sessions').set(auth(token)).send({ presentationId });
    return { token, sessionId: res.body.sessionId as string, code: res.body.code as string };
  }

  it('issues an anonymous participant token and stores only its hash', async () => {
    const { sessionId, code } = await liveCode();
    const res = await request(app).post('/api/v1/join').send({ code });
    expect(res.status).toBe(201);
    expect(res.body).toMatchObject({ sessionId, participantToken: expect.any(String), rejoined: false });
    expect(res.body.participantToken.length).toBeGreaterThanOrEqual(40);

    const participant = await prisma.participant.findFirstOrThrow({ where: { sessionId } });
    expect(participant.anonToken).toBe(hashToken(res.body.participantToken));
    expect(participant.anonToken).not.toBe(res.body.participantToken);
  });

  it('rejoins with the same token instead of creating a new participant', async () => {
    const { sessionId, code } = await liveCode();
    const first = await request(app).post('/api/v1/join').send({ code });
    const again = await request(app).post('/api/v1/join').send({ code, participantToken: first.body.participantToken });
    expect(again.status).toBe(200);
    expect(again.body).toMatchObject({ rejoined: true, participantToken: first.body.participantToken });
    expect(await prisma.participant.count({ where: { sessionId } })).toBe(1);
  });

  it('404 for an unknown code and for an ended session', async () => {
    const { sessionId, code } = await liveCode();
    const unknown = await request(app).post('/api/v1/join').send({ code: code === '000000' ? '000001' : '000000' });
    expect(unknown.status).toBe(404);
    expect(unknown.body.error.code).toBe('SESSION_NOT_FOUND');

    await prisma.session.update({ where: { id: sessionId }, data: { status: 'ENDED', endedAt: new Date() } });
    const ended = await request(app).post('/api/v1/join').send({ code });
    expect(ended.status).toBe(404);
  });

  it.each(['12345', '1234567', 'abcdef', ''])('400 for malformed code %p', async (code) => {
    const res = await request(app).post('/api/v1/join').send({ code });
    expect(res.status).toBe(400);
  });
});

describe('GET /sessions/:id and /summary', () => {
  it('returns lecturer state and an empty summary', async () => {
    const { token } = await registerLecturer(app);
    const presentationId = await presentationWithSlides(token);
    const s = await request(app).post('/api/v1/sessions').set(auth(token)).send({ presentationId });

    const state = await request(app).get(`/api/v1/sessions/${s.body.sessionId}`).set(auth(token));
    expect(state.status).toBe(200);
    expect(state.body).toMatchObject({ status: 'WAITING', code: s.body.code, totalSlides: 2, currentSlide: null, participants: 0 });

    const summary = await request(app).get(`/api/v1/sessions/${s.body.sessionId}/summary`).set(auth(token));
    expect(summary.status).toBe(200);
    expect(summary.body.slides).toHaveLength(2);
    expect(summary.body.slides[1]).toMatchObject({ type: 'QUIZ', responses: 0, percentCorrect: 0 });
    expect(summary.body.slides[0].percentCorrect).toBeNull();

    const other = await registerLecturer(app);
    await request(app).get(`/api/v1/sessions/${s.body.sessionId}/summary`).set(auth(other.token)).expect(404);
  });
});
