/**
 * Mirrors the entity list into Three.js objects every frame: spinning dropped
 * items, falling blocks, animated mobs and block-break particles.
 */
import * as THREE from 'three';
import { createBlockMaterial } from './materials.js';

/** Same brightness curve as the terrain shader, for MeshBasicMaterial mobs. */
function brightness(sky, block, daylight) {
  const c = (l) => l / (2 - l);
  return Math.max(c((sky / 15) * daylight), c(block / 15), 0.035);
}

export class EntityRenderer {
  /**
   * @param {import('./renderer.js').GameRenderer} renderer
   * @param {import('./itemmodel.js').ItemModels} itemModels
   * @param {import('./models.js').MobModels} mobModels
   * @param {import('../world/world.js').World} world
   */
  constructor(renderer, itemModels, mobModels, world) {
    this.r = renderer;
    this.itemModels = itemModels;
    this.mobModels = mobModels;
    this.world = world;
    this.objects = new Map();
    this.group = renderer.entityGroup;
    this.particles = new ParticleSystem(renderer, world);
  }

  _lightAt(x, y, z) {
    const ix = Math.floor(x), iy = Math.floor(y), iz = Math.floor(z);
    return [this.world.getSkyLight(ix, iy, iz), this.world.getBlockLight(ix, iy, iz)];
  }

  _create(e) {
    if (e.type === 'item' || e.type === 'falling') {
      const id = e.type === 'item' ? e.stack.id : e.blockId;
      const mat = createBlockMaterial(this.r.uniforms, 'entity');
      const mesh = new THREE.Mesh(this.itemModels.geometry(id), mat);
      const cube = this.itemModels.isCube(id);
      const s = e.type === 'falling' ? 0.999 : (cube ? 0.25 : 0.42);
      mesh.scale.setScalar(s);
      const obj = { mesh, mat, cube, count: e.type === 'item' ? e.stack.count : 1 };
      if (e.type === 'item' && e.stack.count > 1) {
        // A second copy hints at a stack of several items.
        const extra = new THREE.Mesh(mesh.geometry, mat);
        extra.position.set(0.25, 0.2, 0.25);
        mesh.add(extra);
      }
      this.group.add(mesh);
      return obj;
    }
    const model = this.mobModels.create(e.kind);
    this.group.add(model.root);
    return { model };
  }

  _dispose(obj) {
    if (obj.mesh) { this.group.remove(obj.mesh); obj.mat.dispose(); }
    if (obj.model) { this.group.remove(obj.model.root); obj.model.material.dispose(); }
  }

  /**
   * @param {import('../entities/entities.js').EntityManager} entities
   * @param {number} dt
   * @param {number} time seconds since start
   * @param {number} daylight
   */
  sync(entities, dt, time, daylight) {
    const alive = new Set();
    for (const e of entities.list) {
      if (e.removed) continue;
      alive.add(e.id);
      let obj = this.objects.get(e.id);
      if (!obj) { obj = this._create(e); this.objects.set(e.id, obj); }
      const visible = this.world.isLoaded(e.x, e.z);
      if (obj.mesh) {
        obj.mesh.visible = visible;
        const [sky, blk] = this._lightAt(e.x, e.y + 0.25, e.z);
        obj.mat.uniforms.uEntityLight.value.set(sky / 15, blk / 15, 1);
        if (e.type === 'item') {
          const bob = Math.sin(time * 2.5 + e.id) * 0.06;
          obj.mesh.position.set(e.x, e.y + (obj.cube ? 0.125 : 0.21) + 0.08 + bob, e.z);
          obj.mesh.rotation.y = e.spin;
        } else {
          obj.mesh.position.set(e.x, e.y + 0.5, e.z);
        }
      } else {
        const m = obj.model;
        m.root.visible = visible;
        m.root.position.set(e.x, e.y, e.z);
        m.root.rotation.y = e.yaw;
        const [sky, blk] = this._lightAt(e.x, e.y + e.height * 0.6, e.z);
        let b = brightness(sky, blk, daylight);
        if (e.burning) b = Math.max(b, 0.9);
        const col = m.material.color;
        if (e.hurtTime > 0 || e.dead) col.setRGB(b * 1.4, b * 0.45, b * 0.45);
        else if (e.burning && Math.sin(time * 30) > 0) col.setRGB(b * 1.3, b * 0.8, b * 0.4);
        else col.setScalar(b);
        if (e.fuse > 0) {
          const flash = Math.sin(e.fuse * 20) > 0;
          if (flash) col.setRGB(1.6, 1.6, 1.6);
          m.body.scale.setScalar(1 + e.fuse * 0.12);
        } else m.body.scale.setScalar(1);
        const swing = Math.sin(e.walkPhase) * 0.9 * e.walkAmount;
        for (const p of m.parts) {
          if (p.def.swing) p.pivot.rotation.x = p.rest.x + swing * p.def.swing;
          if (p.def.flap) p.pivot.rotation.z = (e.onGround ? 0 : Math.sin(time * 25) * 0.8) * p.def.flap;
        }
        if (m.head) m.head.rotation.y = wrap(e.headYaw - e.yaw);
        m.root.rotation.z = e.dead ? Math.min(1, e.deathTime / 0.5) * (Math.PI / 2) : 0;
      }
    }
    for (const [id, obj] of this.objects) {
      if (!alive.has(id)) { this._dispose(obj); this.objects.delete(id); }
    }
    this.particles.update(dt);
  }

