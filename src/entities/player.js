/**
 * Player movement: walking, sprinting, sneaking (with edge protection),
 * jumping, swimming and creative flight. Survival stats live in
 * game/survival.js; this class only moves the body.
 */
import { AABB, moveBox } from './physics.js';
import { LIQUID } from '../world/constants.js';

export class Player {
  /**
   * @param {object} cfg parsed player.json
   * @param {import('./physics.js').BlockColliders} colliders
   * @param {import('../world/registry.js').BlockRegistry} blocks
   */
  constructor(cfg, colliders, blocks) {
    this.cfg = cfg;
    this.colliders = colliders;
    this.blocks = blocks;
    this.x = 0; this.y = 80; this.z = 0;
    this.vx = 0; this.vy = 0; this.vz = 0;
    this.yaw = 0;
    this.pitch = 0;
    this.onGround = false;
    this.flying = false;
    this.canFly = false;
    this.sneaking = false;
    this.sprinting = false;
    this.inWater = false;
    this.inLava = false;
    this.eyeIn = null;
    this.onIce = false;
    this.horizontalCollision = false;
    this.eyeOffset = cfg.eyeHeight;
    /** Highest y since leaving the ground, for fall damage. */
    this.fallStartY = null;
    /** Distance fallen on the most recent landing (consumed by survival). */
    this.landedFallDistance = 0;
    this.distanceWalked = 0;
    this.stepDistance = 0;
    this.jumpedThisFrame = false;
    this._lastJumpPress = -1;
    this._wasJumpDown = false;
    this._time = 0;
  }

  get height() { return this.sneaking && !this.flying ? this.cfg.sneakHeight : this.cfg.height; }

  /** Eye position in world space. */
  eye() { return { x: this.x, y: this.y + this.eyeOffset, z: this.z }; }

  box() { return AABB.fromFeet(this.x, this.y, this.z, this.cfg.halfWidth, this.height); }

  /** Unit look direction from yaw/pitch (yaw 0 looks towards -z). */
  lookDir() {
    const cp = Math.cos(this.pitch);
    return { x: -Math.sin(this.yaw) * cp, y: Math.sin(this.pitch), z: -Math.cos(this.yaw) * cp };
  }

  teleport(x, y, z) {
    this.x = x; this.y = y; this.z = z;
    this.vx = this.vy = this.vz = 0;
    this.fallStartY = null;
  }

  _sampleEnvironment(world) {
    const B = this.blocks;
    const box = this.box();
    let water = false, lava = false;
    const x0 = Math.floor(box.minX + 0.001), x1 = Math.floor(box.maxX - 0.001);
    const y0 = Math.floor(box.minY + 0.001), y1 = Math.floor(box.minY + 1.2);
    const z0 = Math.floor(box.minZ + 0.001), z1 = Math.floor(box.maxZ - 0.001);
    for (let x = x0; x <= x1; x++) for (let y = y0; y <= y1; y++) for (let z = z0; z <= z1; z++) {
      const l = B.liquid[world.getBlock(x, y, z)];
      if (l === LIQUID.water) water = true;
      else if (l === LIQUID.lava) lava = true;
    }
    this.inWater = water;
    this.inLava = lava;
    const ey = this.y + this.eyeOffset;
    const eyeId = world.getBlock(Math.floor(this.x), Math.floor(ey), Math.floor(this.z));
    const el = B.liquid[eyeId];
    this.eyeIn = null;
    if (el) {
      const meta = world.getMeta(Math.floor(this.x), Math.floor(ey), Math.floor(this.z));
      const above = B.liquid[world.getBlock(Math.floor(this.x), Math.floor(ey) + 1, Math.floor(this.z))];
      const h = above ? 1 : (meta === 0 || meta === 8 ? 8 / 9 : (8 - meta) / 9);
      if (ey - Math.floor(ey) < h) this.eyeIn = el === LIQUID.water ? 'water' : 'lava';
    }
    const below = world.getBlock(Math.floor(this.x), Math.floor(this.y - 0.05), Math.floor(this.z));
    this.onIce = !!B.defs[below]?.slippery;
    this.groundBlock = below;
  }

