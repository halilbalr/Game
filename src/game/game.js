/**
 * Game session: owns one loaded world and runs the simulation - chunk
 * streaming, player input, block interaction, ticks (liquids, crops,
 * furnaces, mobs), survival, day/night and saving. Rendering and UI are
 * injected so this class stays the single place where rules are applied.
 */
import { TerrainGenerator } from '../world/terrain.js';
import { World } from '../world/world.js';
import { LiquidSystem } from '../world/liquids.js';
import { FACE, FACE_NORMALS, LIQUID, WORLD_HEIGHT, SECTIONS, chunkKey, RENDER } from '../world/constants.js';
import { Player } from '../entities/player.js';
import { BlockColliders, AABB } from '../entities/physics.js';
import { EntityManager } from '../entities/entities.js';
import { raycastBlocks, makeBoundsLookup } from './raycast.js';
import { Inventory, stack } from './inventory.js';
import { breakSeconds, dropsFor, toolWear } from './mining.js';
import { Survival } from './survival.js';
import { mulberry32 } from '../core/random.js';

const OPPOSITE = [FACE.BOTTOM, FACE.TOP, FACE.SOUTH, FACE.NORTH, FACE.EAST, FACE.WEST];

/** Converts a horizontal direction to the FACE it points at. */
function horizontalFacing(dx, dz) {
  if (Math.abs(dx) > Math.abs(dz)) return dx > 0 ? FACE.EAST : FACE.WEST;
  return dz > 0 ? FACE.SOUTH : FACE.NORTH;
}

export class Game {
  /**
   * @param {object} deps
   * @param {object} deps.data all parsed data files keyed by name (blocks, items, game, ...)
   * @param {{blocks: object, items: object}} deps.registries
   * @param {object} deps.crafting CraftingSystem
   * @param {object} deps.furnaceLogic FurnaceLogic
   * @param {object} deps.storage WorldStorage
   * @param {object} deps.settings live settings
   * @param {object} [deps.view] rendering hooks (renderer, entityRenderer, hand) - optional for headless use
   * @param {object} [deps.sound] SoundSystem
   * @param {object} [deps.ui] UI hooks
   */
  constructor(deps) {
    Object.assign(this, deps);
    this.blocks = deps.registries.blocks;
    this.items = deps.registries.items;
    this.cfg = deps.data.game;
    this.colliders = new BlockColliders(this.blocks);
    this.bounds = makeBoundsLookup(this.blocks);
    this.rand = mulberry32((Date.now() & 0xffffffff) >>> 0);
    this.running = false;
    this.paused = false;
    this.selected = 0;
    this.miningKey = null;
    this.miningProgress = 0;
    this.breakCooldown = 0;
    this.useCooldown = 0;
    this.attackCooldown = 0;
    this.eating = null;
    this.tickAccumulator = 0;
    this.saveTimer = 0;
    this.time = 0;
    this.target = null;
    this.gravityQueue = [];
    this.supportQueue = [];
    this.pendingLoads = new Set();
    this.savedKeys = new Set();
    this.hurtTilt = 0;
    this.sleepTimer = 0;
    this.fps = 0;
    this._digSoundTimer = 0;
    this._stepAccum = 0;
    this._spiral = [];
    const maxR = this.cfg.render.maxRenderDistance + 2;
    for (let dz = -maxR; dz <= maxR; dz++) for (let dx = -maxR; dx <= maxR; dx++) this._spiral.push([dx, dz, dx * dx + dz * dz]);
    this._spiral.sort((a, b) => a[2] - b[2]);
  }

  /* ------------------------------------------------------------ lifecycle */

  /**
   * Opens a world (new or saved) and pre-generates the area around the player.
   * @param {object} meta world metadata from storage or the create screen
   * @param {(fraction:number) => void} [onProgress]
   */
  async open(meta, onProgress) {
    this.meta = meta;
    this.generator = new TerrainGenerator(meta.seed, this.data.worldgen, this.blocks);
    this.world = new World({ blocks: this.blocks, generator: this.generator });
    this.liquids = new LiquidSystem(this.world, this.blocks, this.cfg.liquids);
    this.player = new Player(this.data.player, this.colliders, this.blocks);
    this.survival = new Survival(this.data.player.survival, meta.difficulty);
    this.inventory = new Inventory(this.data.ui.inventorySlots, this.items);
    this.entities = new EntityManager({
      world: this.world, blocks: this.blocks, items: this.items, colliders: this.colliders,
      mobData: this.data.mobs, config: this.cfg, rand: this.rand,
      hooks: {
        pickup: (s) => this._pickup(s),
        damagePlayer: (amount, source, fx, fz) => this.damagePlayer(amount, source, fx, fz),
        sound: (name, x, y, z) => this.sound?.play(name, x, y, z),
        explode: (x, y, z, power, damage) => this.explode(x, y, z, power, damage),
      },
    });
    this.entities.difficulty = meta.difficulty;
    this.world.listeners.push((x, y, z, oldId, newId) => this._onBlockChanged(x, y, z, oldId, newId));
    this.savedKeys = await this.storage.savedChunkKeys(meta.id);
    this.creative = meta.mode === 'creative';
    this.player.canFly = this.creative;

    if (meta.player) {
      const p = meta.player;
      this.player.teleport(p.x, p.y, p.z);
      this.player.yaw = p.yaw ?? 0;
      this.player.pitch = p.pitch ?? 0;
      this.player.flying = !!p.flying && this.creative;
      this.inventory.load(meta.inventory);
      this.survival.load(meta.survival);
      this.selected = meta.selected ?? 0;
      // A world saved while dead reopens at the respawn point.
      if (this.survival.dead) this.respawn();
    } else {
      const s = this.generator.findSpawnColumn();
      meta.spawn = { x: s.x + 0.5, y: s.height + 1, z: s.z + 0.5 };
      this.player.teleport(meta.spawn.x, meta.spawn.y + 2, meta.spawn.z);
      if (this.creative) {
        this.data.ui.starterKitCreative.forEach((n, i) => this.inventory.set(i, stack(this.items.id(n), this.items.maxStack(this.items.id(n)))));
      }
    }
    // Pre-load the area around the player before handing control over.
    const r = Math.min(this.settings.renderDistance, 3);
    const pcx = Math.floor(this.player.x) >> 4, pcz = Math.floor(this.player.z) >> 4;
    const needed = this._spiral.filter(([dx, dz]) => Math.max(Math.abs(dx), Math.abs(dz)) <= r + 1);
    let done = 0;
    for (const [dx, dz] of needed) {
      await this._ensureChunk(pcx + dx, pcz + dz, true);
      done++;
      if (done % 4 === 0) { onProgress?.(done / needed.length); await new Promise((res) => setTimeout(res, 0)); }
    }
    if (!meta.player) {
      const sx = Math.floor(this.player.x), sz = Math.floor(this.player.z);
      const top = this.world.topSolidY(sx, sz);
      this.player.teleport(this.player.x, top + 1, this.player.z);
      meta.spawn.y = top + 1;
    }
    this.entities.load(meta.entities);
    this.time = meta.time ?? this.cfg.startTime;
    this.running = true;
    onProgress?.(1);
  }

