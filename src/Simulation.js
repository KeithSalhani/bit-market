import { Store } from './environment/Store.js';
import { Shopper } from './entities/Shopper.js';
import { StoreBot } from './entities/StoreBot.js';
import { Clerk } from './entities/Clerk.js';

/**
 * Simulation – the autonomous core that drives the entire Bit-Market ecosystem.
 *
 * Call `tick()` once per animation frame.  The simulation manages entity
 * lifecycles, spawn rates, and global statistics.
 */
export class Simulation {
  /**
   * @param {number} canvasWidth
   * @param {number} canvasHeight
   */
  constructor(canvasWidth = 900, canvasHeight = 680) {
    this.store = new Store(canvasWidth, canvasHeight);

    /** @type {Shopper[]} */
    this.shoppers = [];
    /** @type {StoreBot[]} */
    this.storeBots = [];
    /** @type {Clerk[]} */
    this.clerks = [];

    this.tick = 0;
    /** How often (in ticks) to spawn a new shopper. */
    this.spawnInterval = 180; // ~3 s at 60 fps

    this._lastSpawn = 0;

    this._init();
  }

  _init() {
    // One StoreBot per product category warehouse lane
    const warehouseY = 20;
    const laneX = [135, 335, 535, 735];
    laneX.forEach((x) => {
      this.storeBots.push(new StoreBot(x, warehouseY));
    });

    // One Clerk per checkout counter
    this.store.checkouts.forEach((co) => {
      this.clerks.push(new Clerk(co));
    });
  }

  /** Advance the simulation by one tick. */
  update() {
    this.tick += 1;

    // Spawn shoppers at regular intervals
    if (this.tick - this._lastSpawn >= this.spawnInterval) {
      this._spawnShopper();
      this._lastSpawn = this.tick;
    }

    // Update all active shoppers; remove those that have left
    for (let i = this.shoppers.length - 1; i >= 0; i--) {
      const s = this.shoppers[i];
      s.update(this.store);
      if (!s.active) this.shoppers.splice(i, 1);
    }

    // Update bots and clerks
    this.storeBots.forEach((b) => b.update(this.store));
    this.clerks.forEach((c) => c.update(this.store));
  }

  _spawnShopper() {
    const s = new Shopper(this.store.entranceX, this.store.entranceY);
    this.shoppers.push(s);
  }

  /**
   * Summary of the simulation's current state (useful for a stats overlay).
   * @returns {{ tick: number, shoppers: number, bots: number,
   *             revenue: number, served: number }}
   */
  getStats() {
    return {
      tick: this.tick,
      shoppers: this.shoppers.length,
      bots: this.storeBots.length,
      revenue: this.store.totalRevenue,
      served: this.store.totalCustomersServed,
    };
  }
}
