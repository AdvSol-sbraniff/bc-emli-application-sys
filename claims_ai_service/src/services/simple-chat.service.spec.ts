import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request = require('supertest');
import { SimpleChatController } from '../controllers/simple-chat.controller';
import { SimpleChatService } from './simple-chat.service';

describe('Simple chat deployment selection', () => {
  const originalEnv = { ...process.env };
  let app: INestApplication;
  let responsesCreate: jest.Mock;
  let chatCreate: jest.Mock;
  let service: any;

  beforeEach(async () => {
    process.env.GENAI_BASE_URL = 'https://example.test/openai/v1/';
    process.env.GENAI_KEY = 'test-key';
    process.env.GENAI_API_STYLE = 'responses';
    delete process.env.GENAI_DEPLOYMENT;
    const module = await Test.createTestingModule({
      controllers: [SimpleChatController],
      providers: [SimpleChatService],
    }).compile();
    service = module.get(SimpleChatService);
    responsesCreate = jest.fn().mockResolvedValue({ output_text: 'Hello' });
    chatCreate = jest
      .fn()
      .mockResolvedValue({ choices: [{ message: { content: 'Hello' } }] });
    service.client.responses.create = responsesCreate;
    service.client.chat.completions.create = chatCreate;
    app = module.createNestApplication();
    await app.init();
  });

  afterEach(async () => {
    await app?.close();
    process.env = { ...originalEnv };
  });

  it.each(['responses', 'chat_completions'])(
    'passes the selected model through HTTP using %s without an env default',
    async (style) => {
      service.apiStyle = style;
      await request(app.getHttpServer())
        .post('/inv/simple-chat')
        .send({ prompt: 'Hello', deployment_name: ' selected-model ' })
        .expect(201, { message: 'Hello' });
      expect(
        style === 'responses' ? responsesCreate : chatCreate,
      ).toHaveBeenCalledWith(
        expect.objectContaining({ model: 'selected-model' }),
      );
    },
  );

  it('returns a clear client error when no model is configured or supplied', async () => {
    const response = await request(app.getHttpServer())
      .post('/inv/simple-chat')
      .send({ prompt: 'Hello' })
      .expect(400);
    expect(response.body.message).toContain('deployment_name is required');
    expect(responsesCreate).not.toHaveBeenCalled();
  });

  it('preserves the optional legacy env fallback but allows an override', async () => {
    process.env.GENAI_DEPLOYMENT = 'legacy-model';
    const legacy: any = new SimpleChatService();
    legacy.client.responses.create = responsesCreate;
    await legacy.simpleChat('Hello');
    await legacy.simpleChat('Hello', 'other-model');
    expect(responsesCreate.mock.calls.map(([body]) => body.model)).toEqual([
      'legacy-model',
      'other-model',
    ]);
  });
});
