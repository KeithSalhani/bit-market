import { Shopper } from '../../src/entities/Shopper.js';
import { Store } from '../../src/environment/Store.js';

describe('Shopper', () => {
  let store;

  beforeEach(() => {
    store = new Store(900, 680);
  });

  test('constructs with required properties', () => {
    const s = new Shopper(450, 640);
    expect(s.id).toMatch(/^shopper-/);
    expect(s.shoppingList).toBeInstanceOf(Array);
    expect(s.cart).toEqual([]);
    expect(s.active).toBe(true);
    expect(s.stateMachine).not.toBeNull();
  });

  test('starts in ENTERING state', () => {
    const s = new Shopper(450, 640);
    expect(s.stateMachine.current).toBe('ENTERING');
  });

  test('cartTotal sums item prices', () => {
    const s = new Shopper(450, 640);
    s.cart.push({ name: 'Bear', price: 25, emoji: '🧸' });
    s.cart.push({ name: 'Lollipop', price: 2, emoji: '🍭' });
    expect(s.cartTotal).toBe(27);
  });

  test('budget is a positive number', () => {
    const s = new Shopper(450, 640);
    expect(s.budget).toBeGreaterThan(0);
    expect(s.remainingBudget).toBe(s.budget);
  });

  test('happiness starts in valid range', () => {
    const s = new Shopper(450, 640);
    expect(s.happiness).toBeGreaterThanOrEqual(0);
    expect(s.happiness).toBeLessThanOrEqual(100);
  });

  test('update progresses state machine', () => {
    const s = new Shopper(450, 640);
    // Run many ticks – shopper should eventually leave ENTERING
    for (let i = 0; i < 200; i++) {
      s.update(store);
      if (!s.active || s.stateMachine.current !== 'ENTERING') break;
    }
    // Either progressed past ENTERING or is active elsewhere
    const notStuck = s.stateMachine.current !== 'ENTERING' || !s.active;
    expect(notStuck).toBe(true);
  });
});
