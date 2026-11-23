import request from 'supertest';
import { prisma } from '../src/lib/prisma';
import { auth, pollSlide, quizSlide, registerLecturer, resetDb } from './helpers';
import { sleep, startServer, TestClient } from './socket-helpers';

let server: Awaited<ReturnType<typeof startServer>>;
const clients: TestClient[] = [];

beforeAll(async () => {
  server = await startServer();
});
beforeEach(resetDb);
afterEach(() => {
  clients.splice(0).forEach((c) => c.close());
});
afterAll(async () => {
  await server.close();
  await prisma.$disconnect();
});

async function track(p: Promise<TestClient>) {
  const c = await p;
  clients.push(c);
  return c;
}

async function setupSession() {
  const { token } = await registerLecturer(server.app);
  const p = await request(server.app).post('/api/v1/presentations').set(auth(token)).send({ title: 'Loops' });
  for (const s of [pollSlide, quizSlide]) {
    await request(server.app).post(`/api/v1/presentations/${p.body.id}/slides`).set(auth(token)).send(s).expect(201);
  }
  const s = await request(server.app).post('/api/v1/sessions').set(auth(token)).send({ presentationId: p.body.id });
  return { token, sessionId: s.body.sessionId as string, code: s.body.code as string };
}

async function joinStudent(code: string) {
  const res = await request(server.app).post('/api/v1/join').send({ code }).expect(201);
  const token = res.body.participantToken as string;
  return { token, client: await track(TestClient.connect(server.url, { participantToken: token })) };
}

