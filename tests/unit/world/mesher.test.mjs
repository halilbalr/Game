import { test } from 'node:test';
import assert from 'node:assert/strict';
import { flatWorld, registries, loadData } from '../../helpers/fixtures.mjs';
import { Mesher } from '../../../src/render/mesher.js';
import { buildAtlas, collectTextureNames } from '../../../src/render/textures.js';

const { blocks, items } = registries();
const atlas = buildAtlas(collectTextureNames(blocks, items), loadData('textures.json'), loadData('sprites.json'));
blocks.bindAtlas((n) => atlas.tile(n));

function quads(mesh) { return mesh ? mesh.vertexCount / 4 : 0; }

test('a flat ground section only exposes its top faces', () => {
  const w = flatWorld(1);
  const m = new Mesher(blocks, atlas);
  // section 3 covers y=48..63, ground top at 63
  const { opaque, translucent } = m.build(w, w.getChunk(0, 0), 3);
  assert.equal(quads(opaque), 256, 'one top face per column');
  assert.equal(translucent, null);
  // all those faces point up: every vertex at y = 16 (local)
  for (let i = 1; i < opaque.position.length; i += 3) assert.equal(opaque.position[i], 16);
});

test('a lone block in the air has six faces with no occlusion', () => {
  const w = flatWorld(1);
  w.setBlock(5, 80, 5, blocks.id('stone'));
  const m = new Mesher(blocks, atlas);
  const { opaque } = m.build(w, w.getChunk(0, 0), 5);
  assert.equal(quads(opaque), 6);
  // shade byte = 255 * AO(1.0) * faceShade -> top face 255
  const shades = new Set();
  for (let i = 2; i < opaque.light.length; i += 4) shades.add(opaque.light[i]);
  assert.ok(shades.has(255));
});

test('ambient occlusion darkens vertices in a corner', () => {
  const w = flatWorld(1);
  const stone = blocks.id('stone');
  w.setBlock(4, 64, 4, stone); // block sitting on the ground next to (5, 64, 4)
  const m = new Mesher(blocks, atlas);
  const { opaque } = m.build(w, w.getChunk(0, 0), 3);
  // ground top faces adjacent to the placed block get AO < 1 at shared vertices
  let darker = 0;
  for (let i = 2; i < opaque.light.length; i += 4) if (opaque.light[i] < 255) darker++;
  assert.ok(darker >= 4);
});

test('water renders into the translucent mesh with a lowered surface', () => {
  const w = flatWorld(1);
  const water = blocks.id('water');
  w.setBlock(3, 64, 3, water, 0);
  const m = new Mesher(blocks, atlas);
  const { translucent } = m.build(w, w.getChunk(0, 0), 4);
  assert.ok(translucent);
  let maxY = 0;
  for (let i = 1; i < translucent.position.length; i += 3) maxY = Math.max(maxY, translucent.position[i]);
  assert.ok(maxY < 1.0 + 0.0001 && maxY > 0.8, `surface height ${maxY}`);
});

test('leaves next to leaves cull shared faces', () => {
  const w = flatWorld(1);
  const leaves = blocks.id('oak_leaves');
  w.setBlock(2, 80, 2, leaves);
  w.setBlock(3, 80, 2, leaves);
  const m = new Mesher(blocks, atlas);
  const { opaque } = m.build(w, w.getChunk(0, 0), 5);
  assert.equal(quads(opaque), 10);
});

test('plants become crossed quads', () => {
  const w = flatWorld(1);
  w.setBlock(6, 64, 6, blocks.id('red_flower'));
  const m = new Mesher(blocks, atlas);
  const { opaque } = m.build(w, w.getChunk(0, 0), 4);
  assert.equal(quads(opaque), 4, 'two diagonal planes, both windings');
});

test('atlas covers every texture the registries reference', () => {
  for (const name of collectTextureNames(blocks, items)) assert.ok(atlas.tiles.has(name), name);
  // tint-masked texels exist for grass top
  const img = atlas.tileImage('grass_top');
  assert.equal(img.alpha(3, 3), 254);
});