  /** Generates or loads a chunk. With `wait`, saved chunks are awaited. */
  async _ensureChunk(cx, cz, wait) {
    const key = chunkKey(cx, cz);
    if (this.world.chunks.has(key) || this.pendingLoads.has(key)) return;
    if (this.savedKeys.has(`${cx},${cz}`)) {
      this.pendingLoads.add(key);
      const p = this.storage.loadChunk(this.meta.id, cx, cz).then((data) => {
        this.pendingLoads.delete(key);
        if (!this.running && !wait) return;
        if (data) this.world.insertSavedChunk(cx, cz, data);
        else this._generate(cx, cz);
      }).catch((err) => {
        console.error('chunk load failed', err);
        this.pendingLoads.delete(key);
        this._generate(cx, cz);
      });
      if (wait) await p;
      return;
    }
    this._generate(cx, cz);
  }

  _generate(cx, cz) {
    const c = this.world.generateChunk(cx, cz);
    this.entities.populateChunk(c, (biomeId) => this.generator.biomes[biomeId]?.animals ?? []);
  }

  /** Saves everything that changed. */
  async save() {
    if (!this.meta) return;
    const m = this.meta;
    const p = this.player;
    m.player = { x: p.x, y: p.y, z: p.z, yaw: p.yaw, pitch: p.pitch, flying: p.flying };
    m.inventory = this.inventory.toJSON();
    m.survival = this.survival.toJSON();
    m.entities = this.entities.toJSON();
    m.time = this.time;
    m.selected = this.selected;
    m.lastPlayed = Date.now();
    await this.storage.saveWorld(m);
    const writes = [];
    for (const c of this.world.chunks.values()) {
      if (!c.modified) continue;
      c.modified = false;
      this.savedKeys.add(`${c.cx},${c.cz}`);
      writes.push(this.storage.saveChunk(m.id, c));
    }
    await Promise.all(writes);
  }

  /** Saves and releases the world. */
  async close() {
    this.running = false;
    await this.save();
    this.view?.renderer.clearChunks();
    this.view?.entityRenderer.clear();
  }

  /* ------------------------------------------------------------ helpers */

  get heldStack() { return this.inventory.get(this.selected); }
  get heldItem() { const s = this.heldStack; return s ? this.items.get(s.id) : undefined; }
  get timeOfDay() { return (this.time % this.cfg.dayLengthTicks) / this.cfg.dayLengthTicks; }
  get day() { return Math.floor(this.time / this.cfg.dayLengthTicks) + 1; }
  get isNight() { const t = this.timeOfDay; return t > this.cfg.rules.nightStart && t < this.cfg.rules.nightEnd; }
  get reach() { return this.creative ? this.cfg.interaction.reachCreative : this.cfg.interaction.reachSurvival; }

  _pickup(s) {
    const left = this.inventory.add(s.id, s.count, s.damage ?? 0);
    if (left < s.count) this.sound?.play('pop');
    return left;
  }

  /** Adds items to the inventory, dropping what does not fit. */
  give(id, count, damage = 0) {
    const left = this.inventory.add(id, count, damage);
    if (left > 0) this.entities.dropItem(this.player.x, this.player.y + 1.2, this.player.z, stack(id, left, damage));
  }

  /** Throws items from the player in the look direction. */
  throwStack(s) {
    if (!s) return;
    const d = this.player.lookDir();
    const e = this.player.eye();
    const v = this.cfg.rules.throwSpeed;
    this.entities.dropItem(e.x + d.x * 0.3, e.y - 0.3 + d.y * 0.3, e.z + d.z * 0.3, s, {
      vx: d.x * v, vy: d.y * v + 2, vz: d.z * v, pickupDelay: 1.5,
    });
  }

  /** Drops one (or all) of the held item. */
  dropHeld(all = false) {
    const s = this.heldStack;
    if (!s) return;
    this.throwStack(this.inventory.take(this.selected, all ? s.count : 1));
  }

  damagePlayer(amount, source, fromX, fromZ) {
    if (this.creative || this.survival.dead) return;
    const hit = this.survival.damage(amount, source);
    if (!hit) return;
    this.sound?.play('hurt');
    this.hurtTilt = 1;
    if (fromX !== undefined) {
      const dx = this.player.x - fromX, dz = this.player.z - fromZ;
      const len = Math.hypot(dx, dz) || 1;
      const r = this.cfg.rules;
      this.player.vx += (dx / len) * r.playerKnockback;
      this.player.vz += (dz / len) * r.playerKnockback;
      this.player.vy = Math.max(this.player.vy, r.playerKnockbackUp);
    }
  }

