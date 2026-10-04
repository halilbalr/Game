import { test } from 'node:test';
import assert from 'node:assert/strict';
import { flatWorld, registries } from '../../helpers/fixtures.mjs';
import { LiquidSystem } from '../../../src/world/liquids.js';

const { blocks } = registries();
const cfg = { water: { tickDelay: 5, spread: 7 }, lava: { tickDelay: 30, spread: 3 }, maxUpdatesPerTick: 1000 };

function run(liq, ticks) { for (let i = 0; i < ticks; i++) liq.update(); }

test('a water source spreads seven blocks across flat ground then stops', () => {
  const w = flatWorld(1);
  const liq = new LiquidSystem(w, blocks, cfg);
  const water = blocks.id('water');
  w.setBlock(0, 64, 0, water, 0);
  run(liq, 200);
  assert.equal(w.getBlock(7, 64, 0), water);
  assert.equal(w.getMeta(7, 64, 0), 7);
  assert.equal(w.getBlock(8, 64, 0), 0);
  assert.equal(w.getMeta(3, 64, 0), 3);
  assert.equal(liq.pendingCount, 0, 'flow settles');
});

test('removing the source dries the flow', () => {
  const w = flatWorld(1);
  const liq = new LiquidSystem(w, blocks, cfg);
  const water = blocks.id('water');
  w.setBlock(0, 64, 0, water, 0);
  run(liq, 200);
  w.setBlock(0, 64, 0, 0);
  run(liq, 400);
  for (let x = -8; x <= 8; x++) assert.equal(w.getBlock(x, 64, 0), 0, `x=${x}`);
});

test('water falls down a hole', () => {
  const w = flatWorld(1);
  const liq = new LiquidSystem(w, blocks, cfg);
  const water = blocks.id('water');
  for (let y = 55; y <= 63; y++) w.setBlock(2, y, 0, 0);
  w.setBlock(0, 64, 0, water, 0);
  run(liq, 300);
  assert.equal(w.getBlock(2, 55, 0), water);
});

test('two adjacent sources create a new source (infinite water)', () => {
  const w = flatWorld(1);
  const liq = new LiquidSystem(w, blocks, cfg);
  const water = blocks.id('water'), stone = blocks.id('stone');
  // 3x1 trench walled in
  for (let x = -1; x <= 3; x++) { w.setBlock(x, 64, -1, stone); w.setBlock(x, 64, 1, stone); }
  w.setBlock(-1, 64, 0, stone); w.setBlock(3, 64, 0, stone);
  w.setBlock(0, 64, 0, water, 0);
  w.setBlock(2, 64, 0, water, 0);
  run(liq, 100);
  assert.equal(w.getBlock(1, 64, 0), water);
  assert.equal(w.getMeta(1, 64, 0), 0);
});

test('water meeting lava source makes obsidian', () => {
  const w = flatWorld(1);
  const liq = new LiquidSystem(w, blocks, cfg);
  const water = blocks.id('water'), lava = blocks.id('lava');
  w.setBlock(3, 64, 0, lava, 0);
  w.setBlock(0, 64, 0, water, 0);
  run(liq, 200);
  assert.equal(w.getBlock(3, 64, 0), blocks.id('obsidian'));
});
