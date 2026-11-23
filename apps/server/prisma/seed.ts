/**
 * Seed: demo lecturer + "POP Lecture 4: Loops" presentation.
 * Idempotent: re-running replaces the demo lecturer's seeded presentation.
 */
import 'dotenv/config';
import bcrypt from 'bcryptjs';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient, SlideType } from '../src/generated/prisma/client';

const DEMO_EMAIL = 'demo@classpluse.app';
const DEMO_PASSWORD = 'Password123!';
const PRESENTATION_TITLE = 'POP Lecture 4: Loops';

const slides: Array<{
  type: SlideType;
  question: string;
  options: Array<{ label: string; isCorrect?: boolean }>;
}> = [
  {
    type: SlideType.POLL,
    question: 'Is a string a primitive type?',
    options: [{ label: 'Yes' }, { label: 'No' }, { label: 'Depends on the language' }],
  },
  {
    type: SlideType.QUIZ,
    question: 'Which loop always runs at least once?',
    options: [{ label: 'for' }, { label: 'while' }, { label: 'do-while', isCorrect: true }],
  },
];

async function main() {
  const url = process.env.DATABASE_URL;
  if (!url) throw new Error('DATABASE_URL is not set');
  const prisma = new PrismaClient({ adapter: new PrismaPg({ connectionString: url }) });

  try {
    const passwordHash = await bcrypt.hash(DEMO_PASSWORD, 12);
    const lecturer = await prisma.lecturer.upsert({
      where: { email: DEMO_EMAIL },
      update: { passwordHash },
      create: { name: 'Demo Lecturer', email: DEMO_EMAIL, passwordHash },
    });

    await prisma.presentation.deleteMany({ where: { lecturerId: lecturer.id, title: PRESENTATION_TITLE } });
    const presentation = await prisma.presentation.create({
      data: {
        lecturerId: lecturer.id,
        title: PRESENTATION_TITLE,
        slides: {
          create: slides.map((s, i) => ({
            order: i,
            type: s.type,
            question: s.question,
            options: {
              create: s.options.map((o, j) => ({ order: j, label: o.label, isCorrect: o.isCorrect ?? false })),
            },
          })),
        },
      },
      include: { slides: true },
    });

    console.log(`Seeded lecturer ${DEMO_EMAIL} / ${DEMO_PASSWORD}`);
    console.log(`Seeded presentation "${presentation.title}" with ${presentation.slides.length} slides`);
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