  /* ------------------------------------------------------------ frame */

  /**
   * Runs one animation frame.
   * @param {number} dt seconds since last frame
   * @param {object} input sampled from Controls
   * @param {{took(a:string):boolean}} actions one-shot actions
   */
  frame(dt, input, actions) {
    if (!this.running) return;
    dt = Math.min(dt, 0.1);
    const p = this.player;
    const alive = !this.survival.dead;

    if (!this.paused && alive && this.sleepTimer <= 0) {
      p.yaw -= input.lookX;
      p.pitch = Math.max(-Math.PI / 2 + 0.001, Math.min(Math.PI / 2 - 0.001, p.pitch - input.lookY));
      if (input.wheel) this.select((this.selected + input.wheel + 9) % 9);
      for (let i = 0; i < 9; i++) if (actions.took(`slot${i}`)) this.select(i);
      if (actions.took('drop')) this.dropHeld(false);
      if (actions.took('pick')) this._pickBlock();

      const sub = Math.ceil(dt / (1 / 60));
      const sdt = dt / sub;
      for (let i = 0; i < sub; i++) {
        const prevY = p.y;
        p.update(sdt, input, this.world, { autoJump: this.settings.autoJump && !!this.controlsTouch, canSprint: this.survival.canSprint() || this.creative });
        if (p.landedFallDistance > 0 && !this.creative) {
          const dmg = this.survival.onLanded(p.landedFallDistance);
          if (dmg > 0) { this.sound?.play('hurt'); this.hurtTilt = 1; }
        }
        if (p.jumpedThisFrame && !this.creative) this.survival.addExhaustion(p.sprinting ? this.data.player.survival.exhaustion.sprintJump : this.data.player.survival.exhaustion.jump);
        void prevY;
      }
      if (p.y < this.cfg.rules.voidY) this.damagePlayer(this.cfg.rules.voidDamage, 'void');
      this._updateTarget();
      this._interact(dt, input, actions);
      this._footsteps(dt);
    } else {
      this.renderSelection(null, -1);
    }

    this.tickAccumulator += dt;
    const tickLen = 1 / this.cfg.ticksPerSecond;
    let ticks = 0;
    while (this.tickAccumulator >= tickLen && ticks < 5) {
      this.tickAccumulator -= tickLen;
      if (!this.paused) this.tick();
      ticks++;
    }
    if (ticks >= 5) this.tickAccumulator = 0;

    if (!this.paused) {
      this.entities.update(dt, p, { daylight: this.view?.renderer.daylight ?? 1, gameMode: this.meta.mode, playerDead: !alive });
      if (alive) this.entities.updateSpawning(dt, p, { daylight: this.view?.renderer.daylight ?? 1, difficulty: this.meta.difficulty, gameMode: this.meta.mode });
    }
    this._streamChunks();

    if (this.sleepTimer > 0) {
      this.sleepTimer -= dt;
      if (this.sleepTimer <= 0) {
        const len = this.cfg.dayLengthTicks;
        this.time = (Math.floor(this.time / len) + 1) * len;
        this.ui?.toast(this.ui.t('msg.day', { n: this.day }));
      }
    }
    if (this.hurtTilt > 0) this.hurtTilt = Math.max(0, this.hurtTilt - dt * 3);
    this.saveTimer += dt;
    if (this.saveTimer > this.cfg.autosaveSeconds) {
      this.saveTimer = 0;
      this.save().catch((err) => console.error('autosave failed', err));
    }
  }

  select(i) {
    if (i === this.selected) return;
    this.selected = i;
    this.eating = null;
    this.miningKey = null;
    this.miningProgress = 0;
  }

  _footsteps(dt) {
    const p = this.player;
    if (p.onGround && !p.flying && p.stepDistance > (p.sprinting ? this.cfg.rules.stepDistanceSprint : this.cfg.rules.stepDistanceWalk)) {
      p.stepDistance = 0;
      const id = p.groundBlock;
      const def = this.blocks.defs[id];
      if (def && id) this.sound?.play(`step_${def.sound}`, p.x, p.y, p.z, 0.8);
      if (!this.creative && p.sprinting) this.survival.addExhaustion(this.data.player.survival.exhaustion.perBlockSprint * 2);
    }
    if (p.inWater && !this.creative) this.survival.addExhaustion(this.data.player.survival.exhaustion.perBlockSwim * dt * 4);
  }

  _streamChunks() {
    const p = this.player;
    const pcx = Math.floor(p.x) >> 4, pcz = Math.floor(p.z) >> 4;
    const R = this.settings.renderDistance + 1;
    const start = performance.now();
    const budget = this.cfg.render.generateBudgetMs;
    for (const [dx, dz] of this._spiral) {
      if (Math.max(Math.abs(dx), Math.abs(dz)) > R) continue;
      const cx = pcx + dx, cz = pcz + dz;
      const key = chunkKey(cx, cz);
      if (this.world.chunks.has(key) || this.pendingLoads.has(key)) continue;
      this._ensureChunk(cx, cz, false);
      if (performance.now() - start > budget) break;
    }
    // Unload far chunks (saving modified ones first).
    const U = R + 2;
    for (const c of [...this.world.chunks.values()]) {
      if (Math.max(Math.abs(c.cx - pcx), Math.abs(c.cz - pcz)) <= U) continue;
      if (c.modified) {
        this.savedKeys.add(`${c.cx},${c.cz}`);
        this.storage.saveChunk(this.meta.id, c).catch((err) => console.error('chunk save failed', err));
      }
      this.world.removeChunk(c.cx, c.cz);
    }
  }

  /* ------------------------------------------------------------ targeting & interaction */

