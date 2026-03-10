import { Entity } from './Entity.js';
import { StateMachine } from '../ai/StateMachine.js';

let _clerkCount = 0;

/**
 * Clerk – an autonomous checkout operator AI lifeform.
 *
 * States:
 *   IDLE → BECKONING → SERVING
 */
export class Clerk extends Entity {
  /**
   * @param {import('../environment/Checkout.js').Checkout} checkout
   *        The counter this clerk operates.
   */
  constructor(checkout) {
    _clerkCount += 1;
    super(`clerk-${_clerkCount}`, checkout.serviceX, checkout.y - 30);
    this.checkout = checkout;
    this.radius = 14;
    this.speed = 0; // clerks stay behind their counter
    this.color = '#6C5CE7';
    this.hat = true;

    this.stateMachine = this._buildStateMachine();
  }

  _buildStateMachine() {
    return new StateMachine(
      {
        IDLE: {
          update: (e) => {
            if (e.checkout.queueLength > 0) return 'BECKONING';
          },
        },

        BECKONING: {
          update: (e) => {
            // Wait for first shopper to reach service position
            if (e.checkout.queueLength > 0) {
              return 'SERVING';
            }
            return 'IDLE';
          },
        },

        SERVING: {
          update: (e) => {
            if (e.checkout.queueLength === 0) return 'IDLE';
            // Mark the counter busy so the simulation knows a transaction
            // is in progress (the shopper drives the timer via CHECKING_OUT).
            e.checkout.busy = true;
          },
        },
      },
      'IDLE',
    );
  }
}
