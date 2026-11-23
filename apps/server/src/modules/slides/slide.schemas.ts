import { z } from 'zod';

export const MIN_OPTIONS = 2;
export const MAX_OPTIONS = 6;

export const SlideTypeSchema = z.enum(['POLL', 'QUIZ']);
export type SlideTypeInput = z.infer<typeof SlideTypeSchema>;

export const OptionInput = z.object({
  /** Present when editing an existing option (keeps its responses); omit for new options. */
  id: z.string().min(1).max(64).optional(),
  label: z.string().trim().min(1, 'Option label is required').max(120),
  isCorrect: z.boolean().optional().default(false),
});
export type OptionInputT = z.infer<typeof OptionInput>;

const Question = z.string().trim().min(1, 'Question is required').max(300);
const ImageUrl = z.url({ protocol: /^https$/, message: 'Image URL must be an https URL' }).max(500);
const Options = z
  .array(OptionInput)
  .min(MIN_OPTIONS, `A slide needs at least ${MIN_OPTIONS} options`)
  .max(MAX_OPTIONS, `A slide can have at most ${MAX_OPTIONS} options`);

export interface RuleIssue {
  path: string;
  message: string;
}

/** Business rules that depend on the slide type. Shared by create and (merged) update. */
export function slideRuleIssues(type: SlideTypeInput, options: Array<{ label: string; isCorrect: boolean }>): RuleIssue[] {
  const issues: RuleIssue[] = [];
  const correct = options.filter((o) => o.isCorrect).length;
  if (type === 'QUIZ' && correct !== 1) {
    issues.push({ path: 'options', message: 'A quiz slide needs exactly one correct option' });
  }
  if (type === 'POLL' && correct > 0) {
    issues.push({ path: 'options', message: 'Poll slides cannot have a correct option' });
  }
  const seen = new Set<string>();
  options.forEach((o, i) => {
    const key = o.label.trim().toLowerCase();
    if (seen.has(key)) issues.push({ path: `options.${i}.label`, message: 'Option labels must be unique' });
    seen.add(key);
  });
  return issues;
}

export const CreateSlideBody = z
  .object({
    type: SlideTypeSchema,
    question: Question,
    imageUrl: ImageUrl.nullish(),
    options: Options,
  })
  .superRefine((val, ctx) => {
    for (const issue of slideRuleIssues(val.type, val.options)) {
      ctx.addIssue({ code: 'custom', path: issue.path.split('.'), message: issue.message });
    }
  });

export const UpdateSlideBody = z
  .object({
    type: SlideTypeSchema.optional(),
    question: Question.optional(),
    imageUrl: ImageUrl.nullish(),
    options: Options.optional(),
  })
  .refine((v) => Object.keys(v).length > 0, { message: 'Nothing to update' });

export const ReorderBody = z.object({
  slideIds: z
    .array(z.string().min(1).max(64))
    .min(1)
    .refine((ids) => new Set(ids).size === ids.length, 'slideIds must not contain duplicates'),
});