  _isSelectable = (id) => !this.blocks.liquid[id] && this.blocks.render[id] !== RENDER.none;

  _updateTarget() {
    const p = this.player;
    const eye = p.eye(), dir = p.lookDir();
    const hit = raycastBlocks(this.world, this._isSelectable, eye, dir, this.reach, this.bounds);
    const r = this.cfg.rules;
    const mob = this.entities.raycastMob(eye, dir, Math.min(this.reach, this.creative ? r.mobReachCreative : r.mobReachSurvival));
    if (mob && (!hit || mob.dist < hit.dist)) this.target = { type: 'mob', mob: mob.mob, dist: mob.dist };
    else if (hit) this.target = { type: 'block', ...hit };
    else this.target = null;
  }

  renderSelection(target, progress) {
    this.view?.renderer.setSelection(target, progress);
  }

  _interact(dt, input, actions) {
    const it = this.cfg.interaction;
    this.breakCooldown -= dt;
    this.useCooldown -= dt;
    this.attackCooldown -= dt;
    const t = this.target;

    if (actions.took('attack')) {
      if (t?.type === 'mob') this.attack(t.mob);
      else this.view?.hand.doSwing();
    }
    if (actions.took('tap')) {
      if (t?.type === 'mob') this.attack(t.mob);
      else this.use();
    }
    if (actions.took('use')) { this.use(); this.useCooldown = it.placeCooldown + 0.1; }
    else if (input.useHeld && this.useCooldown <= 0) { this.use(true); this.useCooldown = it.placeCooldown; }

    // Holding on a mob keeps attacking at the cooldown rate (touch).
    if (input.breakHeld && t?.type === 'mob' && this.attackCooldown <= 0 && this.controlsTouch) this.attack(t.mob);

    if (input.breakHeld && t?.type === 'block') this._mine(dt, t);
    else { this.miningKey = null; this.miningProgress = 0; }
    this.renderSelection(t?.type === 'block' ? t : null, this.miningProgress > 0 ? this.miningProgress : -1);

    // Eating continues over time once started.
    if (this.eating) {
      this.eating.t += dt;
      if (Math.floor(this.eating.t * 4) !== Math.floor((this.eating.t - dt) * 4)) { this.sound?.play('eat'); this.view?.hand.doSwing(); }
      if (this.eating.t >= this.data.player.survival.eatSeconds) {
        const s = this.heldStack;
        const item = this.heldItem;
        if (s && item?.food && s.id === this.eating.id) {
          this.survival.eat(item.food);
          this.inventory.take(this.selected, 1);
          this.sound?.play('burp');
        }
        this.eating = null;
      }
    }
  }

  _mine(dt, t) {
    const key = `${t.x},${t.y},${t.z}`;
    if (this.breakCooldown > 0) return;
    const def = this.blocks.defs[t.id];
    if (this.creative) {
      if (this.heldItem?.tool?.type === 'sword') return;
      this.breakBlock(t.x, t.y, t.z);
      this.breakCooldown = this.cfg.interaction.creativeBreakCooldown;
      return;
    }
    if (key !== this.miningKey) { this.miningKey = key; this.miningProgress = 0; }
    const p = this.player;
    const secs = breakSeconds(def, this.heldItem, {
      onGround: p.onGround || p.flying, inWater: p.eyeIn === 'water',
      waterFactor: this.cfg.interaction.inWaterMiningFactor, airFactor: this.cfg.interaction.airborneMiningFactor,
      swordLeavesSpeed: this.data.items.swordLeavesSpeed,
    });
    if (secs === Infinity) return;
    this.miningProgress += secs === 0 ? 1 : dt / secs;
    this._digSoundTimer -= dt;
    if (this._digSoundTimer <= 0) {
      this._digSoundTimer = this.cfg.rules.digSoundInterval;
      this.sound?.play(`dig_${def.sound}`, t.x + 0.5, t.y + 0.5, t.z + 0.5);
      this.view?.hand.doSwing();
    }
    if (this.miningProgress >= 1) {
      this.breakBlock(t.x, t.y, t.z);
      this.miningKey = null;
      this.miningProgress = 0;
      this.breakCooldown = secs === 0 ? this.cfg.rules.breakDelayInstant : this.cfg.rules.breakDelay;
    }
  }

  /** Breaks a block as the player: drops, tool wear, effects. */
  breakBlock(x, y, z) {
    const id = this.world.getBlock(x, y, z);
    if (!id) return;
    const def = this.blocks.defs[id];
    const meta = this.world.getMeta(x, y, z);
    this._dropContainer(x, y, z);
    if (def.bedPart) this._removeOtherBedHalf(x, y, z, def, meta);
    this.world.setBlock(x, y, z, 0);
    this.view?.entityRenderer.particles.burst(x, y, z, this.blocks.tileFor(id, FACE.NORTH, meta), this._tintAt(x, z, id));
    this.sound?.play(`break_${def.sound}`, x + 0.5, y + 0.5, z + 0.5);
    this.view?.hand.doSwing();
    if (this.creative) return;
    const item = this.heldItem;
    for (const d of dropsFor(def, meta, item, this.rand, this.items)) {
      this.entities.dropItem(x + 0.5, y + 0.3, z + 0.5, stack(d.id, d.count));
    }
    if (def.hardness > 0) this._wearHeld('break');
    this.survival.addExhaustion(this.data.player.survival.exhaustion.breakBlock);
  }

  _tintAt(x, z, id) {
    const c = this.world.getChunk(x >> 4, z >> 4);
    if (!c) return [255, 255, 255];
    const i = (((z & 15) << 4) | (x & 15)) * 3;
    const src = this.blocks.foliage[id] ? c.foliageTint : c.grassTint;
    return [src[i], src[i + 1], src[i + 2]];
  }

