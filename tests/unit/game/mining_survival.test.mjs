import { test } from 'node:test';
import assert from 'node:assert/strict';
import { breakSeconds, canHarvest, dropsFor } from '../../../src/game/mining.js';
import { Survival } from '../../../src/game/survival.js';
import { mulberry32 } from '../../../src/core/random.js';
import { loadData, registries } from '../../helpers/fixtures.mjs';

const { blocks, items } = registries();
const def = (n) => blocks.get(blocks.id(n));
const item = (n) => items.get(items.id(n));

test('break times follow hardness and tool speed', () => {
  // stone: hardness 1.5. Bare hand cannot harvest -> 1.5*100/1 ticks = 150 ticks = 7.5 s
  assert.equal(breakSeconds(def('stone'), undefined), 7.5);
  // wooden pickaxe: speed 2, harvestable -> 1.5*30/2 = 22.5 -> 23 ticks
  assert.equal(breakSeconds(def('stone'), item('wooden_pickaxe')), 23 / 20);
  // diamond pickaxe speed 8 -> 1.5*30/8 = 5.625 -> 6 ticks
  assert.equal(breakSeconds(def('stone'), item('diamond_pickaxe')), 6 / 20);
  // dirt by hand: 0.5*30 = 15 ticks
  assert.equal(breakSeconds(def('dirt'), undefined), 0.75);
  assert.equal(breakSeconds(def('bedrock'), item('diamond_pickaxe')), Infinity);
  assert.equal(breakSeconds(def('tall_grass'), undefined), 0);
  // airborne mining is five times slower
  assert.equal(breakSeconds(def('dirt'), undefined, { onGround: false }), 75 / 20);
});

test('ores need the right pickaxe tier', () => {
  assert.equal(canHarvest(def('iron_ore'), item('wooden_pickaxe')), false);
  assert.equal(canHarvest(def('iron_ore'), item('stone_pickaxe')), true);
  assert.equal(canHarvest(def('diamond_ore'), item('stone_pickaxe')), false);
  assert.equal(canHarvest(def('diamond_ore'), item('iron_pickaxe')), true);
  assert.equal(canHarvest(def('obsidian'), item('iron_pickaxe')), false);
  assert.equal(canHarvest(def('dirt'), undefined), true);
});

test('drops: stone gives cobblestone, ripe wheat gives wheat', () => {
  const r = mulberry32(1);
  assert.deepEqual(dropsFor(def('stone'), 0, item('wooden_pickaxe'), r, items), [{ id: items.id('cobblestone'), count: 1 }]);
  assert.deepEqual(dropsFor(def('stone'), 0, undefined, r, items), []);
  const ripe = dropsFor(def('wheat_crop'), 7, undefined, r, items);
  assert.ok(ripe.some((d) => d.id === items.id('wheat')));
  const young = dropsFor(def('wheat_crop'), 2, undefined, r, items);
  assert.deepEqual(young, [{ id: items.id('wheat_seeds'), count: 1 }]);
  const clay = dropsFor(def('clay'), 0, undefined, r, items);
  assert.deepEqual(clay, [{ id: items.id('clay_ball'), count: 4 }]);
});

const scfg = loadData('player.json').survival;

test('fall damage is distance minus three', () => {
  const s = new Survival(scfg);
  assert.equal(s.onLanded(3), 0);
  assert.equal(s.onLanded(5.5), 3);
  assert.equal(s.health, 17);
});

test('drowning starts after the air supply runs out', () => {
  const s = new Survival(scfg);
  for (let t = 0; t < scfg.maxAirTicks; t++) s.tick({ headInWater: true });
  assert.equal(s.health, 20);
  for (let t = 0; t < 25; t++) s.tick({ headInWater: true });
  assert.equal(s.health, 18);
  for (let t = 0; t < 3; t++) s.tick({ headInWater: false });
  assert.ok(s.air > 0, 'breath recovers out of water');
});

test('exhaustion drains saturation, then food; low food stops regeneration', () => {
  const s = new Survival(scfg);
  s.saturation = 1;
  s.addExhaustion(4.5);
  s.tick({});
  assert.equal(s.saturation, 0);
  assert.equal(s.food, 20);
  s.addExhaustion(8);
  s.tick({});
  assert.equal(s.food, 18);
  s.health = 10;
  s.food = 10;
  for (let t = 0; t < 400; t++) s.tick({});
  assert.equal(s.health, 10);
});

test('starvation on normal difficulty does not kill below half a heart', () => {
  const s = new Survival(scfg, 'normal');
  s.food = 0; s.saturation = 0; s.health = 3;
  for (let t = 0; t < 2000; t++) s.tick({});
  assert.equal(s.health, 1);
  assert.equal(s.dead, false);
});

test('eating restores food and saturation', () => {
  const s = new Survival(scfg);
  s.food = 10; s.saturation = 0;
  s.eat(item('steak').food);
  assert.equal(s.food, 18);
  assert.equal(s.saturation, 12.8);
});

test('invulnerability frames block rapid repeated damage', () => {
  const s = new Survival(scfg);
  s.saturation = 0;
  s.food = 17; // below the regeneration threshold so healing does not interfere
  assert.ok(s.damage(4, 'mob'));
  assert.ok(!s.damage(4, 'mob'));
  for (let t = 0; t < scfg.invulnerableTicks; t++) s.tick({});
  assert.ok(s.damage(4, 'mob'));
  assert.equal(s.health, 12);
});
