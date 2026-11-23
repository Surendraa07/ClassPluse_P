import { z } from 'zod';

/** Parse or throw ZodError (turned into a 400 VALIDATION_ERROR by the error handler). */
export function parse<S extends z.ZodType>(schema: S, data: unknown): z.infer<S> {
  return schema.parse(data);
}

export const IdParam = z.object({ id: z.string().min(1).max(64) });
