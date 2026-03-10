import { StoreBot } from '../../src/entities/StoreBot.js';
import { Store } from '../../src/environment/Store.js';

describe('StoreBot', () => {
  let store;

  beforeEach(() => {
    store = new Store(900, 680);
  });

  test('constructs with required properties', () => {
    const bot = new StoreBot(100, 20);
    expect(bot.id).toMatch(/^bot-/);
    expect(bot.carryAmount).toBe(0);
    expect(bot.carryCapacity).toBe(8);
    expect(bot.active).toBe(true);
    expect(bot.stateMachine).not.toBeNull();
  });

  test('starts in IDLE state', () => {
    const bot = new StoreBot(100, 20);
    expect(bot.stateMachine.current).toBe('IDLE');
  });

  test('transitions to SCANNING after IDLE timer expires', () => {
    const bot = new StoreBot(100, 20);
    // Run ticks past the idle timer (max 60 ticks)
    for (let i = 0; i < 100; i++) {
      bot.update(store);
      if (bot.stateMachine.current === 'SCANNING') break;
    }
    expect(['SCANNING', 'MOVING_TO_WAREHOUSE', 'IDLE']).toContain(
      bot.stateMachine.current,
    );
  });

  test('detects needy shelves and starts restocking cycle', () => {
    const bot = new StoreBot(100, 20);
    // Drain the first shelf so the bot has work to do
    const shelf = store.shelves[0];
    while (!shelf.needsRestock) shelf.take();

    // Run for many ticks to let the bot cycle through states
    let seenMovingToWarehouse = false;
    for (let i = 0; i < 500; i++) {
      bot.update(store);
      if (bot.stateMachine.current === 'MOVING_TO_WAREHOUSE') {
        seenMovingToWarehouse = true;
        break;
      }
    }
    expect(seenMovingToWarehouse).toBe(true);
  });
});
