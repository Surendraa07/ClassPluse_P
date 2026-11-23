/** @type {import('jest').Config} */
module.exports = {
  testEnvironment: 'node',
  roots: ['<rootDir>/tests'],
  setupFiles: ['<rootDir>/tests/setup-env.ts'],
  // Transpile only (fast); `npm run typecheck` does the full type check.
  transform: { '^.+\.ts$': 'ts-jest' },
  testTimeout: 20000,
  maxWorkers: 1, // test files share one database
};
