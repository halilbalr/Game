/**
 * First-person view model: the held block/item (or bare arm) drawn in its own
 * scene on top of the world, with walk bobbing, swing and equip animations.
 */
import * as THREE from 'three';
import { createBlockMaterial } from './materials.js';

export class HandRenderer {
  /**
   * @param {import('./renderer.js').GameRenderer} renderer
   * @param {import('./itemmodel.js').ItemModels} itemModels
   * @param {object} cfg "hand" section of data/ui.json
   */
  constructor(renderer, itemModels, cfg) {
    this.r = renderer;
    this.itemModels = itemModels;
    this.cfg = cfg;
    this.root = new THREE.Group();
    renderer.handScene.add(this.root);
    this.material = createBlockMaterial(renderer.uniforms, 'entity');
    this.mesh = null;
    const armGeo = new THREE.BoxGeometry(0.22, 0.22, 0.8);
    this.armMaterial = new THREE.MeshBasicMaterial({ color: new THREE.Color(cfg.skin) });
    this.arm = new THREE.Mesh(armGeo, this.armMaterial);
    this.root.add(this.arm);
    this.itemId = -1;
    this.equip = 1;
    this.swing = 0;
    this.swinging = false;
  }

  /** Changes the held item (null for empty hand). */
  setItem(id) {
    const next = id ?? -1;
    if (next === this.itemId) return;
    this.itemId = next;
    this.equip = 0;
    if (this.mesh) { this.root.remove(this.mesh); this.mesh = null; }
    this.arm.visible = next < 0;
    if (next >= 0) {
      this.mesh = new THREE.Mesh(this.itemModels.geometry(next), this.material);
      this.root.add(this.mesh);
    }
  }

  /** Starts a swing animation (break, place, attack). */
  doSwing() {
    if (!this.swinging || this.swing > 0.5) { this.swing = 0; this.swinging = true; }
  }

  /**
   * @param {number} dt
   * @param {{bob:number, bobAmount:number, sky:number, block:number, visible:boolean}} s
   */
  update(dt, s) {
    this.root.visible = s.visible;
    if (!s.visible) return;
    this.equip = Math.min(1, this.equip + dt * 5);
    if (this.swinging) {
      this.swing += dt * 3.2;
      if (this.swing >= 1) { this.swing = 0; this.swinging = false; }
    }
    const sw = Math.sin(this.swing * Math.PI);
    const sw2 = Math.sin(Math.sqrt(this.swing) * Math.PI);
    const bobX = Math.sin(s.bob) * 0.03 * s.bobAmount;
    const bobY = -Math.abs(Math.cos(s.bob)) * 0.035 * s.bobAmount;
    const drop = (1 - this.equip) * 0.6;
    this.material.uniforms.uEntityLight.value.set(s.sky / 15, s.block / 15, 1);
    const b = Math.max((s.sky / 15) * this.r.daylight, s.block / 15, 0.08);
    this.armMaterial.color.set(this.cfg.skin).multiplyScalar(b / (2 - b) + 0.15);

    if (this.mesh) {
      const cube = this.itemModels.isCube(this.itemId);
      const c = cube ? this.cfg.block : this.cfg.item;
      this.mesh.scale.setScalar(c.scale);
      this.mesh.position.set(c.pos[0] + bobX - sw2 * 0.25, c.pos[1] + bobY - drop + sw * 0.18, c.pos[2] - sw * 0.25);
      this.mesh.rotation.set(c.rot[0] * Math.PI / 180 - sw * 0.9, c.rot[1] * Math.PI / 180 + sw2 * 0.4, c.rot[2] * Math.PI / 180);
    } else {
      const a = this.cfg.arm;
      this.arm.position.set(a.pos[0] + bobX - sw2 * 0.2, a.pos[1] + bobY - drop + sw * 0.15, a.pos[2] - sw * 0.25);
      this.arm.rotation.set(a.rot[0] * Math.PI / 180 - sw * 0.8, a.rot[1] * Math.PI / 180 + sw2 * 0.3, a.rot[2] * Math.PI / 180);
    }
  }
}