describe('realtime full flow', () => {
  it('lecturer starts → 3 students join → answer → pulse → results update → end', async () => {
    const { token, sessionId, code } = await setupSession();
    const lecturer = await track(TestClient.connect(server.url, { token, sessionId }));

    const waiting = await lecturer.waitFor('session:state');
    expect(waiting).toMatchObject({ status: 'WAITING', code, currentSlide: null, totalSlides: 2 });

    // --- 3 students join; lecturer sees the joined count rise ---
    const s1 = await joinStudent(code);
    const s2 = await joinStudent(code);
    const s3 = await joinStudent(code);
    await lecturer.waitFor('participants:count', (p) => p.count === 3);
    const studentWaiting = await s3.client.waitFor('session:state');
    expect(studentWaiting.status).toBe('WAITING');
    expect(studentWaiting.code).toBeUndefined(); // lecturer-only fields hidden

    // --- start: everyone gets slide 1; students don't see isCorrect ---
    expect(await lecturer.emit('session:start')).toEqual({ ok: true });
    const live = await s1.client.waitFor('session:state', (p) => p.status === 'LIVE');
    expect(live.currentSlide).toMatchObject({ index: 0, type: 'POLL', question: pollSlide.question });
    const lecturerLive = await lecturer.waitFor('session:state', (p) => p.status === 'LIVE');
    expect(lecturerLive.currentSlide.options[0]).toHaveProperty('isCorrect');
    expect(live.currentSlide.options[0]).not.toHaveProperty('isCorrect');

    const [yes, no, depends] = live.currentSlide.options as Array<{ id: string }>;
    const slideId = live.currentSlide.id as string;

    // --- answers: 2× Yes, 1× No → lecturer gets aggregated counts only ---
    s1.client.clear();
    s2.client.clear();
    s3.client.clear();
    expect(await s1.client.emit('answer:submit', { slideId, optionId: yes!.id })).toMatchObject({ ok: true });
    expect(await s2.client.emit('answer:submit', { slideId, optionId: yes!.id })).toMatchObject({ ok: true });
    expect(await s3.client.emit('answer:submit', { slideId, optionId: no!.id })).toMatchObject({ ok: true });

    const results = await lecturer.waitFor('results:update', (p) => p.slideId === slideId && p.answered === 3);
    expect(results.counts).toEqual([
      { optionId: yes!.id, count: 2 },
      { optionId: no!.id, count: 1 },
      { optionId: depends!.id, count: 0 },
    ]);
    expect(JSON.stringify(results)).not.toMatch(/participant[A-Za-z]*Id/); // never who chose what

    // Results are hidden from students while the toggle is off.
    await sleep(400);
    expect(s1.client.received('results:update')).toHaveLength(0);

    // --- changing an answer upserts (count stays 3) ---
    await s3.client.emit('answer:submit', { slideId, optionId: depends!.id });
    const changed = await lecturer.waitFor('results:update', (p) => p.counts[2].count === 1 && p.counts[1].count === 0);
    expect(changed.answered).toBe(3);

    // --- toggle results on → students receive them ---
    expect(await lecturer.emit('results:toggle', { show: true })).toEqual({ ok: true, show: true });
    await s2.client.waitFor('session:state', (p) => p.showResultsToStudents === true);
    const studentResults = await s2.client.waitFor('results:update', (p) => p.answered === 3);
    expect(studentResults.counts[0].count).toBe(2);

    // --- pulse: 2 following, 1 lost; spam taps don't inflate the totals ---
    await s1.client.emit('pulse:set', { state: 'FOLLOWING' });
    await s2.client.emit('pulse:set', { state: 'FOLLOWING' });
    for (let i = 0; i < 5; i++) await s3.client.emit('pulse:set', { state: 'LOST' });
    await lecturer.waitFor('pulse:update', (p) => p.following === 2 && p.lost === 1 && p.total === 3);
    await s3.client.emit('pulse:set', { state: 'FOLLOWING' });
    await lecturer.waitFor('pulse:update', (p) => p.following === 3 && p.lost === 0 && p.total === 3);
    expect(s1.client.received('pulse:update')).toHaveLength(0); // lecturer-only

    // --- next slide: old question closes ---
    expect(await lecturer.emit('slide:next')).toEqual({ ok: true });
    const quiz = await s1.client.waitFor('session:state', (p) => p.currentSlide?.index === 1);
    const late = await s2.client.emit('answer:submit', { slideId, optionId: no!.id });
    expect(late).toEqual({ ok: false, error: { code: 'SLIDE_CLOSED', message: expect.any(String) } });

    const doWhile = quiz.currentSlide.options[2].id as string;
    await s1.client.emit('answer:submit', { slideId: quiz.currentSlide.id, optionId: doWhile });
    await s2.client.emit('answer:submit', { slideId: quiz.currentSlide.id, optionId: quiz.currentSlide.options[0].id });
    await lecturer.waitFor('results:update', (p) => p.slideId === quiz.currentSlide.id && p.answered === 2);

    expect(await lecturer.emit('slide:next')).toMatchObject({ ok: false, error: { code: 'NO_MORE_SLIDES' } });

    // --- end ---
    expect(await lecturer.emit('session:end')).toEqual({ ok: true });
    await s1.client.waitFor('session:ended', (p) => p.sessionId === sessionId);
    await lecturer.waitFor('session:ended');

    // Code no longer works; students can't reconnect.
    await request(server.app).post('/api/v1/join').send({ code }).expect(404);
    await expect(TestClient.connect(server.url, { participantToken: s1.token })).rejects.toThrow(/ended/i);

    // --- summary ---
    const summary = await request(server.app).get(`/api/v1/sessions/${sessionId}/summary`).set(auth(token));
    expect(summary.body).toMatchObject({ status: 'ENDED', participants: 3, pulse: { following: 3, lost: 0, total: 3 } });
    const [poll, quizSummary] = summary.body.slides;
    expect(poll.responses).toBe(3);
    expect(poll.options.map((o: { count: number; percent: number }) => [o.count, o.percent])).toEqual([
      [2, 66.7],
      [0, 0],
      [1, 33.3],
    ]);
    expect(quizSummary).toMatchObject({ responses: 2, percentCorrect: 50 });
  });
});

