import { Product, PRODUCT_CATALOGUE } from '../../src/environment/Product.js';

describe('Product', () => {
  test('constructs with correct properties', () => {
    const p = new Product('Widget', 'toys', '🧸', 25);
    expect(p.name).toBe('Widget');
    expect(p.category).toBe('toys');
    expect(p.emoji).toBe('🧸');
    expect(p.basePrice).toBe(25);
    expect(p.price).toBe(25);
  });

  test('updatePrice raises price when stock is low', () => {
    const p = new Product('Widget', 'toys', '🧸', 100);
    p.updatePrice(0); // no stock
    expect(p.price).toBeGreaterThan(100);
  });

  test('updatePrice keeps basePrice when fully stocked', () => {
    const p = new Product('Widget', 'toys', '🧸', 100);
    p.updatePrice(1); // full stock
    expect(p.price).toBe(100);
  });

  test('updatePrice caps multiplier at +50%', () => {
    const p = new Product('Widget', 'toys', '🧸', 100);
    p.updatePrice(0);
    expect(p.price).toBeLessThanOrEqual(150.01);
  });

  test('PRODUCT_CATALOGUE has all four categories', () => {
    expect(PRODUCT_CATALOGUE).toHaveProperty('toys');
    expect(PRODUCT_CATALOGUE).toHaveProperty('food');
    expect(PRODUCT_CATALOGUE).toHaveProperty('electronics');
    expect(PRODUCT_CATALOGUE).toHaveProperty('sports');
  });

  test('each catalogue category has at least one product', () => {
    for (const [, products] of Object.entries(PRODUCT_CATALOGUE)) {
      expect(products.length).toBeGreaterThan(0);
    }
  });
});
