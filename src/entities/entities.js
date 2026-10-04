/**
 * Non-player entities: dropped items, falling sand/gravel, and mobs with simple
 * wander / panic / chase AI. Rendering is handled separately by
 * render/entityRenderer.js, which mirrors this list.
 */
import { AABB, moveBox } from './physics.js';
import { LIQUID, WORLD_HEIGHT } from '../world/constants.js';
import { stack } from '../game/inventory.js';

let nextId = 1;

class Entity {
  constructor(type, x, y, z) {
    this.id = nextId++;
    this.type = type;
    this.x = x; this.y = y; this.z = z;
    this.vx = 0; this.vy = 0; this.vz = 0;
    this.yaw = 0;
    this.onGround = false;
    this.removed = false;
    this.age = 0;
    this.halfWidth = 0.125;
    this.height = 0.25;
  }
  box() { return AABB.fromFeet(this.x, this.y, this.z, this.halfWidth, this.height); }
}

export class ItemEntity extends Entity {
  constructor(x, y, z, s, pickupDelay) {
    super('item', x, y, z);
    this.stack = s;
    this.pickupDelay = pickupDelay;
    this.spin = Math.random() * Math.PI * 2;
  }
}

export class FallingBlock extends Entity {
  constructor(x, y, z, blockId, meta) {
    super('falling', x, y, z);
    this.blockId = blockId;
    this.meta = meta;
    this.halfWidth = 0.49;
    this.height = 0.98;
  }
}

export class Mob extends Entity {
  constructor(kind, def, x, y, z) {
    super('mob', x, y, z);
    this.kind = kind;
    this.def = def;
    this.health = def.health;
    this.halfWidth = def.halfWidth;
    this.height = def.height;
    this.headYaw = 0;
    this.hurtTime = 0;
    this.invulnerable = 0;
    this.deathTime = 0;
    this.dead = false;
    this.walkPhase = 0;
    this.walkAmount = 0;
    this.targetX = null; this.targetZ = null;
    this.wanderTimer = 0;
    this.panicTimer = 0;
    this.attackTimer = 0;
    this.fuse = 0;
    this.burning = false;
    this.horizontalCollision = false;
    this.persistent = !def.hostile;
  }
}

export class EntityManager {
  /**
   * @param {object} deps
   * @param {import('../world/world.js').World} deps.world
   * @param {import('../world/registry.js').BlockRegistry} deps.blocks
   * @param {import('../world/registry.js').ItemRegistry} deps.items
   * @param {import('./physics.js').BlockColliders} deps.colliders
   * @param {object} deps.mobData parsed mobs.json
   * @param {object} deps.config parsed game.json
   * @param {() => number} deps.rand
   * @param {object} deps.hooks callbacks: pickup(stack) -> leftover count, damagePlayer(amount, source, fromX, fromZ), sound(name, x, y, z), explode(x, y, z, power, damage), dropped(mob)
   */
  constructor({ world, blocks, items, colliders, mobData, config, rand, hooks }) {
    this.world = world;
    this.blocks = blocks;
    this.items = items;
    this.colliders = colliders;
    this.mobData = mobData;
    this.cfg = config;
    this.rand = rand;
    this.hooks = hooks;
    /** @type {Entity[]} */
    this.list = [];
    this.difficulty = 'normal';
    this._hostileTimer = 0;
  }

  /** Drops an item stack into the world with a small random toss. */
  dropItem(x, y, z, s, opts = {}) {
    if (!s || s.count <= 0) return null;
    const items = this.list.filter((e) => e.type === 'item');
    if (items.length >= this.cfg.interaction.maxItemEntities) {
      const oldest = items[0];
      oldest.removed = true;
    }
    const e = new ItemEntity(x, y, z, stack(s.id, s.count, s.damage ?? 0), opts.pickupDelay ?? this.cfg.interaction.itemPickupDelay);
    const r = this.rand;
    if (opts.vx !== undefined) { e.vx = opts.vx; e.vy = opts.vy; e.vz = opts.vz; }
    else { e.vx = (r() - 0.5) * 2; e.vy = 3 + r() * 1.5; e.vz = (r() - 0.5) * 2; }
    this.list.push(e);
    return e;
  }

