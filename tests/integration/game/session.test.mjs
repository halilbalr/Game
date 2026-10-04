/**
 * Runs a real Game session headlessly (no renderer/UI) against in-memory storage.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game } from '../../../src/game/game.js';
import { CraftingSystem } from '../../../src/game/crafting.js';
import { FurnaceLogic } from '../../../src/game/smelting.js';
import { WorldStorage, MemoryBackend } from '../../../src/game/storage.js';
import { stack } from '../../../src/game/inventory.js';
import { loadData, registries } from '../../helpers/fixtures.mjs';

const data = Object.fromEntries(['blocks', 'items', 'recipes', 'smelting', 'worldgen', 'game', 'player', 'mobs', 'ui', 'strings']
  .map((n) => [n, loadData(`${n}.json`)]));
const reg = registries();
const NO_ACTIONS = { took: () => false };
const IDLE = { forward: 0, strafe: 0, jump: false, sneak: false, sprint: false, breakHeld: false, useHeld: false, lookX: 0, lookY: 0, wheel: 0 };

async function newGame(storage, meta) {
  const game = new Game({
    data, registries: reg, crafting: new CraftingSystem(data.recipes, reg.items),
    furnaceLogic: new FurnaceLogic(data.smelting, reg.items), storage,
    settings: { renderDistance: 2, autoJump: true },
  });
  await game.open(meta);
  return game;
}

function meta(id, mode = 'survival') {
  return { id, name: id, seed: 2024, seedText: '2024', mode, difficulty: 'peaceful', created: 0, lastPlayed: 0 };
}

function run(game, seconds, input = IDLE) {
  for (let t = 0; t < seconds; t += 1 / 30) game.frame(1 / 30, { ...input }, NO_ACTIONS);
}

test('a new world spawns the player standing on dry land', async () => {
  const game = await newGame(new WorldStorage(new MemoryBackend()), meta('spawn'));
  run(game, 2);
  const p = game.player;
  assert.ok(p.onGround, 'standing');
  const below = game.world.getBlock(Math.floor(p.x), Math.floor(p.y - 0.01), Math.floor(p.z));
  assert.ok(game.blocks.solid[below]);
  assert.equal(game.survival.health, 20);
});

test('breaking the block under the crosshair drops an item that gets picked up', async () => {
  const game = await newGame(new WorldStorage(new MemoryBackend()), meta('mine'));
  run(game, 1);
  const p = game.player;
  p.pitch = -Math.PI / 2 + 0.05;
  run(game, 0.1);
  const t = game.target;
  assert.equal(t.type, 'block');
  const id = t.id;
  run(game, 6, { ...IDLE, breakHeld: true });
  assert.notEqual(game.world.getBlock(t.x, t.y, t.z), id, 'block was broken');
  run(game, 2);
  const expected = game.blocks.defs[id].drops?.[0]?.item ?? game.blocks.defs[id].name;
  assert.ok(game.inventory.count(game.items.id(expected)) >= 1, `picked up ${expected}`);
});

test('placing a block from the hotbar consumes it in survival', async () => {
  const game = await newGame(new WorldStorage(new MemoryBackend()), meta('place'));
  run(game, 1);
  const planks = game.items.id('oak_planks');
  game.inventory.set(0, stack(planks, 5));
  game.select(0);
  game.player.pitch = -0.7;
  run(game, 0.1);
  const t = game.target;
  assert.equal(t?.type, 'block');
  game.use();
  assert.equal(game.inventory.get(0).count, 4);
  const n = [[0, 1, 0], [0, -1, 0], [0, 0, -1], [0, 0, 1], [-1, 0, 0], [1, 0, 0]][t.face];
  const placedAt = game.blocks.replaceable[t.id] ? [t.x, t.y, t.z] : [t.x + n[0], t.y + n[1], t.z + n[2]];
  assert.equal(game.world.getBlock(...placedAt), planks);
});

test('a furnace smelts over game ticks and lights up', async () => {
  const game = await newGame(new WorldStorage(new MemoryBackend()), meta('furnace'));
  const p = game.player;
  const x = Math.floor(p.x) + 2, y = Math.floor(p.y), z = Math.floor(p.z);
  game.world.setBlock(x, y, z, game.blocks.id('furnace'), 2);
  game.world.setBlockEntity(x, y, z, { type: 'furnace', ...game.furnaceLogic.createState(), input: stack(game.items.id('sand'), 2), fuel: stack(game.items.id('coal'), 1) });
  for (let i = 0; i < 10; i++) game.tick();
  assert.equal(game.world.getBlock(x, y, z), game.blocks.id('lit_furnace'));
  for (let i = 0; i < 400; i++) game.tick();
  const be = game.world.getBlockEntity(x, y, z);
  assert.equal(be.output.id, game.items.id('glass'));
  assert.equal(be.output.count, 2);
});

test('explosions remove blocks around the centre but never bedrock', async () => {
  const game = await newGame(new WorldStorage(new MemoryBackend()), meta('boom', 'creative'));
  const p = game.player;
  const cx = Math.floor(p.x) + 6, cz = Math.floor(p.z);
  const cy = game.world.topSolidY(cx, cz);
  game.explode(cx + 0.5, cy + 0.5, cz + 0.5, 3, 18);
  assert.equal(game.world.getBlock(cx, cy, cz), 0);
  game.explode(cx + 0.5, 1, cz + 0.5, 3, 18);
  assert.equal(game.world.getBlock(cx, 0, cz), game.blocks.id('bedrock'));
});

test('dying scatters the inventory and respawning restores health', async () => {
  const game = await newGame(new WorldStorage(new MemoryBackend()), meta('death'));
  game.inventory.set(3, stack(game.items.id('diamond'), 4));
  game.survival.damage(100, 'lava');
  game.tick();
  assert.ok(game.survival.dead);
  assert.equal(game.inventory.count(game.items.id('diamond')), 0);
  assert.ok(game.entities.list.some((e) => e.type === 'item' && e.stack.id === game.items.id('diamond')));
  game.respawn();
  assert.equal(game.survival.health, 20);
  assert.ok(!game.survival.dead);
});

test('saved worlds restore blocks, inventory and position', async () => {
  const storage = new WorldStorage(new MemoryBackend());
  const m = meta('persist');
  const a = await newGame(storage, m);
  run(a, 1);
  const p = a.player;
  const spot = [Math.floor(p.x) + 1, Math.floor(p.y) + 3, Math.floor(p.z)];
  a.world.setBlock(...spot, a.blocks.id('gold_block'));
  a.inventory.set(7, stack(a.items.id('apple'), 3));
  await a.close();
  const saved = await storage.loadWorld('persist');
  const b = await newGame(storage, saved);
  assert.equal(b.world.getBlock(...spot), b.blocks.id('gold_block'));
  assert.equal(b.inventory.get(7).count, 3);
  assert.ok(Math.abs(b.player.x - p.x) < 1e-9 && Math.abs(b.player.z - p.z) < 1e-9);
});

test('sand falls when the block under it is removed', async () => {
  const game = await newGame(new WorldStorage(new MemoryBackend()), meta('sand', 'creative'));
  const p = game.player;
  const x = Math.floor(p.x) + 3, z = Math.floor(p.z);
  const top = game.world.topSolidY(x, z);
  game.world.setBlock(x, top + 1, z, game.blocks.id('stone'));
  game.world.setBlock(x, top + 2, z, game.blocks.id('sand'));
  game.world.setBlock(x, top + 1, z, 0);
  run(game, 3);
  assert.equal(game.world.getBlock(x, top + 1, z), game.blocks.id('sand'));
  assert.equal(game.world.getBlock(x, top + 2, z), 0);
});
