import { Router } from 'express';
import { z } from 'zod';
import { createUploadSignature } from '../../lib/cloudinary';
import { parse } from '../../lib/validate';
import { lecturerIdOf, requireLecturer } from '../../middleware/auth';
import { uploadLimiter } from '../../middleware/rateLimit';

const SignatureBody = z.object({ kind: z.enum(['avatar', 'slide']) });

export const uploadsRouter = Router();
uploadsRouter.use(requireLecturer);

/** Returns the fields the app sends to Cloudinary with the file. */
uploadsRouter.post('/signature', uploadLimiter, (req, res) => {
  const { kind } = parse(SignatureBody, req.body);
  res.json(createUploadSignature(kind, lecturerIdOf(req)));
});
