import { test } from 'node:test';
import assert from 'node:assert/strict';
import { TerrainGenerator } from '../../../src/world/terrain.js';
import { Chunk } from '../../../src/world/chunk.js';
import { loadData, registries } from '../../helpers/fixtures.mjs';

const cfg = loadData('worldgen.json');
const { blocks } = registries();

function gen(seed, cx, cz) {
  const g = new TerrainGenerator(seed, cfg, blocks);
  const c = new Chunk(cx, cz);
  g.generate(c);
  return { g, c };
}

test('generation is deterministic for a seed', () => {
  const a = gen(99, 3, -2).c, b = gen(99, 3, -2).c;
  assert.deepEqual(a.blocks, b.blocks);
  const c = gen(100, 3, -2).c;
  assert.notDeepEqual(a.blocks, c.blocks);
});

test('bottom layer is bedrock and nothing is above the height limit', () => {
  const { c } = gen(1, 0, 0);
  const bedrock = blocks.id('bedrock');
  for (let z = 0; z < 16; z++) for (let x = 0; x < 16; x++) {
    assert.equal(c.getBlock(x, 0, z), bedrock);
  }
  for (let z = 0; z < 16; z++) for (let x = 0; x < 16; x++) {
    assert.equal(c.getBlock(x, 127, z), 0);
  }
});

test('oceans are filled with water up to sea level', () => {
  const g = new TerrainGenerator(12345, cfg, blocks);
  // find an ocean column
  let found = null;
  for (let x = -2000; x < 2000 && !found; x += 37) {
    const s = g.sampleColumn(x, 500, {});
    if (s.height < cfg.seaLevel - 5) found = x;
  }
  assert.ok(found !== null, 'expected an ocean somewhere');
  const c = new Chunk(found >> 4, 500 >> 4);
  g.generate(c);
  const lx = found & 15, lz = 500 & 15;
  const water = blocks.id('water'), ice = blocks.id('ice');
  const top = c.getBlock(lx, cfg.seaLevel, lz);
  assert.ok(top === water || top === ice);
  assert.equal(c.getBlock(lx, cfg.seaLevel + 1, lz), 0);
});

test('trees crossing chunk borders are identical from both sides', () => {
  // Generate a 3x3 area twice in different orders and compare.
  const g1 = new TerrainGenerator(777, cfg, blocks);
  const g2 = new TerrainGenerator(777, cfg, blocks);
  const order1 = [], order2 = [];
  for (let cx = -1; cx <= 1; cx++) for (let cz = -1; cz <= 1; cz++) order1.push([cx, cz]);
  for (const p of [...order1].reverse()) order2.push(p);
  const out1 = new Map(), out2 = new Map();
  for (const [cx, cz] of order1) { const c = new Chunk(cx, cz); g1.generate(c); out1.set(`${cx},${cz}`, c.blocks); }
  for (const [cx, cz] of order2) { const c = new Chunk(cx, cz); g2.generate(c); out2.set(`${cx},${cz}`, c.blocks); }
  for (const k of out1.keys()) assert.deepEqual(out1.get(k), out2.get(k));
});

test('a forest has trees with logs and leaves', () => {
  const g = new TerrainGenerator(12345, cfg, blocks);
  let forestChunk = null;
  outer: for (let x = -3000; x < 3000; x += 48) {
    for (let z = -3000; z < 3000; z += 48) {
      if (g.biomeAt(x, z).name === 'forest') { forestChunk = [x >> 4, z >> 4]; break outer; }
    }
  }
  assert.ok(forestChunk);
  const c = new Chunk(...forestChunk);
  g.generate(c);
  const log = blocks.id('oak_log'), leaves = blocks.id('oak_leaves');
  const birchLog = blocks.id('birch_log');
  let logs = 0, leaf = 0;
  for (const b of c.blocks) { if (b === log || b === birchLog) logs++; if (b === leaves) leaf++; }
  assert.ok(logs > 0 && leaf > 0, `logs=${logs} leaves=${leaf}`);
});

test('ores appear underground only within their height range', () => {
  const diamond = blocks.id('diamond_ore');
  let count = 0;
  for (let cx = 0; cx < 6; cx++) {
    const { c } = gen(4242, cx, 0);
    for (let i = 0; i < c.blocks.length; i++) {
      if (c.blocks[i] === diamond) {
        count++;
        const y = i >> 8;
        assert.ok(y <= 16 + 6, `diamond at y=${y}`);
      }
    }
  }
  assert.ok(count > 0);
});

test('cave test for a single voxel matches bulk generation', () => {
  const { g, c } = gen(31337, 2, 5);
  const stone = blocks.id('stone');
  let checked = 0, mismatches = 0;
  for (let y = 10; y < 50; y += 3) {
    for (let z = 0; z < 16; z += 3) for (let x = 0; x < 16; x += 3) {
      const wx = 32 + x, wz = 80 + z;
      const h = g.sampleColumn(wx, wz, {}).height;
      if (y > h - 6) continue;
      const id = c.getBlock(x, y, z);
      const carved = g.caveAt(wx, y, wz);
      checked++;
      if (carved && id !== 0 && id !== blocks.id('lava')) mismatches++;
      if (!carved && id === 0) mismatches++;
    }
  }
  assert.ok(checked > 50);
  assert.equal(mismatches, 0);
  void stone;
});

test('spawn column is dry land', () => {
  const g = new TerrainGenerator(2024, cfg, blocks);
  const s = g.findSpawnColumn();
  assert.ok(s.height > cfg.seaLevel);
});
