/**
 * Gameplay mechanics exercised through a headless Game session.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game } from '../../../src/game/game.js';
import { CraftingSystem } from '../../../src/game/crafting.js';
import { FurnaceLogic } from '../../../src/game/smelting.js';
import { WorldStorage, MemoryBackend } from '../../../src/game/storage.js';
import { stack } from '../../../src/game/inventory.js';
import { FACE } from '../../../src/world/constants.js';
import { loadData, registries } from '../../helpers/fixtures.mjs';

const data = Object.fromEntries(['blocks', 'items', 'recipes', 'smelting', 'worldgen', 'game', 'player', 'mobs', 'ui', 'strings']
  .map((n) => [n, loadData(`${n}.json`)]));
const reg = registries();
const NO_ACTIONS = { took: () => false };
const IDLE = { forward: 0, strafe: 0, jump: false, sneak: false, sprint: false, breakHeld: false, useHeld: false, lookX: 0, lookY: 0, wheel: 0 };

async function newGame(mode = 'survival', difficulty = 'normal') {
  const game = new Game({
    data, registries: reg, crafting: new CraftingSystem(data.recipes, reg.items),
    furnaceLogic: new FurnaceLogic(data.smelting, reg.items), storage: new WorldStorage(new MemoryBackend()),
    settings: { renderDistance: 2, autoJump: true },
  });
  await game.open({ id: `m${Math.random()}`, name: 'm', seed: 2024, seedText: '2024', mode, difficulty, created: 0, lastPlayed: 0 });
  game.entities.updateSpawning = () => {};
  game.entities.list = [];
  for (let t = 0; t < 1; t += 1 / 30) game.frame(1 / 30, { ...IDLE }, NO_ACTIONS);
  return game;
}

/** Builds a flat 9x9 grass platform at the player's feet and clears the air above it. */
function platform(game) {
  const B = game.blocks, w = game.world, p = game.player;
  const x0 = Math.floor(p.x), y = Math.floor(p.y), z0 = Math.floor(p.z);
  for (let x = x0 - 4; x <= x0 + 4; x++) for (let z = z0 - 4; z <= z0 + 4; z++) {
    w.setBlock(x, y - 1, z, B.id('grass_block'));
    for (let k = 0; k < 6; k++) w.setBlock(x, y + k, z, 0);
  }
  p.teleport(x0 + 0.5, y, z0 + 0.5);
  return { x0, y, z0 };
}

function aimAt(game, x, y, z) {
  const e = game.player.eye();
  const dx = x - e.x, dy = y - e.y, dz = z - e.z;
  game.player.yaw = Math.atan2(-dx, -dz);
  game.player.pitch = Math.atan2(dy, Math.hypot(dx, dz));
  game._updateTarget();
}

test('attacking a pig with a sword kills it and drops pork', async () => {
  const game = await newGame();
  const { x0, y, z0 } = platform(game);
  const pig = game.entities.spawnMob('pig', x0 + 0.5, y, z0 - 1.5);
  pig.wanderTimer = 999;
  game.inventory.set(0, stack(game.items.id('diamond_sword'), 1));
  game.select(0);
  for (let i = 0; i < 6 && !pig.dead; i++) {
    aimAt(game, pig.x, pig.y + 0.5, pig.z);
    assert.equal(game.target?.type, 'mob');
    game.attack(pig);
    game.attackCooldown = 0;
    pig.invulnerable = 0;
  }
  assert.ok(pig.dead);
  assert.ok(game.entities.list.some((e) => e.type === 'item' && e.stack.id === game.items.id('raw_porkchop')));
  assert.ok(game.inventory.get(0).damage > 0, 'sword wears');
});

test('a zombie at night chases and hurts the player', async () => {
  const game = await newGame();
  const { x0, y, z0 } = platform(game);
  game.time = 18000;
  const z = game.entities.spawnMob('zombie', x0 + 0.5, y, z0 + 3.5);
  for (let t = 0; t < 4; t += 1 / 30) game.frame(1 / 30, { ...IDLE }, NO_ACTIONS);
  assert.ok(game.survival.health < 20, `health ${game.survival.health}`);
  void z;
});

test('a blastling explodes next to the player and leaves a crater', async () => {
  const game = await newGame();
  const { x0, y, z0 } = platform(game);
  game.time = 18000;
  game.entities.spawnMob('blastling', x0 + 0.5, y, z0 + 2.5);
  for (let t = 0; t < 4; t += 1 / 30) game.frame(1 / 30, { ...IDLE }, NO_ACTIONS);
  assert.ok(!game.entities.list.some((e) => e.kind === 'blastling'));
  assert.ok(game.survival.health < 20);
  let holes = 0;
  for (let x = x0 - 2; x <= x0 + 2; x++) for (let z = z0; z <= z0 + 4; z++) if (game.world.getBlock(x, y - 1, z) === 0) holes++;
  assert.ok(holes > 0, 'blocks were destroyed');
});

