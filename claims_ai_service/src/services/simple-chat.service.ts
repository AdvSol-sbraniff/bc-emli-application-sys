import { BadRequestException, Injectable } from '@nestjs/common';
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
    const deployment = process.env.GENAI_DEPLOYMENT?.trim() || '';

    if (!baseURL || !apiKey) {
      throw new Error('Missing GENAI_BASE_URL and/or GENAI_KEY');
    }

    this.deployment = deployment;
    this.apiStyle = getGenAiApiStyleFromEnv();
    this.client = new OpenAI({
      apiKey,
      baseURL,
    });
  }

  async simpleChat(
    prompt: string,
    deploymentName?: string,
  ): Promise<{ message: string }> {
    const cleanPrompt = String(prompt || '').trim();
    if (!cleanPrompt) return { message: '' };
    const deployment = deploymentName?.trim() || this.deployment;
    if (!deployment)
      throw new BadRequestException('A model deployment_name is required.');

    if (this.apiStyle === 'responses') {
      const resp = await this.client.responses.create({
        model: deployment,
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
      model: deployment,
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
