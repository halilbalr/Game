/**
 * Owns the Three.js renderer, scene and camera, keeps chunk section meshes in
 * sync with the world, and draws the sky, block selection and break cracks.
 */
import * as THREE from 'three';
import { Mesher } from './mesher.js';
import { Sky } from './sky.js';
import { createAtlasTexture, createWorldUniforms, createBlockMaterial, geometryFromMesh } from './materials.js';
import { SECTIONS, RENDER, chunkKey } from '../world/constants.js';

THREE.ColorManagement.enabled = false;

export class GameRenderer {
  /**
   * @param {object} opts
   * @param {HTMLCanvasElement} opts.canvas
   * @param {import('../world/registry.js').BlockRegistry} opts.blocks
   * @param {object} opts.atlas atlas from buildAtlas()
   * @param {object} opts.config parsed game.json
   */
  constructor({ canvas, blocks, atlas, config }) {
    this.blocks = blocks;
    this.atlas = atlas;
    this.cfg = config.render;
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: false, powerPreference: 'high-performance', alpha: false });
    this.renderer.outputColorSpace = THREE.LinearSRGBColorSpace;
    this.renderer.autoClear = false;
    this.renderer.info.autoReset = false;
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(this.cfg.fov, 1, this.cfg.near, this.cfg.far);
    this.camera.rotation.order = 'YXZ';
    this.baseFov = this.cfg.fov;

    this.atlasTexture = createAtlasTexture(atlas);
    this.uniforms = createWorldUniforms(this.atlasTexture);
    this.opaqueMaterial = createBlockMaterial(this.uniforms, 'opaque');
    this.translucentMaterial = createBlockMaterial(this.uniforms, 'translucent');
    this.mesher = new Mesher(blocks, atlas);
    /** @type {Map<number, {cx:number, cz:number, opaque:(THREE.Mesh|null)[], translucent:(THREE.Mesh|null)[]}>} */
    this.chunkMeshes = new Map();
    this.chunkGroup = new THREE.Group();
    this.scene.add(this.chunkGroup);
    this.entityGroup = new THREE.Group();
    this.scene.add(this.entityGroup);
    this.sky = new Sky(this.scene, config.sky);
    this.sectionSphere = new THREE.Sphere(new THREE.Vector3(8, 8, 8), 14);

    // Hand / held item layer.
    this.handScene = new THREE.Scene();
    this.handCamera = new THREE.PerspectiveCamera(70, 1, 0.01, 10);

    this._initSelection();
    this.pixelRatio = 1;
    this.daylight = 1;
    this.stats = { sections: 0, triangles: 0, meshedThisFrame: 0 };
  }

  _initSelection() {
    const edges = new THREE.EdgesGeometry(new THREE.BoxGeometry(1, 1, 1));
    this.selection = new THREE.LineSegments(edges, new THREE.LineBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.55 }));
    this.selection.visible = false;
    this.scene.add(this.selection);
    const crackGeo = new THREE.BoxGeometry(1.004, 1.004, 1.004);
    this.crackMaterial = new THREE.MeshBasicMaterial({
      map: this.atlasTexture, transparent: true, depthWrite: false, polygonOffset: true,
      polygonOffsetFactor: -1, polygonOffsetUnits: -1, opacity: 0.9,
    });
    this.crack = new THREE.Mesh(crackGeo, this.crackMaterial);
    this.crack.visible = false;
    this.crackStage = -1;
    this.scene.add(this.crack);
  }

  /** Resizes the drawing buffer to the canvas' CSS size. */
  resize(width, height, maxPixelRatio) {
    this.pixelRatio = Math.min(window.devicePixelRatio || 1, maxPixelRatio ?? this.cfg.maxPixelRatio);
    this.renderer.setPixelRatio(this.pixelRatio);
    this.renderer.setSize(width, height, false);
    this.camera.aspect = width / height;
    this.camera.updateProjectionMatrix();
    this.handCamera.aspect = width / height;
    this.handCamera.updateProjectionMatrix();
  }

  /**
   * Builds meshes for dirty, meshable chunks near the player within a time budget.
   * @param {import('../world/world.js').World} world
   * @param {number} px player x
   * @param {number} pz player z
   * @param {number} renderDistance in chunks
   * @param {number} budgetMs
   */
  updateChunks(world, px, pz, renderDistance, budgetMs) {
    const pcx = Math.floor(px) >> 4, pcz = Math.floor(pz) >> 4;
    const start = performance.now();
    const candidates = [];
    for (const key of world.dirtyChunks) {
      const c = world.chunks.get(key);
      if (!c) { world.dirtyChunks.delete(key); continue; }
      const dx = c.cx - pcx, dz = c.cz - pcz;
      if (Math.max(Math.abs(dx), Math.abs(dz)) > renderDistance) continue;
      if (!world.isMeshable(c.cx, c.cz)) continue;
      candidates.push([dx * dx + dz * dz, c]);
    }
    candidates.sort((a, b) => a[0] - b[0]);
    let meshed = 0;
    for (const [, c] of candidates) {
      const key = chunkKey(c.cx, c.cz);
      let entry = this.chunkMeshes.get(key);
      if (!entry) {
        entry = { cx: c.cx, cz: c.cz, opaque: new Array(SECTIONS).fill(null), translucent: new Array(SECTIONS).fill(null) };
        this.chunkMeshes.set(key, entry);
      }
      for (let sy = 0; sy < SECTIONS; sy++) {
        if (!(c.dirtyMask & (1 << sy))) continue;
        const { opaque, translucent } = this.mesher.build(world, c, sy);
        this._setSection(entry, 'opaque', sy, opaque, this.opaqueMaterial);
        this._setSection(entry, 'translucent', sy, translucent, this.translucentMaterial);
        c.dirtyMask &= ~(1 << sy);
        meshed++;
        if (performance.now() - start > budgetMs) break;
      }
      if (c.dirtyMask === 0) world.dirtyChunks.delete(key);
      if (performance.now() - start > budgetMs) break;
    }
    this.stats.meshedThisFrame = meshed;
    // Drop meshes of chunks that left the world or the view distance.
    for (const [key, entry] of this.chunkMeshes) {
      const far = Math.max(Math.abs(entry.cx - pcx), Math.abs(entry.cz - pcz)) > renderDistance + 1;
      if (far || !world.chunks.has(key)) {
        this._disposeEntry(entry);
        this.chunkMeshes.delete(key);
        const c = world.chunks.get(key);
        if (c) { c.dirtyMask = (1 << SECTIONS) - 1; world.dirtyChunks.add(key); }
      }
    }
    return meshed;
  }

  _setSection(entry, kind, sy, data, material) {
    const old = entry[kind][sy];
    if (old) {
      this.chunkGroup.remove(old);
      old.geometry.dispose();
      entry[kind][sy] = null;
    }
    if (!data) return;
    const geo = geometryFromMesh(data);
    geo.boundingSphere = this.sectionSphere;
    const mesh = new THREE.Mesh(geo, material);
    mesh.position.set(entry.cx * 16, sy * 16, entry.cz * 16);
    mesh.matrixAutoUpdate = false;
    mesh.updateMatrix();
    if (kind === 'translucent') mesh.renderOrder = 2;
    this.chunkGroup.add(mesh);
    entry[kind][sy] = mesh;
  }

  _disposeEntry(entry) {
    for (const kind of ['opaque', 'translucent']) {
      for (const m of entry[kind]) {
        if (!m) continue;
        this.chunkGroup.remove(m);
        m.geometry.dispose();
      }
    }
  }

  /** Removes every chunk mesh (world unload). */
  clearChunks() {
    for (const entry of this.chunkMeshes.values()) this._disposeEntry(entry);
    this.chunkMeshes.clear();
  }

  /**
   * Shows the selection outline (and crack overlay) on a block.
   * @param {{x:number,y:number,z:number}|null} target
   * @param {number} breakProgress 0..1, or <0 for none
   */
  setSelection(target, breakProgress) {
    if (!target) {
      this.selection.visible = false;
      this.crack.visible = false;
      return;
    }
    const b = this.selectionBounds(target.id);
    this.selection.visible = true;
    this.selection.position.set(target.x + (b[0] + b[3]) / 2, target.y + (b[1] + b[4]) / 2, target.z + (b[2] + b[5]) / 2);
    this.selection.scale.set(b[3] - b[0] + 0.004, b[4] - b[1] + 0.004, b[5] - b[2] + 0.004);
    if (breakProgress >= 0) {
      const stage = Math.min(9, Math.floor(breakProgress * 10));
      if (stage !== this.crackStage) this._setCrackStage(stage);
      this.crack.visible = true;
      this.crack.position.copy(this.selection.position);
      this.crack.scale.copy(this.selection.scale);
    } else {
      this.crack.visible = false;
    }
  }

  /** Selection box of a block in block units [x0,y0,z0,x1,y1,z1]. */
  selectionBounds(id) {
    const B = this.blocks;
    const def = B.defs[id];
    switch (B.render[id]) {
      case RENDER.box: return def.box.map((v) => v / 16);
      case RENDER.cross: case RENDER.crop: return [0.15, 0, 0.15, 0.85, 0.8, 0.85];
      case RENDER.torch: return [0.38, 0, 0.38, 0.62, 0.65, 0.62];
      case RENDER.cactus: return [1 / 16, 0, 1 / 16, 15 / 16, 1, 15 / 16];
      default: return [0, 0, 0, 1, 1, 1];
    }
  }

  _setCrackStage(stage) {
    this.crackStage = stage;
    const tile = this.atlas.tile(`crack_${stage}`);
    const per = this.atlas.tilesPerRow;
    const tx = tile % per, ty = Math.floor(tile / per);
    const uv = this.crack.geometry.attributes.uv;
    for (let i = 0; i < uv.count; i++) {
      const u = uv.getX(i) > 0.5 ? 1 : 0, v = uv.getY(i) > 0.5 ? 1 : 0;
      uv.setXY(i, (tx + u) / per, (ty + 1 - v) / per);
    }
    uv.needsUpdate = true;
  }

  /**
   * Draws a frame.
   * @param {object} view
   * @param {THREE.Vector3} view.eye camera position
   * @param {number} view.yaw
   * @param {number} view.pitch
   * @param {number} view.timeOfDay 0..1
   * @param {number} view.renderDistance chunks
   * @param {string|null} view.submerged 'water' | 'lava' | null
   * @param {number} view.dt seconds
   * @param {number} view.fovScale multiplier (sprinting)
   * @param {boolean} view.clouds
   */
  render(view) {
    const cam = this.camera;
    cam.position.copy(view.eye);
    cam.rotation.set(view.pitch, view.yaw, view.roll ?? 0);
    const targetFov = this.baseFov * (view.fovScale ?? 1);
    if (Math.abs(cam.fov - targetFov) > 0.05) {
      cam.fov += (targetFov - cam.fov) * Math.min(1, view.dt * 10);
      cam.updateProjectionMatrix();
    }
    const sky = this.sky.update(view.timeOfDay, cam.position, view.dt, view.clouds !== false);
    this.daylight = sky.daylight;
    const u = this.uniforms;
    u.uDaylight.value = sky.daylight;
    const far = view.renderDistance * 16;
    if (view.submerged === 'water') {
      u.uFogColor.value.setRGB(...this.cfg.underwaterFog);
      u.uFogNear.value = 0;
      u.uFogFar.value = this.cfg.underwaterFogFar * (0.4 + 0.6 * sky.day);
    } else if (view.submerged === 'lava') {
      u.uFogColor.value.setRGB(...this.cfg.lavaFog);
      u.uFogNear.value = 0;
      u.uFogFar.value = 3;
    } else {
      u.uFogColor.value.copy(sky.fogColor);
      u.uFogNear.value = far * 0.55;
      u.uFogFar.value = far - 2;
    }
    u.uBrightness.value = view.brightness ?? 1;
    this.renderer.setClearColor(u.uFogColor.value, 1);
    this.renderer.info.reset();
    this.renderer.clear();
    this.renderer.render(this.scene, cam);
    if (this.handScene.children.length) {
      this.renderer.clearDepth();
      this.renderer.render(this.handScene, this.handCamera);
    }
    const info = this.renderer.info.render;
    this.stats.triangles = info.triangles;
    this.stats.calls = info.calls;
  }
}
