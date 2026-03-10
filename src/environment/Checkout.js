/**
 * Checkout – a counter where shoppers pay for their goods.
 * Managed by a Clerk entity.
 */
export class Checkout {
  /**
   * @param {string} id   Unique identifier
   * @param {number} x    Canvas X position (top-left)
   * @param {number} y    Canvas Y position (top-left)
   */
  constructor(id, x, y) {
    this.id = id;
    this.x = x;
    this.y = y;
    this.width = 120;
    this.height = 60;
    /** Ordered list of shopper IDs waiting/being served. */
    this.queue = [];
    this.maxQueueLength = 6;
    /** True while a transaction is in progress. */
    this.busy = false;
    this.totalRevenue = 0;
    this.customersServed = 0;
  }

  /** Attempt to join the queue. Returns true if the shopper was admitted. */
  enqueue(shopperId) {
    if (this.queue.length >= this.maxQueueLength) return false;
    this.queue.push(shopperId);
    return true;
  }

  /** Remove the shopper at the front of the queue after they have paid. */
  dequeue() {
    if (this.queue.length === 0) return null;
    const id = this.queue.shift();
    this.customersServed += 1;
    return id;
  }

  /** Accept a payment and record the revenue. */
  processPayment(amount) {
    this.totalRevenue += amount;
    this.busy = false;
  }

  /** Position of the front-of-queue waiting spot. */
  get queueEntryX() {
    return this.x + this.width / 2;
  }

  get queueEntryY() {
    return this.y + this.height + 20;
  }

  /** Service position (where shopper stands to be served). */
  get serviceX() {
    return this.x + this.width / 2;
  }

  get serviceY() {
    return this.y - 20;
  }

  get queueLength() {
    return this.queue.length;
  }
}
