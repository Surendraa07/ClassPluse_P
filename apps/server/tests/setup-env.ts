// Runs before each test file: point Prisma at the test database.
import 'dotenv/config';

process.env.NODE_ENV = 'test';
if (process.env.TEST_DATABASE_URL) {
  process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
}
process.env.JWT_SECRET ??= 'test-secret-test-secret-test-secret-123456';
process.env.BCRYPT_ROUNDS = '4'; // fast hashing in tests
process.env.AUTH_RATE_LIMIT = '1000';
// Never talk to the real Cloudinary account from tests; fetch is mocked where needed.
process.env.CLOUDINARY_CLOUD_NAME = 'test-cloud';
process.env.CLOUDINARY_API_KEY = '123456789012345';
process.env.CLOUDINARY_API_SECRET = 'test-cloudinary-secret';
process.env.CLOUDINARY_FOLDER = 'classpluse';