describe('realtime auth, reconnects and validation', () => {
  it('rejects bad credentials and other lecturers', async () => {
    const { sessionId } = await setupSession();
    const other = await registerLecturer(server.app);
    await expect(TestClient.connect(server.url, {})).rejects.toThrow(/credentials/i);
    await expect(TestClient.connect(server.url, { participantToken: 'x'.repeat(43) })).rejects.toThrow(/invalid/i);
    await expect(TestClient.connect(server.url, { token: 'nope', sessionId })).rejects.toThrow(/invalid/i);
    await expect(TestClient.connect(server.url, { token: other.token, sessionId })).rejects.toThrow(/not found/i);
  });

  it('students cannot send lecturer events, and payloads are validated', async () => {
    const { token, sessionId, code } = await setupSession();
    const lecturer = await track(TestClient.connect(server.url, { token, sessionId }));
    const s = await joinStudent(code);

    expect(await s.client.emit('session:end')).toMatchObject({ ok: false, error: { code: 'FORBIDDEN' } });
    expect(await lecturer.emit('answer:submit', { slideId: 'a', optionId: 'b' })).toMatchObject({
      ok: false,
      error: { code: 'FORBIDDEN' },
    });

    // Not live yet
    expect(await s.client.emit('answer:submit', { slideId: 'a', optionId: 'b' })).toMatchObject({
      ok: false,
      error: { code: 'SESSION_NOT_LIVE' },
    });
    // Pulse is allowed in the waiting room
    expect(await s.client.emit('pulse:set', { state: 'LOST' })).toEqual({ ok: true, state: 'LOST' });

    expect(await s.client.emit('pulse:set', { state: 'BORED' })).toMatchObject({ ok: false, error: { code: 'VALIDATION_ERROR' } });
    expect(await lecturer.emit('results:toggle', { show: 'yes' })).toMatchObject({
      ok: false,
      error: { code: 'VALIDATION_ERROR' },
    });

    await lecturer.emit('session:start');
    const state = await s.client.waitFor('session:state', (p) => p.status === 'LIVE');
    const otherSlideOption = (await lecturer.waitFor('session:state', (p) => p.status === 'LIVE')).currentSlide.options[0].id;
    expect(otherSlideOption).toBeTruthy();
    expect(await s.client.emit('answer:submit', { slideId: state.currentSlide.id, optionId: 'not-an-option' })).toMatchObject({
      ok: false,
      error: { code: 'INVALID_OPTION' },
    });
  });

  it('a reconnecting student gets the latest state and their own answer back', async () => {
    const { token, sessionId, code } = await setupSession();
    const lecturer = await track(TestClient.connect(server.url, { token, sessionId }));
    const s = await joinStudent(code);
    await lecturer.emit('session:start');
    const live = await s.client.waitFor('session:state', (p) => p.status === 'LIVE');
    const optionId = live.currentSlide.options[1].id;
    await s.client.emit('answer:submit', { slideId: live.currentSlide.id, optionId });
    await s.client.emit('pulse:set', { state: 'LOST' });

    s.client.close();
    await lecturer.emit('slide:goto', { slideId: live.currentSlide.id }); // state changes while offline are fine

    const again = await track(TestClient.connect(server.url, { participantToken: s.token }));
    const state = await again.waitFor('session:state');
    expect(state).toMatchObject({ status: 'LIVE', currentSlide: { id: live.currentSlide.id } });
    const me = await again.waitFor('me:state');
    expect(me).toEqual({ answer: { slideId: live.currentSlide.id, optionId }, pulse: 'LOST' });
    await again.waitFor('participants:count', (p) => p.count === 1);
  });

  it('throttles results broadcasts (≤ 1 per 300 ms, trailing update included)', async () => {
    const { token, sessionId, code } = await setupSession();
    const lecturer = await track(TestClient.connect(server.url, { token, sessionId }));
    const students = await Promise.all(Array.from({ length: 8 }, () => joinStudent(code)));
    await lecturer.emit('session:start');
    const live = await lecturer.waitFor('session:state', (p) => p.status === 'LIVE');
    await lecturer.waitFor('results:update');
    await sleep(350);
    lecturer.clear();

    await Promise.all(
      students.map((s) => s.client.emit('answer:submit', { slideId: live.currentSlide.id, optionId: live.currentSlide.options[0].id })),
    );
    await lecturer.waitFor('results:update', (p) => p.answered === 8, 3000);
    expect(lecturer.received('results:update').length).toBeLessThanOrEqual(3);
  });
});
