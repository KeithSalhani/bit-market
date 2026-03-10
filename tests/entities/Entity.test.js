import { Entity } from '../../src/entities/Entity.js';

describe('Entity', () => {
  test('constructs with correct default properties', () => {
    const e = new Entity('e1', 100, 200);
    expect(e.id).toBe('e1');
    expect(e.x).toBe(100);
    expect(e.y).toBe(200);
    expect(e.radius).toBe(14);
    expect(e.active).toBe(true);
  });

  test('moveTo returns true when destination is within speed', () => {
    const e = new Entity('e1', 0, 0);
    e.speed = 5;
    const arrived = e.moveTo(3, 4); // distance = 5 exactly
    expect(arrived).toBe(true);
    expect(e.x).toBe(3);
    expect(e.y).toBe(4);
  });

  test('moveTo returns false and advances when far away', () => {
    const e = new Entity('e1', 0, 0);
    e.speed = 1.5;
    const arrived = e.moveTo(100, 0);
    expect(arrived).toBe(false);
    expect(e.x).toBeCloseTo(1.5);
    expect(e.y).toBeCloseTo(0);
  });

  test('distanceTo measures Euclidean distance', () => {
    const e = new Entity('e1', 0, 0);
    const other = { x: 3, y: 4 };
    expect(e.distanceTo(other)).toBeCloseTo(5);
  });

  test('update calls stateMachine.update when present', () => {
    const e = new Entity('e1', 0, 0);
    let called = false;
    e.stateMachine = { update: () => { called = true; } };
    e.update({});
    expect(called).toBe(true);
  });
});
