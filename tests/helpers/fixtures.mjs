/**
 * Shared test fixtures: loads the real data files and builds small worlds.
 * Data is read from disk once here so individual tests stay free of file I/O.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRegistries } from '../../src/world/registry.js';
import { World } from '../../src/world/world.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const dataDir = path.join(here, '..', '..', 'src', 'data');

/** Reads a JSON data file from src/data. */
export function loadData(name) {
  return JSON.parse(fs.readFileSync(path.join(dataDir, name), 'utf8'));
}

let cached;
/** Real block and item registries. */
export function registries() {
  if (!cached) cached = createRegistries(loadData('blocks.json'), loadData('items.json'));
  return cached;
}

/** Generator producing a flat world: bedrock at 0, stone to 59, dirt 60-62, grass at 63. */
export class FlatGenerator {
  constructor(blocks, groundY = 63) {
    this.blocks = blocks;
    this.groundY = groundY;
  }
  generate(chunk) {
    const B = this.blocks;
    const ids = { bedrock: B.id('bedrock'), stone: B.id('stone'), dirt: B.id('dirt'), grass: B.id('grass_block') };
    for (let z = 0; z < 16; z++) {
      for (let x = 0; x < 16; x++) {
        for (let y = 0; y <= this.groundY; y++) {
          let id = ids.stone;
          if (y === 0) id = ids.bedrock;
          else if (y === this.groundY) id = ids.grass;
          else if (y > this.groundY - 4) id = ids.dirt;
          chunk.blocks[(y << 8) | (z << 4) | x] = id;
        }
      }
    }
    chunk.grassTint.fill(120);
    chunk.foliageTint.fill(100);
    chunk.recountSections();
    chunk.generated = true;
  }
}

/** A flat world with chunks generated in a square of the given radius around the origin. */
export function flatWorld(radius = 1, groundY = 63) {
  const { blocks } = registries();
  const world = new World({ blocks, generator: new FlatGenerator(blocks, groundY) });
  for (let cx = -radius; cx <= radius; cx++) {
    for (let cz = -radius; cz <= radius; cz++) world.generateChunk(cx, cz);
  }
  return world;
}
