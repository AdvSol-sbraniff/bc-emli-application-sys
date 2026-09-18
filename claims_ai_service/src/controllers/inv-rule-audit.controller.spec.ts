import { EventEmitter } from 'events';
import { InvController } from './inv.controller';

describe('Rule audit HTTP lifecycle', () => {
  it('forwards client disconnects to the audit and removes listeners afterwards', async () => {
    const request: any = new EventEmitter();
    request.res = new EventEmitter();
    request.res.writableEnded = false;
    const service: any = {
      ruleAudit: jest.fn().mockImplementation(async (...args) => {
        const signal = args[4] as AbortSignal;
        expect(signal.aborted).toBe(false);
        request.res.emit('close');
        expect(signal.aborted).toBe(true);
        throw new Error('cancelled');
      }),
    };
    const controller = new InvController(service);
    await expect(
      controller.ruleAudit({ contextwindowjson: [] }, request),
    ).rejects.toThrow('cancelled');
    expect(request.listenerCount('aborted')).toBe(0);
    expect(request.res.listenerCount('close')).toBe(0);
  });

  it('does not treat a successfully ended response as cancellation', async () => {
    const request: any = new EventEmitter();
    request.res = new EventEmitter();
    request.res.writableEnded = true;
    const service: any = {
      ruleAudit: jest.fn().mockImplementation(async (...args) => {
        request.res.emit('close');
        expect((args[4] as AbortSignal).aborted).toBe(false);
        return { advice: 'Complete.' };
      }),
    };
    const controller = new InvController(service);
    await expect(
      controller.ruleAudit({ contextwindowjson: [] }, request),
    ).resolves.toEqual({ advice: 'Complete.' });
    expect(request.listenerCount('aborted')).toBe(0);
    expect(request.res.listenerCount('close')).toBe(0);
  });
});
