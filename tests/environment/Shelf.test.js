import { Shelf } from '../../src/environment/Shelf.js';
import { Product } from '../../src/environment/Product.js';

function makeShelf(capacity = 8) {
  return new Shelf('s1', 100, 100, 160, 80, 'toys', capacity);
}

describe('Shelf', () => {
  test('constructs with correct properties', () => {
    const shelf = makeShelf();
    expect(shelf.id).toBe('s1');
    expect(shelf.category).toBe('toys');
    expect(shelf.maxCapacity).toBe(8);
    expect(shelf.stock).toBe(0);
    expect(shelf.product).toBeNull();
  });

  test('stock_product fills shelf to capacity', () => {
    const shelf = makeShelf(6);
    const product = new Product('Bear', 'toys', '🧸', 10);
    shelf.stock_product(product);
    expect(shelf.stock).toBe(6);
    expect(shelf.product).toBe(product);
  });

  test('take() decrements stock and returns true', () => {
    const shelf = makeShelf(4);
    shelf.stock_product(new Product('Bear', 'toys', '🧸', 10));
    const result = shelf.take();
    expect(result).toBe(true);
    expect(shelf.stock).toBe(3);
  });

  test('take() returns false when empty', () => {
    const shelf = makeShelf(1);
    shelf.stock_product(new Product('Bear', 'toys', '🧸', 10));
    shelf.take(); // empties shelf
    const result = shelf.take();
    expect(result).toBe(false);
    expect(shelf.stock).toBe(0);
  });

  test('isEmpty is true when stock is 0', () => {
    const shelf = makeShelf(1);
    shelf.stock_product(new Product('Bear', 'toys', '🧸', 10));
    shelf.take();
    expect(shelf.isEmpty).toBe(true);
  });

  test('needsRestock when below 30% capacity', () => {
    const shelf = makeShelf(10);
    shelf.stock_product(new Product('Bear', 'toys', '🧸', 10));
    // 8/10 full – should NOT need restock
    expect(shelf.needsRestock).toBe(false);
    // Drain to 2/10 (20%)
    for (let i = 0; i < 8; i++) shelf.take();
    expect(shelf.needsRestock).toBe(true);
  });

  test('restock adds correct units and caps at maxCapacity', () => {
    const shelf = makeShelf(8);
    shelf.stock_product(new Product('Bear', 'toys', '🧸', 10));
    shelf.take(); shelf.take(); // stock = 6
    const added = shelf.restock(10); // try to add 10, but only 2 fit
    expect(added).toBe(2);
    expect(shelf.stock).toBe(8);
  });

  test('cx and cy return shelf centre', () => {
    const shelf = new Shelf('s2', 100, 200, 160, 80, 'food');
    expect(shelf.cx).toBe(180);
    expect(shelf.cy).toBe(240);
  });
});
