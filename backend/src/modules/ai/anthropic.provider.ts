import Anthropic from '@anthropic-ai/sdk';
import { zodOutputFormat } from '@anthropic-ai/sdk/helpers/zod';
import type { FastifyBaseLogger } from 'fastify';
import type { z } from 'zod';
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

type Effort = 'low' | 'medium' | 'high' | 'xhigh' | 'max';

export interface AnthropicOptions {
  apiKey: string;
  model: string;
  /** Exams need care; chat should feel quick. */
  examEffort: Effort;
  tutorEffort: Effort;
}

/**
 * Claude via the official SDK. Every request opts into server-side refusal
 * fallbacks ("default" routing), so a safety decline on an ordinary study
 * question is retried on Anthropic's recommended fallback model instead of
 * failing the student's exam.
 */
export class AnthropicProvider implements AiProvider {
  readonly source = 'AI' as const;
  private readonly client: Anthropic;

  constructor(
    private readonly options: AnthropicOptions,
    private readonly log: FastifyBaseLogger,
  ) {
    // Worst case about 100 s (2 tries), inside the app's 150 s wait, so the app never gives up first.
    this.client = new Anthropic({ apiKey: options.apiKey, timeout: 48_000, maxRetries: 1 });
  }

  async generateExam(spec: ExamSpec): Promise<GeneratedQuestion[]> {
    const content: Anthropic.Beta.BetaContentBlockParam[] = [
      ...(spec.images ?? []).map((p) => ({
        type: 'image' as const,
        source: { type: 'base64' as const, media_type: p.mediaType, data: p.data },
      })),
      { type: 'text' as const, text: examPrompt(spec) },
    ];
    const { questions } = await this.json(AiExamSchema, undefined, content, this.options.examEffort, 'exam');
    return cleanQuestions(questions);
  }

  async gradeShortAnswers(items: ShortAnswerToGrade[]): Promise<ShortAnswerGrade[]> {
    if (items.length === 0) return [];
    const { grades } = await this.json(AiGradesSchema, GRADING_SYSTEM, gradingPrompt(items), 'low', 'grading');
    return snapGrades(grades);
  }

  async tutor(messages: TutorMessage[], context: TutorContext): Promise<string> {
    const response = await this.call({
      model: this.options.model,
      max_tokens: 4000,
      system: tutorSystem(context),
      messages,
      output_config: { effort: this.options.tutorEffort },
    });
    const text = response.content
      .flatMap((b) => (b.type === 'text' ? [b.text] : []))
      .join('')
      .trim();
    if (!text) throw new AiUnavailableError('The study helper had nothing to say. Please try again.');
    return text;
  }

  /** One structured-output request, validated with the same zod schema. */
  private async json<T extends z.ZodType>(
    schema: T,
    system: string | undefined,
    prompt: string | Anthropic.Beta.BetaContentBlockParam[],
    effort: Effort,
    kind: string,
  ): Promise<z.infer<T>> {
    const response = await this.call({
      model: this.options.model,
      max_tokens: 16000,
      ...(system ? { system } : {}),
      messages: [{ role: 'user', content: prompt }],
      output_config: { effort, format: zodOutputFormat(schema) },
    });
    const text = response.content.flatMap((b) => (b.type === 'text' ? [b.text] : [])).join('');
    try {
      return schema.parse(JSON.parse(text));
    } catch (err) {
      this.log.error({ err, kind }, 'AI returned output that does not match the schema');
      throw new AiUnavailableError('The AI gave an unexpected answer. Please try again.');
    }
  }

  private async call(
    params: Omit<Anthropic.Beta.MessageCreateParamsNonStreaming, 'betas' | 'fallbacks'>,
  ): Promise<Anthropic.Beta.BetaMessage> {
    let response: Anthropic.Beta.BetaMessage;
    try {
      response = await this.client.beta.messages.create({
        ...params,
        betas: ['server-side-fallback-2026-07-01'],
        fallbacks: 'default',
      });
    } catch (err) {
      if (err instanceof Anthropic.RateLimitError) {
        throw new AiUnavailableError('The AI is busy right now. Please try again in a minute.');
      }
      if (err instanceof Anthropic.AuthenticationError || err instanceof Anthropic.PermissionDeniedError) {
        this.log.error({ err }, 'AI credentials rejected');
        throw new AiUnavailableError('The AI is not set up correctly. Please tell the app admin.');
      }
      if (err instanceof Anthropic.BadRequestError && /credit balance/i.test(err.message)) {
        this.log.error('Anthropic account has no credit: add credit in the Anthropic Console');
        throw new AiUnavailableError('The AI helper is resting right now. Please try again later.');
      }
      if (err instanceof Anthropic.APIError) {
        this.log.error({ err, status: err.status }, 'AI request failed');
        throw new AiUnavailableError('The AI could not answer. Please try again.');
      }
      this.log.error({ err }, 'AI unreachable');
      throw new AiUnavailableError("Can't reach the AI right now. Please try again.");
    }

    if (response.stop_reason === 'refusal') {
      this.log.warn({ category: response.stop_details?.category }, 'AI declined the request');
      throw new AiUnavailableError("The AI couldn't help with that. Try rewording it.");
    }
    if (response.stop_reason === 'max_tokens') {
      throw new AiUnavailableError('The answer was too long. Please try again.');
    }
    return response;
  }
}
