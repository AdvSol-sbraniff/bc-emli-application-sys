export type GenAiApiStyle = 'responses' | 'chat_completions';

export function getGenAiApiStyleFromEnv(): GenAiApiStyle {
  const raw = String(process.env.GENAI_API_STYLE || 'chat_completions')
    .trim()
    .toLowerCase();

  return raw === 'responses' ? 'responses' : 'chat_completions';
}

export function flattenGenAiContent(content: unknown): string {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';

  return content
    .map((part: any) => {
      if (typeof part === 'string') return part;
      if (part?.type === 'text' && typeof part?.text === 'string')
        return part.text;
      if (typeof part?.text === 'string') return part.text;
      return '';
    })
    .filter(Boolean)
    .join('\n')
    .trim();
}

export function toChatMessages(
  conversation: any[],
): Array<{ role: 'system' | 'user' | 'assistant'; content: string }> {
  if (!Array.isArray(conversation)) return [];

  return conversation
    .map((entry: any) => {
      const role =
        entry?.role === 'system' || entry?.role === 'assistant'
          ? entry.role
          : 'user';
      const content = flattenGenAiContent(entry?.content);
      return { role, content };
    })
    .filter((entry) => entry.content);
}

export function toResponsesPrompt(conversation: any[]): {
  instructions?: string;
  input: string;
} {
  const messages = toChatMessages(conversation);

  const instructions = messages
    .filter((entry) => entry.role === 'system')
    .map((entry) => entry.content)
    .join('\n\n')
    .trim();

  const input = messages
    .filter((entry) => entry.role !== 'system')
    .map((entry) => `${entry.role.toUpperCase()}:\n${entry.content}`)
    .join('\n\n')
    .trim();

  return {
    instructions: instructions || undefined,
    input,
  };
}

export function toResponsesInputAndInstructions(conversation: any[]): {
  instructions?: string;
  input: any[];
} {
  if (!Array.isArray(conversation)) return { input: [] };

  const instructions = conversation
    .filter((entry: any) => entry?.role === 'system')
    .map((entry: any) => flattenGenAiContent(entry?.content))
    .filter(Boolean)
    .join('\n\n')
    .trim();

  const input = conversation
    .filter((entry: any) => entry?.role !== 'system')
    .map((entry: any) => {
      const role = entry?.role === 'assistant' ? 'assistant' : 'user';
      const content = normalizeResponsesMessageContent(entry?.content);
      return { type: 'message', role, content };
    })
    .filter((entry) => Array.isArray(entry.content) && entry.content.length);

  return {
    instructions: instructions || undefined,
    input,
  };
}

function normalizeResponsesMessageContent(content: unknown): any[] {
  const parts = Array.isArray(content) ? content : [content];

  return parts
    .map((part: any) => {
      if (typeof part === 'string') {
        return { type: 'input_text', text: part };
      }

      if (!part || typeof part !== 'object') {
        const text = flattenGenAiContent(part);
        return text ? { type: 'input_text', text } : null;
      }

      if (part.type === 'input_file') return part;

      if (part.type === 'input_text' && typeof part.text === 'string') {
        return { type: 'input_text', text: part.text };
      }

      if (part.type === 'text' && typeof part.text === 'string') {
        return { type: 'input_text', text: part.text };
      }

      if (typeof part.text === 'string') {
        return { type: 'input_text', text: part.text };
      }

      const text = flattenGenAiContent(part);
      return text ? { type: 'input_text', text } : null;
    })
    .filter((part) => part?.type);
}

export function extractChatCompletionText(resp: any): string {
  const messageContent = resp?.choices?.[0]?.message?.content;
  return flattenGenAiContent(messageContent);
}

export function stripThinkBlocks(text: string): string {
  return String(text || '')
    .replace(/<think>[\s\S]*?<\/think>/gi, '')
    .trim();
}

export function extractJsonPayloadText(text: string): string {
  const cleaned = stripThinkBlocks(text).trim();
  if (!cleaned) return cleaned;

  const objectStart = cleaned.indexOf('{');
  const objectEnd = cleaned.lastIndexOf('}');
  if (objectStart >= 0 && objectEnd > objectStart) {
    return cleaned.slice(objectStart, objectEnd + 1);
  }

  const arrayStart = cleaned.indexOf('[');
  const arrayEnd = cleaned.lastIndexOf(']');
  if (arrayStart >= 0 && arrayEnd > arrayStart) {
    return cleaned.slice(arrayStart, arrayEnd + 1);
  }

  return cleaned;
}
