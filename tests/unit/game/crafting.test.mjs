import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CraftingSystem } from '../../../src/game/crafting.js';
import { FurnaceLogic } from '../../../src/game/smelting.js';
import { Inventory, stack } from '../../../src/game/inventory.js';
import { loadData, registries } from '../../helpers/fixtures.mjs';

const { items } = registries();
const crafting = new CraftingSystem(loadData('recipes.json'), items);
const I = (n) => items.id(n);

function grid3(rows) {
  return rows.flatMap((r) => r.map((n) => (n ? I(n) : 0)));
}

test('a log anywhere in the grid makes four planks', () => {
  const g = [0, 0, 0, 0, I('birch_log'), 0, 0, 0, 0];
  const m = crafting.match(g, 3);
  assert.equal(m.result.id, I('birch_planks'));
  assert.equal(m.result.count, 4);
});

test('a pickaxe needs the exact shape', () => {
  const ok = crafting.match(grid3([
    ['cobblestone', 'cobblestone', 'cobblestone'],
    [null, 'stick', null],
    [null, 'stick', null],
  ]), 3);
  assert.equal(ok.result.id, I('stone_pickaxe'));
  const bad = crafting.match(grid3([
    ['cobblestone', 'cobblestone', null],
    [null, 'stick', null],
    [null, 'stick', null],
  ]), 3);
  assert.notEqual(bad?.result.id, I('stone_pickaxe'));
});

test('shaped recipes match mirrored (axe)', () => {
  const left = crafting.match(grid3([
    ['oak_planks', 'oak_planks', null],
    ['oak_planks', 'stick', null],
    [null, 'stick', null],
  ]), 3);
  const right = crafting.match(grid3([
    [null, 'spruce_planks', 'spruce_planks'],
    [null, 'stick', 'spruce_planks'],
    [null, 'stick', null],
  ]), 3);
  assert.equal(left.result.id, I('wooden_axe'));
  assert.equal(right.result.id, I('wooden_axe'));
});

test('tags let any plank type make a crafting table in the 2x2 grid', () => {
  const g = [I('oak_planks'), I('birch_planks'), I('spruce_planks'), I('oak_planks')];
  assert.equal(crafting.match(g, 2).result.id, I('crafting_table'));
});

test('recipe book lists what the inventory can make and crafts it', () => {
  const inv = new Inventory(36, items);
  inv.add(I('oak_log'), 1);
  const list2 = crafting.craftable(inv, 2).map((r) => r.result.id);
  assert.ok(list2.includes(I('oak_planks')));
  assert.ok(!list2.includes(I('crafting_table')));
  const planks = crafting.recipes.find((r) => r.result.id === I('oak_planks'));
  assert.equal(crafting.craftFromInventory(planks, inv), true);
  assert.equal(inv.count(I('oak_planks')), 4);
  assert.equal(inv.count(I('oak_log')), 0);
  assert.ok(crafting.craftable(inv, 2).some((r) => r.result.id === I('crafting_table')));
  // 3x3-only recipes are hidden from the 2x2 grid
  inv.add(I('cobblestone'), 8);
  assert.ok(!crafting.craftable(inv, 2).some((r) => r.result.id === I('furnace')));
  assert.ok(crafting.craftable(inv, 3).some((r) => r.result.id === I('furnace')));
});

test('furnace smelts with fuel and stops when fuel runs out', () => {
  const f = new FurnaceLogic(loadData('smelting.json'), items);
  const s = f.createState();
  s.input = stack(I('iron_ore'), 3);
  s.fuel = stack(I('oak_planks'), 1);
  for (let t = 0; t < 1000; t++) f.tick(s);
  // one plank = 300 ticks = 1.5 items
  assert.equal(s.output.id, I('iron_ingot'));
  assert.equal(s.output.count, 1);
  assert.equal(s.input.count, 2);
  assert.equal(s.fuel, null);
  s.fuel = stack(I('coal'), 1);
  for (let t = 0; t < 1000; t++) f.tick(s);
  assert.equal(s.output.count, 3);
  assert.equal(s.input, null);
});

test('lava bucket fuel leaves an empty bucket', () => {
  const f = new FurnaceLogic(loadData('smelting.json'), items);
  const s = f.createState();
  s.input = stack(I('sand'), 1);
  s.fuel = stack(I('lava_bucket'), 1);
  f.tick(s);
  assert.equal(s.fuel.id, I('bucket'));
});