  /** Turns a gravity block into a falling entity. */
  spawnFallingBlock(x, y, z, id, meta) {
    const e = new FallingBlock(x + 0.5, y, z + 0.5, id, meta);
    this.list.push(e);
    return e;
  }

  /** Spawns a mob of the given kind. */
  spawnMob(kind, x, y, z) {
    const def = this.mobData.mobs[kind];
    if (!def) throw new Error(`unknown mob ${kind}`);
    const m = new Mob(kind, def, x, y, z);
    m.yaw = this.rand() * Math.PI * 2;
    this.list.push(m);
    return m;
  }

  mobs() { return this.list.filter((e) => e.type === 'mob'); }

  /**
   * Finds the nearest living mob hit by a ray.
   * @returns {{mob: Mob, dist: number}|null}
   */
  raycastMob(o, d, maxDist) {
    let best = null;
    for (const e of this.list) {
      if (e.type !== 'mob' || e.dead) continue;
      const b = e.box();
      const t = rayAabb(o, d, b);
      if (t !== null && t <= maxDist && (!best || t < best.dist)) best = { mob: e, dist: t };
    }
    return best;
  }

  /**
   * Damages a mob, applying knockback away from (fromX, fromZ).
   * @returns {boolean} whether the hit landed
   */
  hurtMob(m, amount, fromX, fromZ) {
    if (m.dead || m.invulnerable > 0) return false;
    m.health -= amount;
    m.hurtTime = 0.35;
    m.invulnerable = this.mobData.ai.hurtInvulnerableSeconds;
    const dx = m.x - fromX, dz = m.z - fromZ;
    const len = Math.hypot(dx, dz) || 1;
    const p = this.mobData.physics;
    m.vx = (dx / len) * p.knockback;
    m.vz = (dz / len) * p.knockback;
    m.vy = p.knockbackUp;
    if (!m.def.hostile) { m.panicTimer = this.mobData.ai.panicSeconds; m.targetX = null; }
    this.hooks.sound?.(`${m.def.sound}_hurt`, m.x, m.y, m.z);
    if (m.health <= 0) {
      m.dead = true;
      m.deathTime = 0;
      for (const d of m.def.drops) {
        const [lo, hi] = d.count;
        const n = lo + Math.floor(this.rand() * (hi - lo + 1));
        if (n > 0) this.dropItem(m.x, m.y + 0.5, m.z, stack(this.items.id(d.item), n));
      }
      this.hooks.dropped?.(m);
    }
    return true;
  }

  /**
   * Advances every entity.
   * @param {number} dt seconds
   * @param {import('./player.js').Player} player
   * @param {{daylight:number, gameMode:string}} env
   */
  update(dt, player, env) {
    for (const e of this.list) {
      if (e.removed) continue;
      if (!this.world.isLoaded(e.x, e.z)) continue;
      e.age += dt;
      if (e.type === 'item') this._updateItem(e, dt, player, env);
      else if (e.type === 'falling') this._updateFalling(e, dt);
      else if (e.type === 'mob') this._updateMob(e, dt, player, env);
    }
    if (this.list.some((e) => e.removed)) this.list = this.list.filter((e) => !e.removed);
  }

