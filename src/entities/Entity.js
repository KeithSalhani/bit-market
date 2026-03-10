/**
 * Entity – abstract base class for all AI lifeforms in the Bit-Market.
 */
export class Entity {
  /**
   * @param {string} id   Unique identifier
   * @param {number} x    Initial canvas X
   * @param {number} y    Initial canvas Y
   */
  constructor(id, x, y) {
    this.id = id;
    this.x = x;
    this.y = y;
    this.radius = 14;
    this.speed = 1.5;
    /** @type {import('../ai/StateMachine.js').StateMachine | null} */
    this.stateMachine = null;
    this.active = true;
  }

  /**
   * Move one step toward (tx, ty).
   * @returns {boolean} true when the destination is reached
   */
  moveTo(tx, ty) {
    const dx = tx - this.x;
    const dy = ty - this.y;
    const dist = Math.hypot(dx, dy);
    if (dist <= this.speed) {
      this.x = tx;
      this.y = ty;
      return true;
    }
    this.x += (dx / dist) * this.speed;
    this.y += (dy / dist) * this.speed;
    return false;
  }

  /**
   * Euclidean distance to another entity (or {x,y} object).
   * @param {{ x: number, y: number }} other
   */
  distanceTo(other) {
    return Math.hypot(other.x - this.x, other.y - this.y);
  }

  /**
   * Update AI logic for this tick.
   * @param {import('../environment/Store.js').Store} store
   */
  update(store) {
    if (this.stateMachine) {
      this.stateMachine.update(this, store);
    }
  }
}
