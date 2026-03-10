import { Entity } from './Entity.js';
import { StateMachine } from '../ai/StateMachine.js';

/** Personality archetypes that influence shopping behaviour. */
const ARCHETYPES = [
  { name: 'Impulsive', color: '#FF6B6B', budget: 300, listSize: 4, speed: 2.0 },
  { name: 'Budget',    color: '#48DBFB', budget: 50,  listSize: 2, speed: 1.4 },
  { name: 'Explorer',  color: '#1DD1A1', budget: 200, listSize: 3, speed: 1.6 },
  { name: 'Rushed',    color: '#FECA57', budget: 150, listSize: 1, speed: 2.5 },
];

let _shopperCount = 0;

/**
 * Shopper – an autonomous customer AI lifeform.
 *
 * States:
 *   ENTERING → BROWSING → MOVING_TO_SHELF → SHOPPING →
 *   MOVING_TO_CHECKOUT → QUEUING → CHECKING_OUT → LEAVING
 */
export class Shopper extends Entity {
  /**
   * @param {number} x  Spawn X (typically the store entrance)
   * @param {number} y  Spawn Y
   */
  constructor(x, y) {
    const archetype = ARCHETYPES[_shopperCount % ARCHETYPES.length];
    _shopperCount += 1;
    super(`shopper-${_shopperCount}`, x, y);

    this.archetype = archetype.name;
    this.color = archetype.color;
    this.speed = archetype.speed;
    this.budget = archetype.budget;
    this.remainingBudget = archetype.budget;

    /** Categories the shopper wants to visit. */
    this.shoppingList = this._buildList(archetype.listSize);
    /** Items added to cart: array of {product, price}. */
    this.cart = [];
    /** Ticks remaining at current activity (browsing/shopping/checkout). */
    this.activityTimer = 0;
    /** Current shelf being shopped. */
    this.targetShelf = null;
    /** Checkout counter this shopper is queuing at. */
    this.targetCheckout = null;
    /** Happiness score (0–100). */
    this.happiness = 80;

    this.stateMachine = this._buildStateMachine();
  }

  /** Build a random shopping list of category strings. */
  _buildList(size) {
    const all = ['toys', 'food', 'electronics', 'sports'];
    const shuffled = all.sort(() => Math.random() - 0.5);
    return shuffled.slice(0, size);
  }

  /** Total cost of items in cart. */
  get cartTotal() {
    return this.cart.reduce((s, item) => s + item.price, 0);
  }

  _buildStateMachine() {
    return new StateMachine(
      {
        ENTERING: {
          enter: (e, store) => {
            e.activityTimer = 40;
          },
          update: (e, store) => {
            // Walk toward the first aisle
            const arrived = e.moveTo(store.entranceX, store.entranceY - 80);
            e.activityTimer -= 1;
            if (arrived || e.activityTimer <= 0) return 'BROWSING';
          },
        },

        BROWSING: {
          enter: (e) => {
            e.targetShelf = null;
            e.activityTimer = 20 + Math.floor(Math.random() * 40);
          },
          update: (e, store) => {
            e.activityTimer -= 1;

            // Check if we still have items on the shopping list
            if (e.shoppingList.length === 0 || e.remainingBudget <= 0) {
              return 'MOVING_TO_CHECKOUT';
            }

            if (e.activityTimer <= 0) {
              // Pick the next category and find a shelf
              const category = e.shoppingList[0];
              const available = store.getAvailableShelvesByCategory(category);
              if (available.length > 0) {
                e.targetShelf =
                  available[Math.floor(Math.random() * available.length)];
                return 'MOVING_TO_SHELF';
              }
              // No stock for this category – cross it off the list and try again
              e.shoppingList.shift();
              e.happiness = Math.max(0, e.happiness - 10);
              e.activityTimer = 20;
            }
          },
        },

        MOVING_TO_SHELF: {
          update: (e) => {
            if (!e.targetShelf) return 'BROWSING';
            const arrived = e.moveTo(e.targetShelf.cx, e.targetShelf.cy + 30);
            if (arrived) return 'SHOPPING';
          },
        },

        SHOPPING: {
          enter: (e) => {
            e.activityTimer = 60 + Math.floor(Math.random() * 120);
          },
          update: (e, store) => {
            e.activityTimer -= 1;
            if (e.activityTimer <= 0) {
              const shelf = e.targetShelf;
              if (shelf && !shelf.isEmpty && shelf.product) {
                const price = shelf.product.price;
                if (price <= e.remainingBudget) {
                  if (shelf.take()) {
                    e.cart.push({ name: shelf.product.name, price, emoji: shelf.product.emoji });
                    e.remainingBudget -= price;
                    e.happiness = Math.min(100, e.happiness + 5);
                  }
                } else {
                  // Too expensive
                  e.happiness = Math.max(0, e.happiness - 5);
                }
              } else {
                e.happiness = Math.max(0, e.happiness - 8);
              }
              // Cross the category off the list
              e.shoppingList.shift();
              return 'BROWSING';
            }
          },
        },

        MOVING_TO_CHECKOUT: {
          enter: (e, store) => {
            // Try both checkouts; if all queues are full just leave
            const sorted = [...store.checkouts].sort(
              (a, b) => a.queueLength - b.queueLength,
            );
            for (const co of sorted) {
              if (co.enqueue(e.id)) {
                e.targetCheckout = co;
                return;
              }
            }
            // All queues full – give up
            e.targetCheckout = null;
          },
          update: (e) => {
            if (!e.targetCheckout) return 'LEAVING';
            const co = e.targetCheckout;
            const arrived = e.moveTo(co.queueEntryX, co.queueEntryY);
            if (arrived) return 'QUEUING';
          },
        },

        QUEUING: {
          update: (e) => {
            if (!e.targetCheckout) return 'LEAVING';
            const co = e.targetCheckout;
            // Move to service position when we're first in queue
            if (co.queue[0] === e.id) {
              const arrived = e.moveTo(co.serviceX, co.serviceY);
              if (arrived) return 'CHECKING_OUT';
            }
          },
        },

        CHECKING_OUT: {
          enter: (e) => {
            e.activityTimer = 120 + Math.floor(Math.random() * 120);
          },
          update: (e, store) => {
            e.activityTimer -= 1;
            if (e.activityTimer <= 0) {
              const co = e.targetCheckout;
              if (co) {
                co.processPayment(e.cartTotal);
                co.dequeue();
              }
              return 'LEAVING';
            }
          },
        },

        LEAVING: {
          update: (e, store) => {
            const arrived = e.moveTo(store.entranceX, store.entranceY + 60);
            if (arrived) {
              e.active = false;
            }
          },
        },
      },
      'ENTERING',
    );
  }
}