  _physics(e, dt, gravity, drag, stepHeight = 0) {
    const inWater = this.blocks.liquid[this.world.getBlock(Math.floor(e.x), Math.floor(e.y + 0.1), Math.floor(e.z))] !== LIQUID.none;
    if (inWater) {
      e.vy += (-gravity * 0.15 - e.vy * 3) * dt;
      e.vx *= Math.exp(-3 * dt); e.vz *= Math.exp(-3 * dt);
    } else {
      e.vy -= gravity * dt;
      e.vy *= Math.exp(-drag * dt);
    }
    const box = e.box();
    const r = moveBox(this.colliders, this.world, box, e.vx * dt, e.vy * dt, e.vz * dt, e.onGround ? stepHeight : 0, e.onGround);
    e.x = (box.minX + box.maxX) / 2; e.y = box.minY; e.z = (box.minZ + box.maxZ) / 2;
    if (r.hitX) e.vx = 0;
    if (r.hitZ) e.vz = 0;
    if (r.hitY) e.vy = 0;
    e.onGround = r.onGround;
    e.horizontalCollision = r.hitX || r.hitZ;
    e.inWater = inWater;
    if (e.y < -10) e.removed = true;
    return r;
  }

  _updateItem(e, dt, player, env) {
    e.spin += dt * 1.6;
    if (e.pickupDelay > 0) e.pickupDelay -= dt;
    this._physics(e, dt, 16, 0.6);
    if (e.onGround) {
      const f = Math.exp(-8 * dt);
      e.vx *= f; e.vz *= f;
    }
    if (e.age > this.cfg.interaction.itemDespawnSeconds) e.removed = true;
    // Merge with nearby identical stacks.
    if (Math.floor(e.age * 4) !== Math.floor((e.age - dt) * 4)) {
      for (const o of this.list) {
        if (o === e || o.type !== 'item' || o.removed || o.stack.id !== e.stack.id || (o.stack.damage ?? 0) !== (e.stack.damage ?? 0)) continue;
        if (Math.abs(o.x - e.x) < 0.6 && Math.abs(o.y - e.y) < 0.6 && Math.abs(o.z - e.z) < 0.6) {
          const max = this.items.maxStack(e.stack.id);
          if (e.stack.count + o.stack.count <= max) { e.stack.count += o.stack.count; o.removed = true; }
        }
      }
    }
    if (e.pickupDelay <= 0 && !env.playerDead) {
      const dx = player.x - e.x, dy = (player.y + 0.8) - e.y, dz = player.z - e.z;
      const r = this.cfg.interaction.itemPickupRadius;
      if (dx * dx + dy * dy + dz * dz < r * r) {
        const left = this.hooks.pickup(e.stack);
        if (left <= 0) e.removed = true;
        else e.stack.count = left;
      }
    }
  }

  _updateFalling(e, dt) {
    this._physics(e, dt, 32, 0.4);
    if (e.onGround || e.age > 30) {
      e.removed = true;
      const x = Math.floor(e.x), y = Math.floor(e.y + 0.5), z = Math.floor(e.z);
      const cur = this.world.getBlock(x, y, z);
      if (y >= 0 && y < WORLD_HEIGHT && (cur === 0 || this.blocks.replaceable[cur])) this.world.setBlock(x, y, z, e.blockId, e.meta);
      else this.dropItem(e.x, e.y + 0.5, e.z, stack(e.blockId, 1));
    }
  }