  _wearHeld(action) {
    const s = this.heldStack, item = this.heldItem;
    if (!s || !item?.tool) return;
    s.damage = (s.damage ?? 0) + toolWear(item, action);
    if (s.damage >= item.tool.durability) {
      this.inventory.set(this.selected, null);
      this.sound?.play('break_wood');
    } else this.inventory.set(this.selected, s);
  }

  _dropContainer(x, y, z) {
    const be = this.world.getBlockEntity(x, y, z);
    if (!be) return;
    const stacks = be.type === 'chest' ? be.slots : [be.input, be.fuel, be.output];
    for (const s of stacks) if (s) this.entities.dropItem(x + 0.5, y + 0.5, z + 0.5, s);
    this.ui?.closeContainerAt?.(x, y, z);
  }

  _removeOtherBedHalf(x, y, z, def, meta) {
    const f = meta & 7;
    const [nx, , nz] = FACE_NORMALS[f];
    const dir = def.bedPart === 'foot' ? 1 : -1;
    const ox = x + nx * dir, oz = z + nz * dir;
    const other = this.world.getBlock(ox, y, oz);
    if (this.blocks.defs[other]?.bedPart) this.world.setBlock(ox, y, oz, 0);
  }

  /** Melee attack on a mob. */
  attack(mob) {
    if (this.attackCooldown > 0) return;
    this.attackCooldown = this.cfg.interaction.attackCooldown;
    const item = this.heldItem;
    const rules = this.cfg.rules;
    let dmg = item?.tool ? item.tool.attack : this.items.fistDamage;
    if (!this.player.onGround && this.player.vy < 0 && !this.player.flying) dmg *= rules.critMultiplier;
    if (this.creative) dmg = Math.max(dmg, rules.creativeMinAttack);
    this.view?.hand.doSwing();
    if (this.entities.hurtMob(mob, dmg, this.player.x, this.player.z)) {
      if (!this.creative) { this._wearHeld('attack'); this.survival.addExhaustion(this.data.player.survival.exhaustion.attack); }
    }
  }

  /** Tap / right click: interact with a block, eat, use buckets/hoes or place. */
  use(repeat = false) {
    const t = this.target;
    const s = this.heldStack, item = this.heldItem;
    this.eating = repeat ? this.eating : null;
    if (t?.type === 'block') {
      const def = this.blocks.defs[t.id];
      if (def.interact && !this.player.sneaking && !repeat) {
        this.interactBlock(def.interact, t.x, t.y, t.z);
        return;
      }
    }
    if (!item) return;
    if (item.food && !repeat) {
      if (this.survival.canEat() || this.creative) this.eating = { id: s.id, t: 0 };
      return;
    }
    if (item.bucket && !repeat) { this._useBucket(item); return; }
    if (t?.type !== 'block') return;
    if (item.tool?.type === 'hoe') {
      const above = this.world.getBlock(t.x, t.y + 1, t.z);
      const name = this.blocks.defs[t.id].name;
      if ((name === 'grass_block' || name === 'dirt') && (above === 0 || this.blocks.replaceable[above] && !this.blocks.liquid[above])) {
        if (above) this.world.setBlock(t.x, t.y + 1, t.z, 0);
        this.world.setBlock(t.x, t.y, t.z, this.blocks.id('farmland'));
        this.sound?.play('place_gravel', t.x, t.y, t.z);
        this.view?.hand.doSwing();
        if (!this.creative) this._wearHeld('break');
      }
      return;
    }
    const blockId = item.isBlock ? item.blockId : (item.places ? this.blocks.id(item.places) : -1);
    if (blockId > 0) this._place(blockId, t);
  }

  _place(blockId, t) {
    const B = this.blocks;
    const def = B.defs[blockId];
    let px, py, pz, face = t.face;
    if (B.replaceable[t.id] && !B.liquid[t.id]) { px = t.x; py = t.y; pz = t.z; face = FACE.TOP; }
    else { const n = FACE_NORMALS[t.face]; px = t.x + n[0]; py = t.y + n[1]; pz = t.z + n[2]; }
    if (py < 0 || py >= WORLD_HEIGHT) return;
    const cur = this.world.getBlock(px, py, pz);
    if (cur !== 0 && !B.replaceable[cur]) return;
    let meta = 0;
    const p = this.player;
    const look = p.lookDir();
    if (def.place?.soil) {
      const below = B.defs[this.world.getBlock(px, py - 1, pz)]?.name;
      if (!def.place.soil.includes(below)) return;
      if (def.renderId === RENDER.cactus) {
        for (const [dx, dz] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) if (B.solid[this.world.getBlock(px + dx, py, pz + dz)]) return;
      }
    }
    if (def.place?.support) {
      if (face === FACE.BOTTOM) return;
      const n = FACE_NORMALS[face];
      const sx = px - n[0], sy = py - n[1], sz = pz - n[2];
      const sid = this.world.getBlock(sx, sy, sz);
      if (!B.solid[sid] || !B.opaque[sid]) return;
      meta = face === FACE.TOP ? 0 : OPPOSITE[face];
    }
    if (def.orient && !def.bedPart) meta = OPPOSITE[horizontalFacing(look.x, look.z)];
    let headPos = null;
    if (def.bedPart === 'foot') {
      const f = horizontalFacing(look.x, look.z);
      meta = f;
      const n = FACE_NORMALS[f];
      headPos = [px + n[0], py, pz + n[2]];
      const hcur = this.world.getBlock(...headPos);
      if (hcur !== 0 && !B.replaceable[hcur]) return;
      if (!B.solid[this.world.getBlock(px, py - 1, pz)] || !B.solid[this.world.getBlock(headPos[0], py - 1, headPos[2])]) return;
    }
    if (B.solid[blockId]) {
      const shape = this.colliders.shapes[blockId];
      const box = new AABB(px + shape[0], py + shape[1], pz + shape[2], px + shape[3], py + shape[4], pz + shape[5]);
      if (box.intersects(p.box())) return;
      for (const e of this.entities.list) if (e.type === 'mob' && !e.dead && box.intersects(e.box())) return;
    }
    this.world.setBlock(px, py, pz, blockId, meta);
    if (headPos) this.world.setBlock(headPos[0], headPos[1], headPos[2], B.id('bed_head'), meta);
    if (def.name.endsWith('leaves')) this.world.setMeta(px, py, pz, 1);
    if (def.interact === 'chest') this.world.setBlockEntity(px, py, pz, { type: 'chest', slots: new Array(this.data.ui.chestSlots).fill(null) });
    if (def.interact === 'furnace') this.world.setBlockEntity(px, py, pz, { type: 'furnace', ...this.furnaceLogic.createState() });
    this.sound?.play(`place_${def.sound}`, px + 0.5, py + 0.5, pz + 0.5);
    this.view?.hand.doSwing();
    if (!this.creative) this.inventory.take(this.selected, 1);
  }

