/**
 * World persistence. Uses IndexedDB in the browser and falls back to an
 * in-memory store (private browsing, tests). Only chunks that differ from the
 * generator output are stored, RLE-compressed.
 */
import { rleEncode, rleDecode } from '../world/rle.js';
import { CHUNK_VOLUME } from '../world/constants.js';

const DB_NAME = 'blockheim';
const DB_VERSION = 1;

/** In-memory backend with the same async interface as the IndexedDB one. */
export class MemoryBackend {
  constructor() { this.stores = { worlds: new Map(), chunks: new Map() }; }
  async get(store, key) { return structuredCloneSafe(this.stores[store].get(key)); }
  async put(store, key, value) { this.stores[store].set(key, structuredCloneSafe(value)); }
  async delete(store, key) { this.stores[store].delete(key); }
  async keys(store, prefix) { return [...this.stores[store].keys()].filter((k) => !prefix || String(k).startsWith(prefix)); }
  async all(store) { return [...this.stores[store].values()].map(structuredCloneSafe); }
}

function structuredCloneSafe(v) {
  if (v === undefined) return undefined;
  return typeof structuredClone === 'function' ? structuredClone(v) : JSON.parse(JSON.stringify(v));
}

/** IndexedDB backend. */
export class IndexedDbBackend {
  constructor(db) { this.db = db; }

  static open() {
    return new Promise((resolve, reject) => {
      const req = indexedDB.open(DB_NAME, DB_VERSION);
      req.onupgradeneeded = () => {
        const db = req.result;
        if (!db.objectStoreNames.contains('worlds')) db.createObjectStore('worlds');
        if (!db.objectStoreNames.contains('chunks')) db.createObjectStore('chunks');
      };
      req.onsuccess = () => resolve(new IndexedDbBackend(req.result));
      req.onerror = () => reject(req.error);
      req.onblocked = () => reject(new Error('IndexedDB blocked'));
    });
  }

  _tx(store, mode, fn) {
    return new Promise((resolve, reject) => {
      const tx = this.db.transaction(store, mode);
      const os = tx.objectStore(store);
      let result;
      const req = fn(os);
      if (req) req.onsuccess = () => { result = req.result; };
      tx.oncomplete = () => resolve(result);
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error);
    });
  }

  get(store, key) { return this._tx(store, 'readonly', (os) => os.get(key)); }
  put(store, key, value) { return this._tx(store, 'readwrite', (os) => os.put(value, key)); }
  delete(store, key) { return this._tx(store, 'readwrite', (os) => os.delete(key)); }
  async keys(store, prefix) {
    const range = prefix ? IDBKeyRange.bound(prefix, `${prefix}￿`) : undefined;
    return this._tx(store, 'readonly', (os) => os.getAllKeys(range));
  }
  all(store) { return this._tx(store, 'readonly', (os) => os.getAll()); }
}

/** High-level world save API. */
export class WorldStorage {
  /** @param {MemoryBackend|IndexedDbBackend} backend */
  constructor(backend) {
    this.backend = backend;
  }

  /** Opens IndexedDB, or memory storage if unavailable. */
  static async create() {
    try {
      if (typeof indexedDB === 'undefined') throw new Error('no indexedDB');
      return new WorldStorage(await IndexedDbBackend.open());
    } catch (err) {
      console.warn('Falling back to in-memory saves:', err);
      const s = new WorldStorage(new MemoryBackend());
      s.volatile = true;
      return s;
    }
  }

  /** All world metadata, most recently played first. */
  async listWorlds() {
    const all = await this.backend.all('worlds');
    return all.sort((a, b) => (b.lastPlayed ?? 0) - (a.lastPlayed ?? 0));
  }

  loadWorld(id) { return this.backend.get('worlds', id); }

  saveWorld(meta) { return this.backend.put('worlds', meta.id, meta); }

  async deleteWorld(id) {
    const keys = await this.backend.keys('chunks', `${id}:`);
    for (const k of keys) await this.backend.delete('chunks', k);
    await this.backend.delete('worlds', id);
  }

  _key(worldId, cx, cz) { return `${worldId}:${cx},${cz}`; }

  /** Set of "cx,cz" strings for chunks stored for a world. */
  async savedChunkKeys(worldId) {
    const keys = await this.backend.keys('chunks', `${worldId}:`);
    return new Set(keys.map((k) => String(k).slice(String(worldId).length + 1)));
  }

  /**
   * Stores a chunk's blocks, metadata and block entities.
   * @param {string} worldId
   * @param {import('../world/chunk.js').Chunk} chunk
   */
  saveChunk(worldId, chunk) {
    const entities = [...chunk.blockEntities.entries()];
    return this.backend.put('chunks', this._key(worldId, chunk.cx, chunk.cz), {
      blocks: rleEncode(chunk.blocks), meta: rleEncode(chunk.meta), entities,
    });
  }

  /** @returns {Promise<{blocks:Uint8Array, meta:Uint8Array, entities:Array}|null>} */
  async loadChunk(worldId, cx, cz) {
    const rec = await this.backend.get('chunks', this._key(worldId, cx, cz));
    if (!rec) return null;
    return {
      blocks: rleDecode(new Uint8Array(rec.blocks), CHUNK_VOLUME),
      meta: rleDecode(new Uint8Array(rec.meta), CHUNK_VOLUME),
      entities: rec.entities ?? [],
    };
  }
}