  /**
   * Advances movement.
   * @param {number} dt seconds (already clamped by the caller)
   * @param {{forward:number, strafe:number, jump:boolean, sneak:boolean, sprint:boolean}} input
   * @param {object} world
   * @param {{autoJump:boolean}} opts
   */
  update(dt, input, world, opts = {}) {
    const c = this.cfg;
    this._time += dt;
    this.jumpedThisFrame = false;
    // Double-tap jump toggles flight in creative.
    if (input.jump && !this._wasJumpDown) {
      if (this.canFly && this._time - this._lastJumpPress < c.doubleTapSeconds) {
        this.flying = !this.flying;
        this.vy = 0;
        this._lastJumpPress = -1;
      } else {
        this._lastJumpPress = this._time;
      }
    }
    this._wasJumpDown = input.jump;
    if (!this.canFly) this.flying = false;

    this._sampleEnvironment(world);
    this.sneaking = !!input.sneak && !this.flying;
    const moving = Math.hypot(input.forward, input.strafe) > 0.1;
    if (input.sprint && input.forward > 0.5 && !this.sneaking && opts.canSprint !== false) this.sprinting = true;
    if (!moving || input.forward <= 0 || this.sneaking || this.horizontalCollision || opts.canSprint === false) this.sprinting = false;

    let speed = c.walkSpeed;
    if (this.flying) speed = this.sprinting ? c.flySprintSpeed : c.flySpeed;
    else if (this.inLava) speed = c.lavaSpeed;
    else if (this.inWater) speed = c.waterSpeed;
    else if (this.sneaking) speed = c.sneakSpeed;
    else if (this.sprinting) speed = c.sprintSpeed;

    let f = input.forward, s = input.strafe;
    const len = Math.hypot(f, s);
    if (len > 1) { f /= len; s /= len; }
    const sin = Math.sin(this.yaw), cos = Math.cos(this.yaw);
    const wishX = (-sin * f + cos * s) * speed;
    const wishZ = (-cos * f - sin * s) * speed;

    let accel = c.airAccel;
    if (this.flying) accel = c.flyAccel;
    else if (this.inWater || this.inLava) accel = c.waterAccel;
    else if (this.onGround) accel = this.onIce ? c.iceAccel : c.groundAccel;
    const k = Math.min(1, accel * dt);
    this.vx += (wishX - this.vx) * k;
    this.vz += (wishZ - this.vz) * k;

    // Vertical motion.
    if (this.flying) {
      const target = ((input.jump ? 1 : 0) - (input.sneak ? 1 : 0)) * c.flyVerticalSpeed;
      this.vy += (target - this.vy) * Math.min(1, 10 * dt);
    } else if (this.inWater || this.inLava) {
      const g = this.inLava ? c.lavaGravity : c.waterGravity;
      const drag = this.inLava ? c.lavaDrag : c.waterDrag;
      this.vy += (-g - drag * this.vy) * dt;
      if (input.jump) {
        this.vy += (this.inLava ? c.lavaSwimAccel : c.swimAccel) * dt;
        if (this.horizontalCollision) this.vy = Math.max(this.vy, c.waterExitBoost);
      }
    } else {
      if (this.onGround && input.jump) this._jump();
      else if (this.onGround && opts.autoJump && moving && this.horizontalCollision && this._canAutoJump(world, wishX, wishZ)) this._jump();
      this.vy -= c.gravity * dt;
      this.vy *= Math.exp(-c.airDrag * dt);
      if (this.vy < -c.terminalVelocity) this.vy = -c.terminalVelocity;
    }

    let dx = this.vx * dt, dy = this.vy * dt, dz = this.vz * dt;
    if (this.sneaking && this.onGround) [dx, dz] = this._clampToEdge(world, dx, dz);

    const box = this.box();
    const r = moveBox(this.colliders, world, box, dx, dy, dz, this.onGround ? c.stepHeight : 0, this.onGround);
    const wasOnGround = this.onGround;
    this.x = (box.minX + box.maxX) / 2;
    this.y = box.minY;
    this.z = (box.minZ + box.maxZ) / 2;
    this.horizontalCollision = r.hitX || r.hitZ;
    if (r.hitX) this.vx = 0;
    if (r.hitZ) this.vz = 0;
    if (r.hitY) this.vy = 0;
    this.onGround = r.onGround || (r.hitY && dy < 0);

    // Fall tracking.
    this.landedFallDistance = 0;
    if (this.flying || this.inWater || this.inLava) this.fallStartY = null;
    else if (!this.onGround) {
      if (this.fallStartY === null || this.y > this.fallStartY) this.fallStartY = Math.max(this.fallStartY ?? -Infinity, this.y);
    } else if (!wasOnGround || this.fallStartY !== null) {
      if (this.fallStartY !== null) this.landedFallDistance = Math.max(0, this.fallStartY - this.y);
      this.fallStartY = null;
    }
    if (this.onGround && this.flying) this.flying = false;

    const moved = Math.hypot(r.dx, r.dz);
    this.distanceWalked += moved;
    if (this.onGround) this.stepDistance += moved;

    const targetEye = this.sneaking ? c.sneakEyeHeight : c.eyeHeight;
    this.eyeOffset += (targetEye - this.eyeOffset) * Math.min(1, dt * 12);
    return r;
  }

  _jump() {
    this.vy = this.cfg.jumpVelocity;
    this.onGround = false;
    this.jumpedThisFrame = true;
    if (this.sprinting) {
      this.vx += -Math.sin(this.yaw) * this.cfg.sprintJumpBoost;
      this.vz += -Math.cos(this.yaw) * this.cfg.sprintJumpBoost;
    }
  }

  /** A one-block step is in front, with room above it to stand. */
  _canAutoJump(world, wishX, wishZ) {
    const len = Math.hypot(wishX, wishZ);
    if (len < 0.01) return false;
    const p = this.cfg.autoJumpProbe;
    const ox = (wishX / len) * p, oz = (wishZ / len) * p;
    const ahead = this.box().offset(ox, 0, oz);
    if (!this.colliders.collides(world, ahead)) return false;
    const raised = this.box().offset(ox, 1.05, oz);
    return !this.colliders.collides(world, raised);
  }

  /** Shrinks horizontal movement so a sneaking player never walks off an edge. */
  _clampToEdge(world, dx, dz) {
    const probe = this.cfg.sneakEdgeProbe;
    const grounded = (ox, oz) => this.colliders.collides(world, this.box().offset(ox, -probe, oz));
    const step = 0.05;
    while (dx !== 0 && !grounded(dx, 0)) dx = Math.abs(dx) < step ? 0 : dx - Math.sign(dx) * step;
    while (dz !== 0 && !grounded(0, dz)) dz = Math.abs(dz) < step ? 0 : dz - Math.sign(dz) * step;
    while (dx !== 0 && dz !== 0 && !grounded(dx, dz)) {
      dx = Math.abs(dx) < step ? 0 : dx - Math.sign(dx) * step;
      dz = Math.abs(dz) < step ? 0 : dz - Math.sign(dz) * step;
    }
    return [dx, dz];
  }
}
