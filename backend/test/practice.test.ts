import { describe, expect, it } from 'vitest';
import { PracticeProvider } from '../src/modules/ai/practice.provider.js';
import type { ExamSpec } from '../src/modules/ai/ai.types.js';

const spec = (over: Partial<ExamSpec>): ExamSpec => ({
  subject: 'ICT',
  topics: 'Networks',
  count: 10,
  types: ['MCQ'],
  difficulty: 'MEDIUM',
  age: 14,
  ...over,
});

const isArithmetic = (prompt: string) => /^What is -?\d+ [-+×÷x*/] -?\d+\?$/.test(prompt);

describe('PracticeProvider', () => {
  const provider = new PracticeProvider();

  it('fills a 10-question subject exam without arithmetic questions', async () => {
    for (const subject of ['ICT', 'Science', 'English', 'History']) {
      const questions = await provider.generateExam(spec({ subject }));
      expect(questions).toHaveLength(10);
      expect(questions.filter((q) => isArithmetic(q.prompt))).toEqual([]);
      expect(new Set(questions.map((q) => q.prompt)).size).toBe(10);
    }
  });

  it('every multiple-choice answer points at one of four options', async () => {
    const questions = await provider.generateExam(spec({ subject: 'Science', count: 20 }));
    for (const q of questions) {
      expect(q.options).toHaveLength(4);
      expect(Number(q.answer)).toBeGreaterThanOrEqual(0);
      expect(Number(q.answer)).toBeLessThan(4);
    }
  });

  it('maths exams are generated arithmetic', async () => {
    const questions = await provider.generateExam(spec({ subject: 'Maths', count: 5 }));
    expect(questions.every((q) => isArithmetic(q.prompt))).toBe(true);
  });
});
