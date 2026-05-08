import { Injectable } from '@nestjs/common';
import OpenAI from 'openai';
import {
  GenAiApiStyle,
  extractChatCompletionText,
  getGenAiApiStyleFromEnv,
  stripThinkBlocks,
} from './genai-api';

@Injectable()
export class SimpleChatService {
  private readonly client: OpenAI;
  private readonly deployment: string;
  private readonly apiStyle: GenAiApiStyle;

  constructor() {
    const baseURL = process.env.GENAI_BASE_URL;
    const apiKey = process.env.GENAI_KEY;
    const deployment = process.env.GENAI_DEPLOYMENT;

    if (!baseURL || !apiKey || !deployment) {
      throw new Error(
        'Missing GENAI_BASE_URL and/or GENAI_KEY and/or GENAI_DEPLOYMENT',
      );
    }

    this.deployment = deployment;
    this.apiStyle = getGenAiApiStyleFromEnv();
    this.client = new OpenAI({
      apiKey,
      baseURL,
    });
  }

  async simpleChat(prompt: string): Promise<{ message: string }> {
    const cleanPrompt = String(prompt || '').trim();
    if (!cleanPrompt) return { message: '' };

    if (this.apiStyle === 'responses') {
      const resp = await this.client.responses.create({
        model: this.deployment,
        input: [
          {
            role: 'user',
            content: [{ type: 'input_text', text: cleanPrompt }],
          },
        ],
      });

      return { message: stripThinkBlocks(resp.output_text ?? '').trim() };
    }

    const resp = await this.client.chat.completions.create({
      model: this.deployment,
      messages: [
        {
          role: 'system',
          content:
            'Reply with only the final answer. Do not include reasoning, analysis, steps, or thinking tags.',
        },
        {
          role: 'user',
          content: cleanPrompt,
        },
      ],
    });

    return {
      message: stripThinkBlocks(extractChatCompletionText(resp)).trim(),
    };
  }
}
