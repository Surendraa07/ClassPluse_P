// Applies migrations to TEST_DATABASE_URL (creates the DB if missing). Run via `npm test`.
require('dotenv/config');
const { execSync } = require('node:child_process');

const url = process.env.TEST_DATABASE_URL;
if (!url) {
  console.error('TEST_DATABASE_URL is not set (see .env.example)');
  process.exit(1);
}
execSync('npx prisma migrate deploy', { stdio: 'inherit', env: { ...process.env, DATABASE_URL: url } });
