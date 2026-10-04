import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Inventory, clickSlot, quickMove, stack } from '../../../src/game/inventory.js';
import { registries } from '../../helpers/fixtures.mjs';

const { items } = registries();
const dirt = items.id('dirt'), pick = items.id('iron_pickaxe'), bucket = items.id('bucket');

test('add merges into existing stacks before using empty slots', () => {
  const inv = new Inventory(36, items);
  assert.equal(inv.add(dirt, 40), 0);
  assert.equal(inv.add(dirt, 40), 0);
  assert.equal(inv.get(0).count, 64);
  assert.equal(inv.get(1).count, 16);
  assert.equal(inv.count(dirt), 80);
});

test('stack limits differ per item and overflow is reported', () => {
  const inv = new Inventory(2, items);
  assert.equal(inv.add(pick, 3), 1, 'tools do not stack');
  const inv2 = new Inventory(1, items);
  assert.equal(inv2.add(bucket, 20), 4, 'buckets stack to 16');
});

test('remove takes from the end and reports the amount', () => {
  const inv = new Inventory(4, items);
  inv.add(dirt, 70);
  assert.equal(inv.remove(dirt, 10), 10);
  assert.equal(inv.count(dirt), 60);
  assert.equal(inv.remove(dirt, 100), 60);
  assert.equal(inv.get(0), null);
});

test('primary click picks up, places, merges and swaps', () => {
  const inv = new Inventory(3, items);
  inv.set(0, stack(dirt, 10));
  let cur = clickSlot(inv, 0, null, 'primary');
  assert.deepEqual(cur, stack(dirt, 10));
  assert.equal(inv.get(0), null);
  cur = clickSlot(inv, 1, cur, 'primary');
  assert.equal(cur, null);
  inv.set(2, stack(dirt, 60));
  cur = clickSlot(inv, 1, null, 'primary');
  cur = clickSlot(inv, 2, cur, 'primary');
  assert.equal(inv.get(2).count, 64);
  assert.equal(cur.count, 6);
  inv.set(0, stack(pick, 1));
  cur = clickSlot(inv, 0, cur, 'primary');
  assert.equal(cur.id, pick, 'different items swap');
});

test('secondary click splits halves and places single items', () => {
  const inv = new Inventory(2, items);
  inv.set(0, stack(dirt, 9));
  let cur = clickSlot(inv, 0, null, 'secondary');
  assert.equal(cur.count, 5);
  assert.equal(inv.get(0).count, 4);
  cur = clickSlot(inv, 1, cur, 'secondary');
  assert.equal(inv.get(1).count, 1);
  assert.equal(cur.count, 4);
});

test('quickMove transfers between containers', () => {
  const a = new Inventory(2, items), b = new Inventory(2, items);
  a.set(0, stack(dirt, 30));
  b.set(0, stack(dirt, 50));
  assert.ok(quickMove(a, 0, b));
  assert.equal(b.get(0).count, 64);
  assert.equal(b.get(1).count, 16);
  assert.equal(a.get(0), null);
});

test('serialisation round-trips', () => {
  const inv = new Inventory(5, items);
  inv.set(1, stack(pick, 1, 17));
  inv.set(3, stack(dirt, 12));
  const copy = new Inventory(5, items);
  copy.load(JSON.parse(JSON.stringify(inv.toJSON())));
  assert.deepEqual(copy.slots, inv.slots);
});
