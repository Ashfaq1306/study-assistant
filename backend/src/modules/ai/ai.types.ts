import { z } from 'zod';
import type { QuestionType } from '../sessions/sessions.schemas.js';

export interface ExamSpec {
  subject: string;
  topics: string;
  difficulty: 'EASY' | 'MEDIUM' | 'HARD';
  count: number;
  types: QuestionType[];
  /** Student's age, so wording and level fit. */
  age: number;
  /** The student's plan or notes. */
  notes?: string;
  /** Photos of the pages they studied: questions come from these. */
  images?: { mediaType: 'image/jpeg' | 'image/png' | 'image/webp'; data: string }[];
}

/**
 * A generated question. For MCQ `answer` is the index of the correct option
 * ("0"–"3"); for TRUE_FALSE it is "true" or "false"; for SHORT it is a model
 * answer, with `keyPoints` a grader can look for.
 */
export const GeneratedQuestionSchema = z.object({
  type: z.enum(['MCQ', 'TRUE_FALSE', 'SHORT']),
  prompt: z.string().min(3).max(600),
  options: z.array(z.string().min(1).max(200)).max(4),
  answer: z.string().min(1).max(400),
  keyPoints: z.array(z.string().min(1).max(120)).max(6),
  explanation: z.string().max(600),
});
export type GeneratedQuestion = z.infer<typeof GeneratedQuestionSchema>;

export const GeneratedExamSchema = z.object({ questions: z.array(GeneratedQuestionSchema) });

/** What the model is asked to return. Limits are applied per question afterwards. */
export const AiExamSchema = z.object({
  questions: z.array(
    z.object({
      type: z.enum(['MCQ', 'TRUE_FALSE', 'SHORT']),
      prompt: z.string(),
      options: z.array(z.string()),
      answer: z.string(),
      keyPoints: z.array(z.string()),
      explanation: z.string(),
    }),
  ),
});

export const AiGradesSchema = z.object({
  grades: z.array(z.object({ id: z.string(), score: z.number(), feedback: z.string() })),
});

export interface ShortAnswerToGrade {
  id: string;
  question: string;
  modelAnswer: string;
  keyPoints: string[];
  studentAnswer: string;
}

export const ShortAnswerGradesSchema = z.object({
  grades: z.array(
    z.object({
      id: z.string(),
      /** 0 = wrong, 0.5 = partly right, 1 = right. */
      score: z.number().min(0).max(1),
      feedback: z.string().max(300),
    }),
  ),
});
export type ShortAnswerGrade = z.infer<typeof ShortAnswerGradesSchema>['grades'][number];

export interface TutorMessage {
  role: 'user' | 'assistant';
  content: string;
}

export interface TutorContext {
  name: string;
  age: number;
  subject?: string;
  topics?: string;
}

/** The AI behind exams and the study helper. */
export interface AiProvider {
  /** 'AI' for a real model, 'PRACTICE' for the built-in fallback. */
  readonly source: 'AI' | 'PRACTICE';
  generateExam(spec: ExamSpec): Promise<GeneratedQuestion[]>;
  gradeShortAnswers(items: ShortAnswerToGrade[]): Promise<ShortAnswerGrade[]>;
  tutor(messages: TutorMessage[], context: TutorContext): Promise<string>;
}

export class AiUnavailableError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'AiUnavailableError';
  }
}