  _useBucket(item) {
    const B = this.blocks;
    const p = this.player;
    const eye = p.eye(), dir = p.lookDir();
    if (item.bucket === 'empty') {
      const hit = raycastBlocks(this.world, (id, x, y, z) => B.liquid[id] ? this.world.getMeta(x, y, z) === 0 : this._isSelectable(id), eye, dir, this.reach, this.bounds);
      if (!hit || !B.liquid[hit.id]) return;
      const filled = this.items.id(B.liquid[hit.id] === LIQUID.water ? 'water_bucket' : 'lava_bucket');
      this.world.setBlock(hit.x, hit.y, hit.z, 0);
      this.sound?.play('splash', hit.x, hit.y, hit.z);
      if (this.creative) return;
      this.inventory.take(this.selected, 1);
      if (!this.inventory.get(this.selected)) this.inventory.set(this.selected, stack(filled, 1));
      else this.give(filled, 1);
      return;
    }
    const t = this.target;
    if (t?.type !== 'block') return;
    let px = t.x, py = t.y, pz = t.z;
    if (!B.replaceable[t.id]) { const n = FACE_NORMALS[t.face]; px += n[0]; py += n[1]; pz += n[2]; }
    const cur = this.world.getBlock(px, py, pz);
    if (cur !== 0 && !B.replaceable[cur]) return;
    this.world.setBlock(px, py, pz, B.id(item.bucket === 'water' ? 'water' : 'lava'), 0);
    this.sound?.play('splash', px, py, pz);
    if (!this.creative) this.inventory.set(this.selected, stack(this.items.id('bucket'), 1));
  }

  _pickBlock() {
    const t = this.target;
    if (t?.type !== 'block') return;
    let id = t.id;
    const def = this.blocks.defs[id];
    if (def.name === 'lit_furnace') id = this.items.id('furnace');
    if (def.bedPart) id = this.items.id('bed');
    for (let i = 0; i < 9; i++) if (this.inventory.get(i)?.id === id) { this.select(i); return; }
    if (this.creative && this.items.get(id)) this.inventory.set(this.selected, stack(id, this.items.maxStack(id)));
  }

  /** Opens a block's UI or uses it (beds). */
  interactBlock(kind, x, y, z) {
    if (kind === 'bed') { this.sleep(x, y, z); return; }
    if (kind === 'crafting') { this.ui?.openScreen('crafting', { x, y, z }); return; }
    let be = this.world.getBlockEntity(x, y, z);
    if (!be) {
      be = kind === 'chest' ? { type: 'chest', slots: new Array(this.data.ui.chestSlots).fill(null) } : { type: 'furnace', ...this.furnaceLogic.createState() };
      this.world.setBlockEntity(x, y, z, be);
    }
    this.ui?.openScreen(kind, { x, y, z, entity: be });
  }

  sleep(x, y, z) {
    if (!this.isNight) { this.ui?.toast(this.ui.t('msg.sleepNotNight')); return; }
    const R = this.cfg.rules.sleepMonsterRadius;
    const near = this.entities.list.some((e) => e.type === 'mob' && e.def.hostile && !e.dead
      && Math.abs(e.x - x) < R && Math.abs(e.y - y) < R / 2 && Math.abs(e.z - z) < R);
    if (near && !this.creative) { this.ui?.toast(this.ui.t('msg.sleepMonsters')); return; }
    this.meta.spawn = { x: x + 0.5, y: y + 1, z: z + 0.5 };
    this.ui?.toast(this.ui.t('msg.spawnSet'));
    this.sleepTimer = this.cfg.rules.sleepSeconds;
    this.ui?.sleepFade(this.cfg.rules.sleepSeconds);
  }

  /** Respawns after death. */
  respawn() {
    const s = this.meta.spawn;
    const x = Math.floor(s.x), z = Math.floor(s.z);
    for (let dz = -1; dz <= 1; dz++) for (let dx = -1; dx <= 1; dx++) {
      const cx = (x >> 4) + dx, cz = (z >> 4) + dz;
      if (!this.world.getChunk(cx, cz)) this._generate(cx, cz);
    }
    let y = s.y;
    const bedHere = this.blocks.defs[this.world.getBlock(x, Math.floor(s.y) - 1, z)]?.bedPart;
    if (!bedHere) y = this.world.topSolidY(x, z) + 1;
    this.player.teleport(s.x, y, s.z);
    this.player.flying = false;
    this.survival.reset();
    this.deathHandled = false;
    this.hurtTilt = 0;
  }

  /** Called once when the player dies: scatter the inventory. */
  onDeath() {
    if (this.creative) return;
    for (let i = 0; i < this.inventory.size; i++) {
      const s = this.inventory.get(i);
      if (s) this.entities.dropItem(this.player.x, this.player.y + 0.5, this.player.z, s, {
        vx: (this.rand() - 0.5) * this.cfg.rules.deathDropSpeed, vy: 3 + this.rand() * 3, vz: (this.rand() - 0.5) * this.cfg.rules.deathDropSpeed, pickupDelay: 2,
      });
    }
    this.inventory.clear();
  }