  _updateMob(m, dt, player, env) {
    const ai = this.mobData.ai, ph = this.mobData.physics;
    if (m.hurtTime > 0) m.hurtTime -= dt;
    if (m.invulnerable > 0) m.invulnerable -= dt;
    if (m.dead) {
      m.deathTime += dt;
      m.vx *= 0.8; m.vz *= 0.8;
      this._physics(m, dt, ph.gravity, ph.airDrag);
      if (m.deathTime > ai.deathSeconds) m.removed = true;
      return;
    }
    const def = m.def;
    let wishX = 0, wishZ = 0, speed = def.walkSpeed;
    const dxp = player.x - m.x, dzp = player.z - m.z, dyp = player.y - m.y;
    const distP = Math.hypot(dxp, dzp);
    const canTarget = def.hostile && env.gameMode === 'survival' && !env.playerDead && distP < def.followRange && Math.abs(dyp) < 12;

    if (canTarget) {
      speed = def.chaseSpeed;
      wishX = dxp / (distP || 1); wishZ = dzp / (distP || 1);
      m.headYaw = Math.atan2(-dxp, -dzp);
      if (def.attackDamage) {
        m.attackTimer -= dt;
        if (distP < def.attackRange && Math.abs(dyp) < 1.6 && m.attackTimer <= 0) {
          m.attackTimer = def.attackCooldown;
          this.hooks.damagePlayer(def.attackDamage[this.difficulty] ?? 3, m.kind, m.x, m.z);
        }
      }
      if (def.fuseSeconds) {
        if (distP < def.fuseRange || (m.fuse > 0 && distP < def.cancelRange)) {
          if (m.fuse === 0) this.hooks.sound?.('fuse', m.x, m.y, m.z);
          m.fuse += dt;
          wishX *= 0.2; wishZ *= 0.2;
          if (m.fuse >= def.fuseSeconds) {
            m.removed = true;
            m.dead = true;
            this.hooks.explode(m.x, m.y + 0.5, m.z, def.explosionPower, def.explosionDamage[this.difficulty] ?? 18);
            return;
          }
        } else if (m.fuse > 0) {
          m.fuse = Math.max(0, m.fuse - dt * 2);
        }
      }
    } else if (m.panicTimer > 0) {
      m.panicTimer -= dt;
      speed = def.panicSpeed ?? def.walkSpeed * 2;
      if (m.targetX === null || this.rand() < dt * 1.5) this._pickWanderTarget(m, ai.wanderRadius);
    } else {
      m.wanderTimer -= dt;
      if (m.wanderTimer <= 0) {
        m.wanderTimer = ai.wanderMinSeconds + this.rand() * (ai.wanderMaxSeconds - ai.wanderMinSeconds);
        if (this.rand() < ai.idleChance) m.targetX = null;
        else this._pickWanderTarget(m, ai.wanderRadius);
      }
      if (m.fuse > 0) m.fuse = Math.max(0, m.fuse - dt * 2);
    }
    if (!canTarget && m.targetX !== null) {
      const dx = m.targetX - m.x, dz = m.targetZ - m.z;
      const d = Math.hypot(dx, dz);
      if (d < 0.5) m.targetX = null;
      else { wishX = dx / d; wishZ = dz / d; }
    }
    // Avoid walking off cliffs or into deep water/lava while wandering.
    if ((wishX || wishZ) && !canTarget && !this._safeAhead(m, wishX, wishZ)) {
      wishX = 0; wishZ = 0; m.targetX = null;
    }
    if (wishX || wishZ) m.yaw = lerpAngle(m.yaw, Math.atan2(-wishX, -wishZ), Math.min(1, dt * 8));
    if (!canTarget) m.headYaw = lerpAngle(m.headYaw, m.yaw, Math.min(1, dt * 4));

    const accel = m.onGround ? 10 : 2;
    m.vx += (wishX * speed - m.vx) * Math.min(1, accel * dt);
    m.vz += (wishZ * speed - m.vz) * Math.min(1, accel * dt);
    if ((wishX || wishZ) && m.horizontalCollision && m.onGround) m.vy = ph.jumpVelocity;
    if (m.inWater && (wishX || wishZ || canTarget)) m.vy = Math.max(m.vy, 1.5);
    this._physics(m, dt, def.slowFall && m.vy < 0 ? ph.gravity * 0.25 : ph.gravity, ph.airDrag, ph.stepHeight);

    const moving = Math.hypot(m.vx, m.vz);
    m.walkAmount += (Math.min(1, moving / 2) - m.walkAmount) * Math.min(1, dt * 8);
    m.walkPhase += moving * dt * 3.2;

    // Undead burn in sunlight.
    m.burning = false;
    if (def.burnsInDaylight && env.daylight > ai.daylightBurnLevel && !m.inWater) {
      const sky = this.world.getSkyLight(Math.floor(m.x), Math.floor(m.y + m.height), Math.floor(m.z));
      if (sky >= 15) {
        m.burning = true;
        m.burnAcc = (m.burnAcc ?? 0) + dt * ai.burnDamagePerSecond;
        if (m.burnAcc >= 1) { m.burnAcc -= 1; m.health -= 1; m.hurtTime = 0.2; if (m.health <= 0) { m.dead = true; m.deathTime = 0; } }
      }
    }
    const lava = this.blocks.liquid[this.world.getBlock(Math.floor(m.x), Math.floor(m.y + 0.2), Math.floor(m.z))] === LIQUID.lava;
    if (lava) this.hurtMob(m, 4, m.x, m.z);

    if (this.rand() < dt * 0.08) this.hooks.sound?.(`${def.sound}_say`, m.x, m.y, m.z);
  }

