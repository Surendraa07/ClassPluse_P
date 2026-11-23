import { z } from 'zod';

const email = z.string().trim().toLowerCase().pipe(z.email('Enter a valid email address').max(254));

export const RegisterBody = z.object({
  name: z.string().trim().min(1, 'Name is required').max(100),
  email,
  // bcrypt only uses the first 72 bytes
  password: z.string().min(8, 'Password must be at least 8 characters').max(72),
});

export const LoginBody = z.object({
  email,
  password: z.string().min(1, 'Password is required').max(72),
});

export const UpdateMeBody = z
  .object({
    name: z.string().trim().min(1, 'Name is required').max(100).optional(),
    avatarUrl: z.url({ protocol: /^https$/, message: 'Avatar must be an https URL' }).max(500).nullable().optional(),
  })
  .refine((v) => Object.keys(v).length > 0, { message: 'Nothing to update' });
