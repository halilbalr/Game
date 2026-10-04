import { test } from 'node:test';
import assert from 'node:assert/strict';
import { flatWorld, registries, loadData } from '../../helpers/fixtures.mjs';
import { Player } from '../../../src/entities/player.js';
import { BlockColliders } from '../../../src/entities/physics.js';
import { raycastBlocks, makeBoundsLookup } from '../../../src/game/raycast.js';

const { blocks } = registries();
const cfg = loadData('player.json');
const still = { forward: 0, strafe: 0, jump: false, sneak: false, sprint: false };

function simulate(p, w, input, seconds) {
  const dt = 1 / 60;
  for (let t = 0; t < seconds; t += dt) p.update(dt, input, w, {});
}

function makePlayer(w) {
  const p = new Player(cfg, new BlockColliders(blocks), blocks);
  p.teleport(0.5, 70, 0.5);
  return p;
}

test('player falls and lands on the ground surface', () => {
  const w = flatWorld(1);
  const p = makePlayer(w);
  simulate(p, w, still, 3);
  assert.ok(Math.abs(p.y - 64) < 1e-6, `y=${p.y}`);
  assert.ok(p.onGround);
  assert.ok(p.landedFallDistance === 0, 'consumed on landing frame');
});

test('fall distance is reported on landing', () => {
  const w = flatWorld(1);
  const p = makePlayer(w);
  let landed = 0;
  const dt = 1 / 60;
  for (let t = 0; t < 3; t += dt) { p.update(dt, still, w, {}); landed = Math.max(landed, p.landedFallDistance); }
  assert.ok(Math.abs(landed - 6) < 0.05, `fell ${landed}`);
});

test('jump clears one block but not two', () => {
  const w = flatWorld(1);
  const p = makePlayer(w);
  simulate(p, w, still, 2);
  let peak = 0;
  const dt = 1 / 60;
  p.update(dt, { ...still, jump: true }, w, {});
  for (let t = 0; t < 1.5; t += dt) { p.update(dt, still, w, {}); peak = Math.max(peak, p.y - 64); }
  assert.ok(peak > 1.15 && peak < 1.35, `peak ${peak}`);
});

test('walking speed matches the configured value and walls stop movement', () => {
  const w = flatWorld(1);
  const p = makePlayer(w);
  simulate(p, w, still, 2);
  const z0 = p.z;
  simulate(p, w, { ...still, forward: 1 }, 2);
  const speed = (z0 - p.z) / 2;
  assert.ok(speed > cfg.walkSpeed * 0.9 && speed <= cfg.walkSpeed, `speed ${speed}`);
  // wall two blocks high in front (towards -z)
  const stone = blocks.id('stone');
  const wz = Math.floor(p.z) - 2;
  for (let x = -3; x <= 3; x++) { w.setBlock(x, 64, wz, stone); w.setBlock(x, 65, wz, stone); }
  simulate(p, w, { ...still, forward: 1 }, 2);
  assert.ok(Math.abs(p.z - (wz + 1 + cfg.halfWidth)) < 1e-6, `stopped at ${p.z}`);
});

test('auto-jump climbs a single block step', () => {
  const w = flatWorld(1);
  const p = makePlayer(w);
  simulate(p, w, still, 2);
  const stone = blocks.id('stone');
  for (let x = -3; x <= 3; x++) for (let z = -8; z <= -2; z++) w.setBlock(x, 64, z, stone);
  let top = 0;
  for (let t = 0; t < 1.5; t += 1 / 60) {
    p.update(1 / 60, { ...still, forward: 1 }, w, { autoJump: true });
    if (p.onGround) top = Math.max(top, p.y);
  }
  assert.ok(Math.abs(top - 65) < 1e-6, `stood at y=${top}`);
});

test('sneaking stops at a ledge', () => {
  const w = flatWorld(1);
  const stone = blocks.id('stone');
  for (let x = -2; x <= 2; x++) for (let z = -2; z <= 2; z++) w.setBlock(x, 70, z, stone);
  const p = new Player(cfg, new BlockColliders(blocks), blocks);
  p.teleport(0.5, 71, 0.5);
  simulate(p, w, still, 1);
  simulate(p, w, { ...still, forward: 1, sneak: true }, 4);
  assert.ok(p.y > 70.9, 'still on the platform');
  assert.ok(p.z > -2 - cfg.halfWidth - 0.05);
});

test('creative flight toggles with a double jump tap', () => {
  const w = flatWorld(1);
  const p = makePlayer(w);
  p.canFly = true;
  simulate(p, w, still, 2);
  const dt = 1 / 60;
  p.update(dt, { ...still, jump: true }, w, {});
  p.update(dt, still, w, {});
  p.update(dt, { ...still, jump: true }, w, {});
  assert.ok(p.flying);
  simulate(p, w, { ...still, jump: true }, 1);
  assert.ok(p.y > 69, `rose to ${p.y}`);
});

test('raycast finds the block face under the crosshair', () => {
  const w = flatWorld(1);
  const bounds = makeBoundsLookup(blocks);
  const hit = raycastBlocks(w, (id) => !blocks.liquid[id], { x: 0.5, y: 66, z: 0.5 }, { x: 0, y: -1, z: 0 }, 5, bounds);
  assert.deepEqual([hit.x, hit.y, hit.z, hit.face], [0, 63, 0, 0]);
  const side = raycastBlocks(w, () => true, { x: 3.5, y: 64.5, z: 0.5 }, { x: -1, y: 0, z: 0 }, 5, bounds);
  assert.equal(side, null, 'nothing within reach horizontally above ground');
  w.setBlock(1, 64, 0, blocks.id('stone'));
  const side2 = raycastBlocks(w, () => true, { x: 3.5, y: 64.5, z: 0.5 }, { x: -1, y: 0, z: 0 }, 5, bounds);
  assert.deepEqual([side2.x, side2.face], [1, 5]);
});
