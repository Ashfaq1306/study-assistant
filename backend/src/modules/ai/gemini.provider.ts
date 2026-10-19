import { ApiError, BlockedReason, FinishReason, GoogleGenAI, type Content, type Part } from '@google/genai';
import type { FastifyBaseLogger } from 'fastify';
import { z } from 'zod';
import { cleanQuestions, examPrompt, GRADING_SYSTEM, gradingPrompt, snapGrades, tutorSystem } from './ai.prompts.js';
import {
  AiExamSchema,
  AiGradesSchema,
  AiUnavailableError,
  type AiProvider,
  type ExamSpec,
  type GeneratedQuestion,
  type ShortAnswerGrade,
  type ShortAnswerToGrade,
  type TutorContext,
  type TutorMessage,
} from './ai.types.js';

export interface GeminiOptions {
  apiKey: string;
  /** The main model first, then fallbacks for when it is overloaded or retired. */
  models: string[];
}

/** Worth trying the next model: overloaded, rate-limited, retired or a server hiccup. */
const TRY_NEXT = new Set([404, 429, 500, 503]);

/** Google Gemini via the official SDK: the same exams, grading and helper as Claude. */
export class GeminiProvider implements AiProvider {
  readonly source = 'AI' as const;
  private readonly client: GoogleGenAI;

  constructor(
    private readonly options: GeminiOptions,
    private readonly log: FastifyBaseLogger,
  ) {
    // Inside the app's 150 s wait, so the app never gives up first.
    this.client = new GoogleGenAI({
      apiKey: options.apiKey,
      httpOptions: { timeout: 45_000, retryOptions: { attempts: 1 } },
    });
  }

  async generateExam(spec: ExamSpec): Promise<GeneratedQuestion[]> {
    const parts: Part[] = [
      ...(spec.images ?? []).map((p) => ({ inlineData: { mimeType: p.mediaType, data: p.data } })),
      { text: examPrompt(spec) },
    ];
    const { questions } = await this.json(AiExamSchema, undefined, parts, 'exam');
    return cleanQuestions(questions);
  }

  async gradeShortAnswers(items: ShortAnswerToGrade[]): Promise<ShortAnswerGrade[]> {
    if (items.length === 0) return [];
    const { grades } = await this.json(AiGradesSchema, GRADING_SYSTEM, [{ text: gradingPrompt(items) }], 'grading');
    return snapGrades(grades);
  }

  async tutor(messages: TutorMessage[], context: TutorContext): Promise<string> {
    const contents: Content[] = messages.map((m) => ({
      role: m.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: m.content }],
    }));
    const text = (await this.call(contents, { systemInstruction: tutorSystem(context), maxOutputTokens: 2000 }))
      .trim();
    if (!text) throw new AiUnavailableError('The study helper had nothing to say. Please try again.');
    return text;
  }

  /** One JSON-mode request, validated with the same zod schema as Claude's. */
  private async json<T extends z.ZodType>(schema: T, system: string | undefined, parts: Part[], kind: string) {
    const text = await this.call([{ role: 'user', parts }], {
      systemInstruction: system,
      responseMimeType: 'application/json',
      responseJsonSchema: z.toJSONSchema(schema),
      maxOutputTokens: 16_000,
    });
    try {
      return schema.parse(JSON.parse(text));
    } catch (err) {
      this.log.error({ err, kind }, 'AI returned output that does not match the schema');
      throw new AiUnavailableError('The AI gave an unexpected answer. Please try again.');
    }
  }

  /** Asks each model in turn until one answers; other errors stop at once. */
  private async firstAvailable(contents: Content[], config: object) {
    let lastError: unknown;
    for (const model of this.options.models) {
      try {
        return await this.client.models.generateContent({ model, contents, config });
      } catch (err) {
        if (!(err instanceof ApiError) || !TRY_NEXT.has(err.status)) throw err;
        this.log.warn({ model, status: err.status }, 'Gemini model unavailable; trying the next one');
        lastError = err;
      }
    }
    throw lastError;
  }

  private async call(
    contents: Content[],
    config: {
      systemInstruction?: string;
      responseMimeType?: string;
      responseJsonSchema?: unknown;
      maxOutputTokens: number;
    },
  ): Promise<string> {
    let response;
    try {
      response = await this.firstAvailable(contents, config);
    } catch (err) {
      if (err instanceof ApiError) {
        if (err.status === 429) throw new AiUnavailableError('The AI is busy right now. Please try again in a minute.');
        if (err.status === 400 || err.status === 401 || err.status === 403) {
          this.log.error({ err, status: err.status }, 'AI credentials or request rejected');
          throw new AiUnavailableError('The AI is not set up correctly. Please tell the app admin.');
        }
        this.log.error({ err, status: err.status }, 'AI request failed');
        throw new AiUnavailableError('The AI could not answer. Please try again.');
      }
      this.log.error({ err }, 'AI unreachable');
      throw new AiUnavailableError("Can't reach the AI right now. Please try again.");
    }

    const candidate = response.candidates?.[0];
    const blocked = response.promptFeedback?.blockReason;
    if ((blocked && blocked !== BlockedReason.BLOCKED_REASON_UNSPECIFIED) || candidate?.finishReason === FinishReason.SAFETY) {
      this.log.warn({ reason: response.promptFeedback?.blockReason ?? candidate?.finishReason }, 'AI declined the request');
      throw new AiUnavailableError("The AI couldn't help with that. Try rewording it.");
    }
    if (candidate?.finishReason === FinishReason.MAX_TOKENS) throw new AiUnavailableError('The answer was too long. Please try again.');
    return response.text ?? '';
  }
}