  clear() {
    for (const obj of this.objects.values()) this._dispose(obj);
    this.objects.clear();
    this.particles.clear();
  }
}

function wrap(a) {
  while (a > Math.PI) a -= Math.PI * 2;
  while (a < -Math.PI) a += Math.PI * 2;
  return a;
}

/** Camera-facing textured quads for block debris and puffs, in one dynamic mesh. */
class ParticleSystem {
  constructor(renderer, world) {
    this.r = renderer;
    this.world = world;
    this.max = 400;
    this.list = [];
    const g = new THREE.BufferGeometry();
    this.pos = new Float32Array(this.max * 4 * 3);
    this.uv = new Float32Array(this.max * 4 * 2);
    this.light = new Uint8Array(this.max * 4 * 4);
    this.tint = new Uint8Array(this.max * 4 * 4);
    const index = new Uint16Array(this.max * 6);
    for (let i = 0; i < this.max; i++) {
      index.set([i * 4, i * 4 + 1, i * 4 + 2, i * 4, i * 4 + 2, i * 4 + 3], i * 6);
    }
    g.setAttribute('position', new THREE.BufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('uv', new THREE.BufferAttribute(this.uv, 2).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('light', new THREE.BufferAttribute(this.light, 4, true).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('tint', new THREE.BufferAttribute(this.tint, 4, true).setUsage(THREE.DynamicDrawUsage));
    g.setIndex(new THREE.BufferAttribute(index, 1));
    g.setDrawRange(0, 0);
    this.geometry = g;
    this.mesh = new THREE.Mesh(g, createBlockMaterial(renderer.uniforms, 'opaque'));
    this.mesh.frustumCulled = false;
    renderer.scene.add(this.mesh);
  }

  /**
   * Emits debris for a broken block.
   * @param {number} tile atlas tile of the block
   * @param {number[]} tint RGB
   */
  burst(x, y, z, tile, tint, count = 24) {
    const per = this.r.atlas.tilesPerRow;
    const tx = tile % per, ty = Math.floor(tile / per);
    const sky = this.world.getSkyLight(Math.floor(x), Math.floor(y), Math.floor(z));
    const blk = this.world.getBlockLight(Math.floor(x), Math.floor(y), Math.floor(z));
    for (let i = 0; i < count; i++) {
      if (this.list.length >= this.max) this.list.shift();
      const u0 = Math.floor(Math.random() * 12), v0 = Math.floor(Math.random() * 12);
      this.list.push({
        x: x + Math.random(), y: y + Math.random(), z: z + Math.random(),
        vx: (Math.random() - 0.5) * 3, vy: Math.random() * 3 + 1, vz: (Math.random() - 0.5) * 3,
        life: 0.5 + Math.random() * 0.6, size: 0.08 + Math.random() * 0.06,
        u0: (tx + u0 / 16) / per, v0: (ty + v0 / 16) / per, du: 3 / 16 / per,
        sky: sky * 17, blk: Math.max(blk, 0) * 17, tint,
      });
    }
  }

  update(dt) {
    const cam = this.r.camera;
    const right = new THREE.Vector3(1, 0, 0).applyQuaternion(cam.quaternion);
    const up = new THREE.Vector3(0, 1, 0).applyQuaternion(cam.quaternion);
    let n = 0;
    for (const p of this.list) {
      p.life -= dt;
      p.vy -= 18 * dt;
      p.x += p.vx * dt; p.y += p.vy * dt; p.z += p.vz * dt;
      const id = this.world.getBlock(Math.floor(p.x), Math.floor(p.y), Math.floor(p.z));
      if (this.world.blocks.solid[id]) { p.y = Math.floor(p.y) + 1.001; p.vy = 0; p.vx *= 0.5; p.vz *= 0.5; }
    }
    this.list = this.list.filter((p) => p.life > 0);
    for (const p of this.list) {
      const s = p.size;
      const corners = [[-1, -1], [1, -1], [1, 1], [-1, 1]];
      for (let k = 0; k < 4; k++) {
        const [a, b] = corners[k];
        const vi = (n * 4 + k);
        this.pos[vi * 3] = p.x + (right.x * a + up.x * b) * s;
        this.pos[vi * 3 + 1] = p.y + (right.y * a + up.y * b) * s;
        this.pos[vi * 3 + 2] = p.z + (right.z * a + up.z * b) * s;
        this.uv[vi * 2] = p.u0 + (a > 0 ? p.du : 0);
        this.uv[vi * 2 + 1] = p.v0 + (b > 0 ? 0 : p.du);
        this.light[vi * 4] = p.sky; this.light[vi * 4 + 1] = p.blk; this.light[vi * 4 + 2] = 230; this.light[vi * 4 + 3] = 255;
        this.tint[vi * 4] = p.tint[0]; this.tint[vi * 4 + 1] = p.tint[1]; this.tint[vi * 4 + 2] = p.tint[2]; this.tint[vi * 4 + 3] = 255;
      }
      n++;
    }
    for (const name of ['position', 'uv', 'light', 'tint']) this.geometry.attributes[name].needsUpdate = true;
    this.geometry.setDrawRange(0, n * 6);
  }

  clear() { this.list = []; this.geometry.setDrawRange(0, 0); }
}