  _pickWanderTarget(m, radius) {
    const a = this.rand() * Math.PI * 2, r = 2 + this.rand() * radius;
    m.targetX = m.x + Math.cos(a) * r;
    m.targetZ = m.z + Math.sin(a) * r;
  }

  _safeAhead(m, wx, wz) {
    const x = Math.floor(m.x + wx * (m.halfWidth + 0.6)), z = Math.floor(m.z + wz * (m.halfWidth + 0.6));
    const y = Math.floor(m.y + 0.01);
    for (let d = 0; d <= this.mobData.ai.maxSafeDrop; d++) {
      const id = this.world.getBlock(x, y - d, z);
      if (this.blocks.liquid[id]) return d === 0 && this.blocks.liquid[id] === LIQUID.water;
      if (this.blocks.solid[id]) return true;
    }
    return false;
  }

  /**
   * Tries to spawn hostile mobs in dark places around the player and despawns far ones.
   * @param {number} dt
   * @param {import('./player.js').Player} player
   * @param {{daylight:number, difficulty:string, gameMode:string}} env
   */
  updateSpawning(dt, player, env) {
    const sp = this.cfg.spawning;
    for (const e of this.list) {
      if (e.type !== 'mob' || e.persistent) continue;
      const d = Math.hypot(e.x - player.x, e.z - player.z);
      if (d > sp.despawnDistance) e.removed = true;
    }
    if (env.difficulty === 'peaceful') {
      for (const e of this.list) if (e.type === 'mob' && e.def.hostile) e.removed = true;
      return;
    }
    this._hostileTimer += dt;
    const interval = 1 / sp.hostileAttemptsPerSecond;
    while (this._hostileTimer >= interval) {
      this._hostileTimer -= interval;
      const hostiles = this.list.filter((e) => e.type === 'mob' && e.def.hostile && !e.removed).length;
      if (hostiles >= sp.maxHostile) break;
      const a = this.rand() * Math.PI * 2;
      const r = sp.hostileMinDistance + this.rand() * (sp.hostileMaxDistance - sp.hostileMinDistance);
      const x = Math.floor(player.x + Math.cos(a) * r), z = Math.floor(player.z + Math.sin(a) * r);
      if (!this.world.isLoaded(x, z)) continue;
      const spot = this._findSpawnY(x, z, player.y, env.daylight, sp.hostileMaxLight);
      if (spot === null) continue;
      const kind = this.rand() < 0.72 ? 'zombie' : 'blastling';
      this.spawnMob(kind, x + 0.5, spot, z + 0.5);
    }
  }

  _findSpawnY(x, z, nearY, daylight, maxLight) {
    const B = this.blocks;
    const tries = [];
    for (let y = Math.min(WORLD_HEIGHT - 3, Math.floor(nearY) + 16); y > Math.max(1, nearY - 24); y--) tries.push(y);
    for (const y of tries) {
      const below = this.world.getBlock(x, y - 1, z);
      if (!B.opaque[below] || !B.solid[below]) continue;
      if (B.solid[this.world.getBlock(x, y, z)] || B.solid[this.world.getBlock(x, y + 1, z)]) continue;
      if (B.liquid[this.world.getBlock(x, y, z)]) continue;
      const sky = this.world.getSkyLight(x, y, z) * daylight;
      const blk = this.world.getBlockLight(x, y, z);
      if (Math.max(sky, blk) <= maxLight) return y;
    }
    return null;
  }

