/**
 * Shelf – a display fixture in the store that holds a single product category.
 */
export class Shelf {
  /**
   * @param {string} id          Unique identifier
   * @param {number} x           Canvas X position (top-left corner)
   * @param {number} y           Canvas Y position (top-left corner)
   * @param {number} width       Width in pixels
   * @param {number} height      Height in pixels
   * @param {string} category    Product category this shelf stocks
   * @param {number} maxCapacity Maximum number of units that fit
   */
  constructor(id, x, y, width, height, category, maxCapacity = 8) {
    this.id = id;
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;
    this.category = category;
    this.maxCapacity = maxCapacity;
    /** @type {import('./Product.js').Product | null} Active product template */
    this.product = null;
    this.stock = 0;
  }

  /** Assign a product and fill to capacity. */
  stock_product(product) {
    this.product = product;
    this.stock = this.maxCapacity;
    this._updatePrice();
  }

  /** Remove one unit (a shopper is buying it).  Returns true if successful. */
  take() {
    if (this.stock <= 0 || !this.product) return false;
    this.stock -= 1;
    this._updatePrice();
    return true;
  }

  /**
   * Restock up to restockAmount units (capped at maxCapacity).
   * @param {number} amount Units to add
   * @returns {number} Actual units added
   */
  restock(amount) {
    const added = Math.min(amount, this.maxCapacity - this.stock);
    this.stock += added;
    this._updatePrice();
    return added;
  }

  /** True when this shelf has fewer than 30 % of its maximum stock. */
  get needsRestock() {
    return this.stock < this.maxCapacity * 0.3;
  }

  /** True when there is nothing left to buy. */
  get isEmpty() {
    return this.stock === 0;
  }

  /** Centre X of the shelf for navigation purposes. */
  get cx() {
    return this.x + this.width / 2;
  }

  /** Centre Y of the shelf for navigation purposes. */
  get cy() {
    return this.y + this.height / 2;
  }

  _updatePrice() {
    if (this.product) {
      this.product.updatePrice(this.stock / this.maxCapacity);
    }
  }
}
