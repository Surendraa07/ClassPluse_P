import request from 'supertest';
import jwt from 'jsonwebtoken';
import { createApp } from '../src/app';
import { prisma } from '../src/lib/prisma';
import { auth, registerLecturer, resetDb } from './helpers';

const app = createApp();

beforeEach(resetDb);
afterAll(() => prisma.$disconnect());

describe('POST /auth/register', () => {
  it('creates a lecturer, returns a token and never exposes the hash', async () => {
    const res = await request(app)
      .post('/api/v1/auth/register')
      .send({ name: 'Ada', email: '  Ada@Example.com ', password: 'Password123!' });
    expect(res.status).toBe(201);
    expect(res.body.token).toEqual(expect.any(String));
    expect(res.body.lecturer).toMatchObject({ name: 'Ada', email: 'ada@example.com', avatarUrl: null });
    expect(res.body.lecturer.passwordHash).toBeUndefined();

    const row = await prisma.lecturer.findUniqueOrThrow({ where: { email: 'ada@example.com' } });
    expect(row.passwordHash).not.toBe('Password123!');
    expect(row.passwordHash.startsWith('$2')).toBe(true);
  });

  it('rejects duplicate emails (case-insensitive) with 409', async () => {
    await registerLecturer(app, { email: 'dup@example.com' });
    const res = await request(app)
      .post('/api/v1/auth/register')
      .send({ name: 'X', email: 'DUP@example.com', password: 'Password123!' });
    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('CONFLICT');
  });

  it('validates the body with field-level details', async () => {
    const res = await request(app).post('/api/v1/auth/register').send({ name: '', email: 'nope', password: 'short' });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
    const paths = res.body.error.details.map((d: { path: string }) => d.path);
    expect(paths).toEqual(expect.arrayContaining(['name', 'email', 'password']));
  });

  it('returns 400 INVALID_JSON for malformed JSON', async () => {
    const res = await request(app)
      .post('/api/v1/auth/register')
      .set('Content-Type', 'application/json')
      .send('{"name":');
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_JSON');
  });
});

describe('POST /auth/login', () => {
  it('logs in with correct credentials', async () => {
    const { lecturer, password } = await registerLecturer(app, { email: 'login@example.com' });
    const res = await request(app).post('/api/v1/auth/login').send({ email: 'LOGIN@example.com', password });
    expect(res.status).toBe(200);
    expect(res.body.lecturer.id).toBe(lecturer.id);
    expect(res.body.lecturer.passwordHash).toBeUndefined();
  });

  it('gives the same 401 for a wrong password and an unknown email', async () => {
    await registerLecturer(app, { email: 'who@example.com' });
    const wrong = await request(app).post('/api/v1/auth/login').send({ email: 'who@example.com', password: 'nope-nope' });
    const unknown = await request(app).post('/api/v1/auth/login').send({ email: 'ghost@example.com', password: 'nope-nope' });
    for (const res of [wrong, unknown]) {
      expect(res.status).toBe(401);
      expect(res.body.error).toEqual({ code: 'INVALID_CREDENTIALS', message: 'Email or password is incorrect' });
    }
  });
});

describe('GET /auth/me', () => {
  it('returns the current lecturer', async () => {
    const { token, lecturer } = await registerLecturer(app);
    const res = await request(app).get('/api/v1/auth/me').set(auth(token));
    expect(res.status).toBe(200);
    expect(res.body.lecturer).toMatchObject({ id: lecturer.id, email: lecturer.email });
  });

  it.each([
    ['no header', undefined],
    ['garbage token', 'Bearer not-a-jwt'],
    ['wrong scheme', 'Basic abc'],
  ])('401 with %s', async (_name, header) => {
    const req = request(app).get('/api/v1/auth/me');
    if (header) req.set('Authorization', header);
    const res = await req;
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('UNAUTHORIZED');
  });

  it('401 for a token signed with another secret', async () => {
    const { lecturer } = await registerLecturer(app);
    const forged = jwt.sign({ sub: lecturer.id, typ: 'lecturer' }, 'some-other-secret-some-other-secret');
    const res = await request(app).get('/api/v1/auth/me').set(auth(forged));
    expect(res.status).toBe(401);
  });

  it('401 for an expired token', async () => {
    const { lecturer } = await registerLecturer(app);
    const expired = jwt.sign({ sub: lecturer.id, typ: 'lecturer' }, process.env.JWT_SECRET!, { expiresIn: -10 });
    const res = await request(app).get('/api/v1/auth/me').set(auth(expired));
    expect(res.status).toBe(401);
  });

  it('401 for a non-lecturer token type', async () => {
    const { lecturer } = await registerLecturer(app);
    const other = jwt.sign({ sub: lecturer.id, typ: 'participant' }, process.env.JWT_SECRET!);
    const res = await request(app).get('/api/v1/auth/me').set(auth(other));
    expect(res.status).toBe(401);
  });

  it('401 once the lecturer has been deleted', async () => {
    const { token, lecturer } = await registerLecturer(app);
    await prisma.lecturer.delete({ where: { id: lecturer.id } });
    const res = await request(app).get('/api/v1/auth/me').set(auth(token));
    expect(res.status).toBe(401);
  });
});