  /**
   * Populates a freshly generated chunk with a few animals.
   * @param {import('../world/chunk.js').Chunk} chunk
   * @param {(biomeId:number) => string[]} animalsFor
   */
  populateChunk(chunk, animalsFor) {
    const sp = this.cfg.spawning;
    if (this.rand() >= sp.passivePerChunkChance) return;
    const passive = this.list.filter((e) => e.type === 'mob' && !e.def.hostile).length;
    if (passive >= sp.maxPassive) return;
    const lx = Math.floor(this.rand() * 16), lz = Math.floor(this.rand() * 16);
    const kinds = animalsFor(chunk.biome[(lz << 4) | lx]);
    if (!kinds.length) return;
    const kind = kinds[Math.floor(this.rand() * kinds.length)];
    const [lo, hi] = sp.passiveGroup;
    const n = lo + Math.floor(this.rand() * (hi - lo + 1));
    const grass = this.blocks.id('grass_block');
    for (let i = 0; i < n; i++) {
      const x = Math.min(15, Math.max(0, lx + Math.floor(this.rand() * 5) - 2));
      const z = Math.min(15, Math.max(0, lz + Math.floor(this.rand() * 5) - 2));
      const y = chunk.topBlockY(x, z);
      if (y < 0 || chunk.getBlock(x, y, z) !== grass) continue;
      this.spawnMob(kind, chunk.cx * 16 + x + 0.5, y + 1, chunk.cz * 16 + z + 0.5);
    }
  }

  /** Persistent entities (animals and items) for saving. */
  toJSON() {
    const out = [];
    for (const e of this.list) {
      if (e.removed) continue;
      if (e.type === 'mob' && e.persistent && !e.dead) out.push({ t: 'mob', k: e.kind, x: e.x, y: e.y, z: e.z, h: e.health, yaw: e.yaw });
      else if (e.type === 'item') out.push({ t: 'item', x: e.x, y: e.y, z: e.z, s: [e.stack.id, e.stack.count, e.stack.damage ?? 0], a: e.age });
    }
    return out;
  }

  /** Restores entities saved with {@link toJSON}. */
  load(data) {
    this.list = [];
    for (const d of data ?? []) {
      if (d.t === 'mob' && this.mobData.mobs[d.k]) {
        const m = this.spawnMob(d.k, d.x, d.y, d.z);
        m.health = d.h; m.yaw = d.yaw ?? 0;
      } else if (d.t === 'item' && this.items.get(d.s[0])) {
        const e = this.dropItem(d.x, d.y, d.z, stack(d.s[0], d.s[1], d.s[2]), { vx: 0, vy: 0, vz: 0, pickupDelay: 0 });
        if (e) e.age = d.a ?? 0;
      }
    }
  }
}

function lerpAngle(a, b, t) {
  let d = b - a;
  while (d > Math.PI) d -= Math.PI * 2;
  while (d < -Math.PI) d += Math.PI * 2;
  return a + d * t;
}

/** Ray vs AABB entry distance, or null. */
export function rayAabb(o, d, b) {
  let tmin = 0, tmax = Infinity;
  for (const [oo, dd, lo, hi] of [[o.x, d.x, b.minX, b.maxX], [o.y, d.y, b.minY, b.maxY], [o.z, d.z, b.minZ, b.maxZ]]) {
    if (Math.abs(dd) < 1e-12) { if (oo < lo || oo > hi) return null; continue; }
    let t1 = (lo - oo) / dd, t2 = (hi - oo) / dd;
    if (t1 > t2) [t1, t2] = [t2, t1];
    tmin = Math.max(tmin, t1); tmax = Math.min(tmax, t2);
    if (tmin > tmax) return null;
  }
  return tmin;
}
