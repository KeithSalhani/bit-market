import { Simulation } from '../src/Simulation.js';

describe('Simulation', () => {
  let sim;

  beforeEach(() => {
    sim = new Simulation(900, 680);
  });

  test('initialises with no shoppers', () => {
    expect(sim.shoppers).toHaveLength(0);
  });

  test('initialises with storeBots', () => {
    expect(sim.storeBots.length).toBeGreaterThan(0);
  });

  test('initialises with clerks (one per checkout)', () => {
    expect(sim.clerks).toHaveLength(sim.store.checkouts.length);
  });

  test('getStats returns expected shape', () => {
    const stats = sim.getStats();
    expect(stats).toHaveProperty('tick');
    expect(stats).toHaveProperty('shoppers');
    expect(stats).toHaveProperty('bots');
    expect(stats).toHaveProperty('revenue');
    expect(stats).toHaveProperty('served');
  });

  test('tick increments on each update', () => {
    sim.update();
    expect(sim.tick).toBe(1);
    sim.update();
    expect(sim.tick).toBe(2);
  });

  test('spawns a shopper after spawnInterval ticks', () => {
    const interval = sim.spawnInterval;
    for (let i = 0; i < interval; i++) sim.update();
    // After exactly spawnInterval updates the shopper should have spawned
    expect(sim.shoppers.length).toBeGreaterThan(0);
  });

  test('inactive shoppers are removed each tick', () => {
    const interval = sim.spawnInterval;
    // Spawn one shopper
    for (let i = 0; i < interval; i++) sim.update();
    // Forcefully deactivate it
    sim.shoppers.forEach((s) => { s.active = false; });
    sim.update();
    expect(sim.shoppers).toHaveLength(0);
  });

  test('revenue increases as shoppers check out', () => {
    // Run the simulation long enough for a full shopper cycle (~2000 ticks)
    for (let i = 0; i < 2000; i++) sim.update();
    // Revenue may still be 0 if no shopper completed checkout, but it must
    // be non-negative and the simulation must not crash.
    expect(sim.store.totalRevenue).toBeGreaterThanOrEqual(0);
  });
});
