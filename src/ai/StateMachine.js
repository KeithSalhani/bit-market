/**
 * StateMachine – drives AI behaviour through discrete named states.
 *
 * Each state is described by:
 *   enter(entity, store)  – called once when entering the state
 *   update(entity, store) – called every tick; return the name of the next
 *                           state (or null/undefined to stay in current state)
 *   exit(entity, store)   – called once when leaving the state
 */
export class StateMachine {
  /**
   * @param {Record<string, {enter?, update, exit?}>} states  State definitions
   * @param {string} initialState  Name of the starting state
   */
  constructor(states, initialState) {
    this.states = states;
    this.current = initialState;
    this._initialised = false;
  }

  /**
   * Tick the machine.  Handles deferred initialisation of the first state.
   * @param {object} entity  The entity that owns this machine
   * @param {import('../environment/Store.js').Store} store
   */
  update(entity, store) {
    // One-time entry into the initial state
    if (!this._initialised) {
      this._enter(entity, store);
      this._initialised = true;
    }

    const def = this.states[this.current];
    if (!def) return;

    const next = def.update(entity, store);
    if (next && next !== this.current) {
      this.transition(next, entity, store);
    }
  }

  /**
   * Force a transition to the named state.
   * @param {string} stateName
   * @param {object} entity
   * @param {import('../environment/Store.js').Store} store
   */
  transition(stateName, entity, store) {
    if (!this.states[stateName]) {
      throw new Error(`Unknown state: ${stateName}`);
    }

    const prev = this.states[this.current];
    if (prev && prev.exit) prev.exit(entity, store);

    this.current = stateName;
    this._enter(entity, store);
  }

  _enter(entity, store) {
    const def = this.states[this.current];
    if (def && def.enter) def.enter(entity, store);
  }
}