test('hoe, seeds and time grow wheat that can be harvested', async () => {
  const game = await newGame('survival', 'peaceful');
  const { x0, y, z0 } = platform(game);
  game.world.setBlock(x0 + 2, y - 1, z0, game.blocks.id('water'));
  game.inventory.set(0, stack(game.items.id('wooden_hoe'), 1));
  game.inventory.set(1, stack(game.items.id('wheat_seeds'), 3));
  game.select(0);
  aimAt(game, x0 + 0.5, y - 0.01, z0 - 1.5);
  assert.equal(game.target?.face, FACE.TOP);
  game.use();
  assert.equal(game.world.getBlock(x0, y - 1, z0 - 2), game.blocks.id('farmland'));
  game.select(1);
  aimAt(game, x0 + 0.5, y - 0.05, z0 - 1.5);
  game.use();
  const crop = game.blocks.id('wheat_crop');
  assert.equal(game.world.getBlock(x0, y, z0 - 2), crop);
  assert.equal(game.inventory.get(1).count, 2);
  // Grow it directly through random ticks on that cell.
  for (let i = 0; i < 200 && game.world.getMeta(x0, y, z0 - 2) < 7; i++) game._randomTick('crop', x0, y, z0 - 2, crop);
  assert.equal(game.world.getMeta(x0, y, z0 - 2), 7);
  game.breakBlock(x0, y, z0 - 2);
  assert.ok(game.entities.list.some((e) => e.type === 'item' && e.stack.id === game.items.id('wheat')));
});

test('buckets pick up and place water', async () => {
  const game = await newGame('survival', 'peaceful');
  const { x0, y, z0 } = platform(game);
  const water = game.blocks.id('water');
  game.world.setBlock(x0, y - 1, z0 - 2, water, 0);
  game.inventory.set(0, stack(game.items.id('bucket'), 1));
  game.select(0);
  aimAt(game, x0 + 0.5, y - 0.2, z0 - 1.5);
  game.use();
  assert.equal(game.inventory.get(0).id, game.items.id('water_bucket'));
  assert.equal(game.world.getBlock(x0, y - 1, z0 - 2), 0);
  aimAt(game, x0 + 2.5, y - 0.01, z0 + 0.5);
  game.use();
  assert.equal(game.inventory.get(0).id, game.items.id('bucket'));
  assert.equal(game.world.getBlock(x0 + 2, y, z0), water);
});

test('sleeping in a bed at night skips to morning and sets the spawn', async () => {
  const game = await newGame('survival', 'peaceful');
  const { x0, y, z0 } = platform(game);
  game.inventory.set(0, stack(game.items.id('bed'), 1));
  game.select(0);
  aimAt(game, x0 + 0.5, y - 0.01, z0 - 1.5);
  game.use();
  const foot = game.world.getBlock(x0, y, z0 - 2);
  assert.equal(game.blocks.defs[foot].name, 'bed_foot');
  const head = game.blocks.defs[game.world.getBlock(x0, y, z0 - 3)].name;
  assert.equal(head, 'bed_head');
  game.time = 24000 + 15000;
  aimAt(game, x0 + 0.5, y + 0.3, z0 - 1.5);
  game.use();
  for (let t = 0; t < 3; t += 1 / 30) game.frame(1 / 30, { ...IDLE }, NO_ACTIONS);
  assert.ok(game.timeOfDay < 0.1, `time of day ${game.timeOfDay}`);
  assert.equal(Math.floor(game.meta.spawn.z), z0 - 2);
  // Breaking one half removes the other.
  game.breakBlock(x0, y, z0 - 3);
  assert.equal(game.world.getBlock(x0, y, z0 - 2), 0);
});

test('torches need support and drop when the wall is removed', async () => {
  const game = await newGame('survival', 'peaceful');
  const { x0, y, z0 } = platform(game);
  const stone = game.blocks.id('stone');
  game.world.setBlock(x0, y, z0 - 3, stone);
  game.inventory.set(0, stack(game.items.id('torch'), 4));
  game.select(0);
  aimAt(game, x0 + 0.5, y + 0.5, z0 - 2.01);
  assert.equal(game.target.face, FACE.SOUTH);
  game.use();
  const torch = game.blocks.id('torch');
  assert.equal(game.world.getBlock(x0, y, z0 - 2), torch);
  assert.equal(game.world.getMeta(x0, y, z0 - 2), FACE.NORTH, 'attached to the north wall');
  game.world.setBlock(x0, y, z0 - 3, 0);
  game.tick();
  assert.equal(game.world.getBlock(x0, y, z0 - 2), 0);
  assert.ok(game.entities.list.some((e) => e.type === 'item' && e.stack.id === torch));
});