  /** Explosion: destroys blocks, damages and knocks back entities. */
  explode(x, y, z, power, damage) {
    const B = this.blocks;
    const rules = this.cfg.rules;
    const r = power;
    const bedrock = B.id('bedrock');
    for (let dy = -r; dy <= r; dy++) {
      for (let dz = -r; dz <= r; dz++) {
        for (let dx = -r; dx <= r; dx++) {
          const d = Math.sqrt(dx * dx + dy * dy + dz * dz);
          if (d > r * (0.75 + this.rand() * 0.3)) continue;
          const bx = Math.floor(x + dx), by = Math.floor(y + dy), bz = Math.floor(z + dz);
          const id = this.world.getBlock(bx, by, bz);
          if (!id || id === bedrock || B.liquid[id]) continue;
          const def = B.defs[id];
          if (def.hardness < 0 || def.hardness >= rules.explosionMaxHardness) continue;
          this._dropContainer(bx, by, bz);
          this.world.setBlock(bx, by, bz, 0);
          if (this.rand() < rules.explosionDropChance) for (const dr of dropsFor(def, 0, undefined, this.rand, this.items)) {
            this.entities.dropItem(bx + 0.5, by + 0.5, bz + 0.5, stack(dr.id, dr.count));
          }
          if (this.rand() < 0.15) this.view?.entityRenderer.particles.burst(bx, by, bz, B.tileFor(id, FACE.NORTH, 0), [255, 255, 255], 4);
        }
      }
    }
    this.sound?.play('explode', x, y, z, 1.5);
    const reach = r * rules.explosionReachFactor;
    const p = this.player;
    const pd = Math.hypot(p.x - x, p.y + 0.9 - y, p.z - z);
    if (pd < reach) {
      this.damagePlayer(Math.max(1, Math.round(damage * (1 - pd / reach))), 'explosion', x, z);
      const k = (1 - pd / reach) * rules.explosionKnockback;
      p.vx += ((p.x - x) / (pd || 1)) * k; p.vy += 4 * (1 - pd / reach) + 2; p.vz += ((p.z - z) / (pd || 1)) * k;
    }
    for (const e of this.entities.list) {
      if (e.type !== 'mob' || e.dead) continue;
      const d = Math.hypot(e.x - x, e.y - y, e.z - z);
      if (d < reach) this.entities.hurtMob(e, Math.round(damage * (1 - d / reach)), x, z);
    }
  }

  /* ------------------------------------------------------------ ticks */

  tick() {
    this.time++;
    this.liquids.update();
    this._processQueues();
    this._randomTicks();
    this._tickFurnaces();
    const p = this.player;
    const touchingCactus = this._touchingCactus();
    if (!this.creative) {
      this.survival.tick({ headInWater: p.eyeIn === 'water', inLava: p.inLava, touchingCactus });
      if (this.survival.hurtFlash === 1 && this.survival.lastDamage !== 'fall') { this.hurtTilt = Math.max(this.hurtTilt, 0.6); }
    }
    // Damage can come from anywhere (mobs, explosions, falls), so death is detected here once.
    if (this.survival.dead && !this.deathHandled) {
      this.deathHandled = true;
      this.onDeath();
      this.ui?.showDeath(this.survival.lastDamage);
    }
  }

  _touchingCactus() {
    const box = this.player.box();
    box.minX -= 0.05; box.maxX += 0.05; box.minZ -= 0.05; box.maxZ += 0.05; box.minY -= 0.05;
    const cactus = this.blocks.id('cactus');
    for (let x = Math.floor(box.minX); x <= Math.floor(box.maxX); x++) {
      for (let y = Math.floor(box.minY); y <= Math.floor(box.maxY); y++) {
        for (let z = Math.floor(box.minZ); z <= Math.floor(box.maxZ); z++) {
          if (this.world.getBlock(x, y, z) === cactus) return true;
        }
      }
    }
    return false;
  }

  _onBlockChanged(x, y, z, oldId, newId) {
    const B = this.blocks;
    if (B.gravity[newId]) this.gravityQueue.push([x, y, z]);
    if (!B.solid[newId] || B.liquid[newId]) {
      this.gravityQueue.push([x, y + 1, z]);
      this.supportQueue.push([x, y + 1, z], [x + 1, y, z], [x - 1, y, z], [x, y, z + 1], [x, y, z - 1]);
    }
  }

  _processQueues() {
    const B = this.blocks;
    const gq = this.gravityQueue;
    this.gravityQueue = [];
    for (const [x, y, z] of gq) {
      const id = this.world.getBlock(x, y, z);
      if (!B.gravity[id] || y <= 0) continue;
      const below = this.world.getBlock(x, y - 1, z);
      if (below === 0 || (B.replaceable[below] && !B.solid[below]) || B.liquid[below]) {
        const meta = this.world.getMeta(x, y, z);
        this.world.setBlock(x, y, z, 0);
        this.entities.spawnFallingBlock(x, y, z, id, meta);
      }
    }
    const sq = this.supportQueue;
    this.supportQueue = [];
    for (const [x, y, z] of sq) {
      const id = this.world.getBlock(x, y, z);
      if (!id) continue;
      const def = B.defs[id];
      if (!def.place) continue;
      let ok = true;
      if (def.place.soil) ok = def.place.soil.includes(B.defs[this.world.getBlock(x, y - 1, z)]?.name);
      if (def.place.support) {
        const meta = this.world.getMeta(x, y, z);
        const n = meta === 0 ? [0, -1, 0] : FACE_NORMALS[meta];
        const sid = this.world.getBlock(x + n[0], y + n[1], z + n[2]);
        ok = B.solid[sid] && B.opaque[sid];
      }
      if (!ok) {
        const meta = this.world.getMeta(x, y, z);
        this.world.setBlock(x, y, z, 0);
        if (!this.creative || true) {
          for (const d of dropsFor(def, meta, undefined, this.rand, this.items)) this.entities.dropItem(x + 0.5, y + 0.3, z + 0.5, stack(d.id, d.count));
        }
      }
    }
  }

