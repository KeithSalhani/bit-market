import { Store } from '../../src/environment/Store.js';

describe('Store', () => {
  let store;

  beforeEach(() => {
    store = new Store(900, 680);
  });

  test('creates 12 shelves (4 categories × 3 rows)', () => {
    expect(store.shelves).toHaveLength(12);
  });

  test('creates 2 checkout counters', () => {
    expect(store.checkouts).toHaveLength(2);
  });

  test('all shelves start with stock', () => {
    for (const shelf of store.shelves) {
      expect(shelf.stock).toBeGreaterThan(0);
    }
  });

  test('getAvailableShelvesByCategory returns matching shelves', () => {
    const toys = store.getAvailableShelvesByCategory('toys');
    expect(toys.length).toBeGreaterThan(0);
    toys.forEach((s) => expect(s.category).toBe('toys'));
  });

  test('getAvailableShelvesByCategory excludes empty shelves', () => {
    const toysCategory = store.shelves.filter((s) => s.category === 'toys');
    // Drain all toy shelves
    toysCategory.forEach((s) => {
      while (!s.isEmpty) s.take();
    });
    const available = store.getAvailableShelvesByCategory('toys');
    expect(available).toHaveLength(0);
  });

  test('getShelvesNeedingRestock returns shelves below threshold', () => {
    // Initially none need restock (all full)
    // Drain one shelf to trigger threshold
    const shelf = store.shelves[0];
    while (!shelf.needsRestock) shelf.take();
    const needy = store.getShelvesNeedingRestock();
    expect(needy).toContain(shelf);
  });

  test('getShortestCheckout returns the one with fewer queue entries', () => {
    store.checkouts[0].enqueue('shopper-1');
    store.checkouts[0].enqueue('shopper-2');
    const shortest = store.getShortestCheckout();
    expect(shortest).toBe(store.checkouts[1]);
  });

  test('totalRevenue sums all checkouts', () => {
    store.checkouts[0].processPayment(50);
    store.checkouts[1].processPayment(30);
    expect(store.totalRevenue).toBe(80);
  });

  test('totalCustomersServed sums all checkouts', () => {
    store.checkouts[0].enqueue('a');
    store.checkouts[0].dequeue();
    store.checkouts[1].enqueue('b');
    store.checkouts[1].dequeue();
    expect(store.totalCustomersServed).toBe(2);
  });
});
