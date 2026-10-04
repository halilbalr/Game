import { test } from 'node:test';
import assert from 'node:assert/strict';
import { flatWorld, registries } from '../../helpers/fixtures.mjs';

const { blocks } = registries();

test('open sky is full brightness down to the ground', () => {
  const w = flatWorld(1);
  assert.equal(w.getSkyLight(5, 64, 5), 15);
  assert.equal(w.getSkyLight(5, 100, 5), 15);
  assert.equal(w.getSkyLight(5, 63, 5), 0, 'inside the grass block');
});

test('placing a roof casts a shadow that falls off with distance', () => {
  const w = flatWorld(1);
  const stone = blocks.id('stone');
  // 7x7 roof at y=66 centred on (0, 0) -> cell under centre gets light from the sides.
  for (let x = -3; x <= 3; x++) for (let z = -3; z <= 3; z++) w.setBlock(x, 66, z, stone);
  assert.equal(w.getSkyLight(0, 70, 0), 15);
  const centre = w.getSkyLight(0, 65, 0);
  const edge = w.getSkyLight(3, 65, 0);
  assert.ok(centre < 15 && edge < 15, `centre=${centre} edge=${edge}`);
  assert.ok(centre < edge, 'centre should be darker than edge');
  assert.equal(centre, 15 - 4, 'four steps from open sky');
  // removing the roof restores full light
  for (let x = -3; x <= 3; x++) for (let z = -3; z <= 3; z++) w.setBlock(x, 66, z, 0);
  assert.equal(w.getSkyLight(0, 65, 0), 15);
});

test('a torch lights its surroundings and removing it darkens them', () => {
  const w = flatWorld(1);
  const stone = blocks.id('stone'), torch = blocks.id('torch');
  // carve a sealed cave at y=40
  for (let x = -6; x <= 6; x++) for (let z = -1; z <= 1; z++) w.setBlock(x, 40, z, 0);
  assert.equal(w.getBlockLight(0, 40, 0), 0);
  assert.equal(w.getSkyLight(0, 40, 0), 0);
  w.setBlock(0, 40, 0, torch);
  assert.equal(w.getBlockLight(0, 40, 0), 14);
  assert.equal(w.getBlockLight(3, 40, 0), 11);
  assert.equal(w.getBlockLight(6, 40, 1), 7);
  w.setBlock(0, 40, 0, 0);
  assert.equal(w.getBlockLight(3, 40, 0), 0);
  void stone;
});

test('light crosses chunk borders', () => {
  const w = flatWorld(1);
  const torch = blocks.id('torch');
  for (let x = 12; x <= 20; x++) w.setBlock(x, 40, 0, 0);
  w.setBlock(14, 40, 0, torch);
  assert.equal(w.getBlockLight(17, 40, 0), 11);
  assert.equal(w.getBlockLight(20, 40, 0), 8);
});

test('leaves and water filter light', () => {
  const w = flatWorld(1);
  const leaves = blocks.id('oak_leaves'), water = blocks.id('water');
  w.setBlock(2, 64, 2, 0);
  for (let x = -1; x <= 5; x++) for (let z = -1; z <= 5; z++) w.setBlock(x, 70, z, leaves);
  assert.ok(w.getSkyLight(2, 69, 2) < 15);
  const w2 = flatWorld(1);
  // dig a pit and fill it with water
  for (let y = 55; y <= 63; y++) for (let x = -4; x <= 4; x++) for (let z = -4; z <= 4; z++) w2.setBlock(x, y, z, water);
  assert.ok(w2.getSkyLight(0, 55, 0) < w2.getSkyLight(0, 62, 0));
});

test('meshes are invalidated where light changes', () => {
  const w = flatWorld(1);
  for (const c of w.chunks.values()) c.dirtyMask = 0;
  w.dirtyChunks.clear();
  w.setBlock(15, 70, 15, blocks.id('glowstone'));
  assert.ok(w.dirtyChunks.size >= 1);
  const c = w.getChunk(0, 0);
  assert.ok(c.dirtyMask & (1 << 4));
});