  _randomTicks() {
    const n = this.cfg.randomTickSpeed;
    const B = this.blocks;
    for (const c of this.world.chunks.values()) {
      if (!c.lit) continue;
      for (let s = 0; s < SECTIONS; s++) {
        if (c.sectionCounts[s] === 0) continue;
        for (let k = 0; k < n; k++) {
          const r = (this.rand() * 4096) | 0;
          const lx = r & 15, lz = (r >> 4) & 15, ly = (s << 4) | (r >> 8);
          const id = c.blocks[(ly << 8) | (lz << 4) | lx];
          if (!id) continue;
          const kind = B.defs[id].randomTick;
          if (kind) this._randomTick(kind, (c.cx << 4) + lx, ly, (c.cz << 4) + lz, id);
        }
      }
    }
  }

  _lightAt(x, y, z) {
    const daylight = this.view?.renderer.daylight ?? 1;
    return Math.max(this.world.getSkyLight(x, y, z) * daylight, this.world.getBlockLight(x, y, z));
  }

  _randomTick(kind, x, y, z, id) {
    const B = this.blocks, w = this.world;
    const rules = this.cfg.rules;
    switch (kind) {
      case 'grass': {
        const above = w.getBlock(x, y + 1, z);
        if (B.opaque[above] || B.liquid[above]) { w.setBlock(x, y, z, B.id('dirt')); return; }
        const tx = x + Math.floor(this.rand() * 3) - 1, ty = y + Math.floor(this.rand() * 5) - 3, tz = z + Math.floor(this.rand() * 3) - 1;
        if (w.getBlock(tx, ty, tz) === B.id('dirt')) {
          const a = w.getBlock(tx, ty + 1, tz);
          if (!B.opaque[a] && !B.liquid[a] && w.getSkyLight(tx, ty + 1, tz) >= rules.growthMinLight) w.setBlock(tx, ty, tz, id);
        }
        return;
      }
      case 'crop': {
        const meta = w.getMeta(x, y, z);
        const def = B.defs[id];
        if (meta < def.maxStage && this._lightAt(x, y, z) >= rules.growthMinLight && this.rand() < rules.cropGrowChance) w.setMeta(x, y, z, meta + 1);
        return;
      }
      case 'sapling': {
        if (this.rand() > rules.saplingGrowChance || this._lightAt(x, y, z) < rules.growthMinLight) return;
        const tree = this.generator.treeDefs[B.defs[id].tree];
        for (let dy = 1; dy <= tree.maxHeight; dy++) if (w.getBlock(x, y + dy, z) !== 0) return;
        w.setBlock(x, y, z, 0);
        const rand = this.rand;
        this.generator.placeTree(tree, x, y, z, rand, (tx, ty, tz, tid, onlyAir) => {
          const cur = w.getBlock(tx, ty, tz);
          if (onlyAir ? (cur === 0 || (B.replaceable[cur] && !B.liquid[cur])) : cur !== B.id('bedrock')) w.setBlock(tx, ty, tz, tid);
        });
        return;
      }
      case 'leaves': {
        if (w.getMeta(x, y, z) & 1) return;
        const R = rules.leafDecayRange;
        for (let dy = -R; dy <= R; dy++) for (let dz = -R; dz <= R; dz++) for (let dx = -R; dx <= R; dx++) {
          if (Math.abs(dx) + Math.abs(dy) + Math.abs(dz) > rules.leafDecayManhattan) continue;
          const b = B.defs[w.getBlock(x + dx, y + dy, z + dz)];
          if (b && b.name.endsWith('_log')) return;
        }
        const def = B.defs[id];
        w.setBlock(x, y, z, 0);
        for (const d of dropsFor(def, 0, undefined, this.rand, this.items)) this.entities.dropItem(x + 0.5, y + 0.3, z + 0.5, stack(d.id, d.count));
        return;
      }
      case 'farmland': {
        const above = w.getBlock(x, y + 1, z);
        if (B.defs[above]?.name === 'wheat_crop') return;
        let water = false;
        const R = rules.farmlandWaterRange;
        for (let dz = -R; dz <= R && !water; dz++) for (let dx = -R; dx <= R && !water; dx++) {
          if (B.liquid[w.getBlock(x + dx, y, z + dz)] === LIQUID.water) water = true;
        }
        if (!water && this.rand() < rules.farmlandRevertChance) w.setBlock(x, y, z, B.id('dirt'));
        return;
      }
      default:
    }
  }

  _tickFurnaces() {
    const B = this.blocks;
    const furnace = B.id('furnace'), lit = B.id('lit_furnace');
    for (const c of this.world.chunks.values()) {
      if (!c.blockEntities.size) continue;
      for (const [idx, be] of c.blockEntities) {
        if (be.type !== 'furnace') continue;
        const r = this.furnaceLogic.tick(be);
        if (!r.changed) continue;
        c.modified = true;
        const x = (c.cx << 4) + (idx & 15), y = idx >> 8, z = (c.cz << 4) + ((idx >> 4) & 15);
        const cur = c.blocks[idx];
        const want = r.lit ? lit : furnace;
        if (cur !== want && (cur === lit || cur === furnace)) {
          const meta = c.meta[idx];
          this.world.setBlock(x, y, z, want, meta);
          c.blockEntities.set(idx, be);
        }
      }
    }
  }
}
