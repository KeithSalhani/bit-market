import { Shelf } from './Shelf.js';
import { Checkout } from './Checkout.js';
import { PRODUCT_CATALOGUE } from './Product.js';

/**
 * Store – the central environment that holds all shelves, checkouts,
 * and spatial metadata for the simulation.
 *
 * Layout (canvas 900 × 680):
 *   Row 1 shelves  y=70
 *   Row 2 shelves  y=200
 *   Row 3 shelves  y=330
 *   Checkout row   y=470
 *   Entrance       centre-bottom (~y=600)
 */
export class Store {
  constructor(canvasWidth = 900, canvasHeight = 680) {
    this.width = canvasWidth;
    this.height = canvasHeight;

    /** @type {Shelf[]} */
    this.shelves = [];
    /** @type {Checkout[]} */
    this.checkouts = [];

    this.entranceX = canvasWidth / 2;
    this.entranceY = canvasHeight - 40;

    this._buildLayout();
  }

  _buildLayout() {
    // Four product categories → four shelf columns
    const categories = ['toys', 'food', 'electronics', 'sports'];
    const colX = [55, 255, 455, 655]; // left-edge X of each column
    const rowY = [70, 200, 330];      // top-edge Y of each row
    const shelfW = 160;
    const shelfH = 80;

    categories.forEach((cat, ci) => {
      const products = PRODUCT_CATALOGUE[cat];
      rowY.forEach((y, ri) => {
        const shelf = new Shelf(
          `shelf-${cat}-${ri}`,
          colX[ci],
          y,
          shelfW,
          shelfH,
          cat,
          8,
        );
        // Assign a different product from the catalogue to each row
        const product = products[ri % products.length];
        shelf.stock_product(product);
        this.shelves.push(shelf);
      });
    });

    // Two checkout counters
    this.checkouts.push(new Checkout('checkout-1', 200, 460));
    this.checkouts.push(new Checkout('checkout-2', 560, 460));
  }

  /** Return shelves matching a category that still have stock. */
  getAvailableShelvesByCategory(category) {
    return this.shelves.filter(
      (s) => s.category === category && !s.isEmpty,
    );
  }

  /** Return all shelves that need restocking. */
  getShelvesNeedingRestock() {
    return this.shelves.filter((s) => s.needsRestock);
  }

  /** Find the checkout with the shortest queue. */
  getShortestCheckout() {
    return this.checkouts.reduce((best, c) =>
      c.queueLength < best.queueLength ? c : best,
    );
  }

  /** Total store revenue across all checkouts. */
  get totalRevenue() {
    return this.checkouts.reduce((sum, c) => sum + c.totalRevenue, 0);
  }

  /** Total customers served across all checkouts. */
  get totalCustomersServed() {
    return this.checkouts.reduce((sum, c) => sum + c.customersServed, 0);
  }
}
