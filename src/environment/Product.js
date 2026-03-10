/**
 * Product – an item sold on a Bit-Market shelf.
 */
export class Product {
  /**
   * @param {string} name       Display name
   * @param {string} category   Category key (toys | food | electronics | sports)
   * @param {string} emoji      Emoji icon
   * @param {number} basePrice  Starting price in bits
   */
  constructor(name, category, emoji, basePrice) {
    this.name = name;
    this.category = category;
    this.emoji = emoji;
    this.basePrice = basePrice;
    this.price = basePrice;
  }

  /**
   * Adjust price based on demand pressure (0 = no stock; 1 = full stock).
   * Uses a simple inverse-supply curve: low stock → higher price.
   * @param {number} stockRatio  current / max stock (0..1)
   */
  updatePrice(stockRatio) {
    const multiplier = 1 + (1 - stockRatio) * 0.5; // up to +50% when empty
    this.price = Math.round(this.basePrice * multiplier * 100) / 100;
  }
}

/** Catalogue of all products available in the store, grouped by category. */
export const PRODUCT_CATALOGUE = {
  toys: [
    new Product('Teddy Bear', 'toys', '🧸', 25),
    new Product('Building Blocks', 'toys', '🪀', 15),
    new Product('Remote Car', 'toys', '🚗', 35),
    new Product('Puzzle', 'toys', '🧩', 20),
  ],
  food: [
    new Product('Lollipop', 'food', '🍭', 2),
    new Product('Chocolate', 'food', '🍫', 5),
    new Product('Cupcake', 'food', '🧁', 4),
    new Product('Gummies', 'food', '🍬', 3),
  ],
  electronics: [
    new Product('Phone', 'electronics', '📱', 199),
    new Product('Headphones', 'electronics', '🎧', 49),
    new Product('Camera', 'electronics', '📷', 89),
    new Product('Game Console', 'electronics', '🎮', 299),
  ],
  sports: [
    new Product('Football', 'sports', '⚽', 20),
    new Product('Tennis Racket', 'sports', '🎾', 30),
    new Product('Skateboard', 'sports', '🛹', 55),
    new Product('Bicycle', 'sports', '🚲', 150),
  ],
};
