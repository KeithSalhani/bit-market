import { Entity } from './Entity.js';
import { StateMachine } from '../ai/StateMachine.js';

let _botCount = 0;

/**
 * StoreBot – an autonomous restocking robot AI lifeform.
 *
 * States:
 *   IDLE → SCANNING → MOVING_TO_WAREHOUSE → LOADING → MOVING_TO_SHELF → RESTOCKING
 */
export class StoreBot extends Entity {
  /**
   * @param {number} x  Spawn X (warehouse staging area)
   * @param {number} y  Spawn Y
   */
  constructor(x, y) {
    _botCount += 1;
    super(`bot-${_botCount}`, x, y);
    this.radius = 16;
    this.speed = 1.2;
    this.color = '#C8D6E5';
    this.accentColor = '#576574';

    /** Units the bot is currently carrying. */
    this.carryAmount = 0;
    this.carryCapacity = 8;
    /** The shelf this bot is heading to restock. */
    this.targetShelf = null;
    this.activityTimer = 0;
    /** Home/warehouse position. */
    this.homeX = x;
    this.homeY = y;

    this.stateMachine = this._buildStateMachine();
  }

  _buildStateMachine() {
    return new StateMachine(
      {
        IDLE: {
          enter: (e) => {
            e.activityTimer = 30 + Math.floor(Math.random() * 30);
          },
          update: (e) => {
            e.activityTimer -= 1;
            if (e.activityTimer <= 0) return 'SCANNING';
          },
        },

        SCANNING: {
          update: (e, store) => {
            const needyShelf = store
              .getShelvesNeedingRestock()
              .sort((a, b) => a.stock - b.stock)[0];

            if (needyShelf) {
              e.targetShelf = needyShelf;
              return 'MOVING_TO_WAREHOUSE';
            }
            // Nothing to do – back to idle
            return 'IDLE';
          },
        },

        MOVING_TO_WAREHOUSE: {
          update: (e) => {
            const arrived = e.moveTo(e.homeX, e.homeY);
            if (arrived) return 'LOADING';
          },
        },

        LOADING: {
          enter: (e) => {
            e.activityTimer = 60;
          },
          update: (e) => {
            e.activityTimer -= 1;
            if (e.activityTimer <= 0) {
              e.carryAmount = e.carryCapacity;
              return 'MOVING_TO_SHELF';
            }
          },
        },

        MOVING_TO_SHELF: {
          update: (e) => {
            if (!e.targetShelf) return 'IDLE';
            const arrived = e.moveTo(
              e.targetShelf.cx,
              e.targetShelf.cy - 30,
            );
            if (arrived) return 'RESTOCKING';
          },
        },

        RESTOCKING: {
          enter: (e) => {
            e.activityTimer = 90;
          },
          update: (e) => {
            e.activityTimer -= 1;
            if (e.activityTimer <= 0) {
              if (e.targetShelf) {
                const added = e.targetShelf.restock(e.carryAmount);
                e.carryAmount -= added;
              }
              e.targetShelf = null;
              return 'IDLE';
            }
          },
        },
      },
      'IDLE',
    );
  }
}
