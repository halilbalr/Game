/**
 * Composition root: loads data, builds every subsystem with explicit
 * dependencies, and runs the frame loop. No other module reaches for globals.
 */
import blocksJson from './data/blocks.json' with { type: 'json' };
import itemsJson from './data/items.json' with { type: 'json' };
import recipesJson from './data/recipes.json' with { type: 'json' };
import smeltingJson from './data/smelting.json' with { type: 'json' };
import worldgenJson from './data/worldgen.json' with { type: 'json' };
import gameJson from './data/game.json' with { type: 'json' };
import playerJson from './data/player.json' with { type: 'json' };
import mobsJson from './data/mobs.json' with { type: 'json' };
import texturesJson from './data/textures.json' with { type: 'json' };
import spritesJson from './data/sprites.json' with { type: 'json' };
import uiJson from './data/ui.json' with { type: 'json' };
import stringsJson from './data/strings.json' with { type: 'json' };

import { createRegistries } from './world/registry.js';
import { buildAtlas, collectTextureNames } from './render/textures.js';
import { GameRenderer } from './render/renderer.js';
import { ItemModels } from './render/itemmodel.js';
import { MobModels } from './render/models.js';
import { EntityRenderer } from './render/entityRenderer.js';
import { HandRenderer } from './render/hand.js';
import { CraftingSystem } from './game/crafting.js';
import { FurnaceLogic } from './game/smelting.js';
import { WorldStorage } from './game/storage.js';
import { Game } from './game/game.js';
import { SoundSystem } from './audio/sound.js';
import { Controls } from './input/controls.js';
import { I18n } from './ui/i18n.js';
import { IconRenderer } from './ui/icons.js';
import { UI } from './ui/ui.js';

const SETTINGS_KEY = 'blockheim.settings.v1';

function isTouchDevice() {
  return navigator.maxTouchPoints > 0 || 'ontouchstart' in window;
}

function loadSettings(data) {
  const touch = isTouchDevice();
  const defaults = {
    renderDistance: touch ? 4 : 6,
    sensitivity: 1,
    fov: data.game.render.fov,
    volume: 0.8,
    music: 0.5,
    autoJump: true,
    clouds: true,
    showFps: false,
    invertY: false,
    touchControls: 'auto',
    resolution: touch ? 0.8 : 1,
    language: I18n.detect(data.strings),
  };
  try {
    const saved = JSON.parse(localStorage.getItem(SETTINGS_KEY) ?? 'null');
    return { ...defaults, ...(saved ?? {}) };
  } catch {
    return defaults;
  }
}

async function boot() {
  const data = {
    blocks: blocksJson, items: itemsJson, recipes: recipesJson, smelting: smeltingJson,
    worldgen: worldgenJson, game: gameJson, player: playerJson, mobs: mobsJson,
    textures: texturesJson, sprites: spritesJson, ui: uiJson, strings: stringsJson,
  };
  const registries = createRegistries(data.blocks, data.items);
  const { blocks, items } = registries;
  const atlas = buildAtlas(collectTextureNames(blocks, items), data.textures, data.sprites);
  blocks.bindAtlas((n) => atlas.tile(n));
  const settings = loadSettings(data);
  const i18n = new I18n(data.strings, settings.language);
  document.documentElement.lang = i18n.lang;

  const canvas = document.getElementById('game');
  const renderer = new GameRenderer({ canvas, blocks, atlas, config: data.game });
  const grassTint = data.textures.defaultGrassTint, foliageTint = data.textures.defaultFoliageTint;
  const itemModels = new ItemModels(blocks, items, atlas, grassTint, foliageTint);
  const mobModels = new MobModels(data.mobs);
  const hand = new HandRenderer(renderer, itemModels, data.ui.hand);
  const icons = new IconRenderer({ blocks, items, atlas, itemModels, grassTint, foliageTint });
  const crafting = new CraftingSystem(data.recipes, items);
  const furnaceLogic = new FurnaceLogic(data.smelting, items);
  const storage = await WorldStorage.create();
  const sound = new SoundSystem(settings);
  const controls = new Controls({ layer: document.getElementById('touch-layer'), canvas, settings, cfg: data.ui.controls });

  let game = null;
  const entityRenderer = new EntityRenderer(renderer, itemModels, mobModels, null);

  const resize = () => {
    renderer.resize(window.innerWidth, window.innerHeight, data.game.render.maxPixelRatio * settings.resolution);
    renderer.baseFov = settings.fov;
  };
  window.addEventListener('resize', resize);
  resize();

  const saveSettings = () => {
    try { localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings)); } catch { /* storage unavailable */ }
  };

  const app = {
    storage,
    async startWorld(meta) {
      sound.unlock();
      if (isTouchDevice()) {
        try {
          await document.documentElement.requestFullscreen?.({ navigationUI: 'hide' });
          await screen.orientation?.lock?.('landscape');
        } catch { /* optional */ }
      }
      ui.showLoading(meta.player ? 'loading.loading' : 'loading.generating');
      entityRenderer.clear();
      game = new Game({
        data, registries, crafting, furnaceLogic, storage, settings, sound, ui,
        view: { renderer, entityRenderer, hand },
      });
      game.controlsTouch = controls.touchMode;
      ui.game = game;
      await game.open(meta, (f) => ui.setLoading(f));
      entityRenderer.world = game.world;
      entityRenderer.particles.world = game.world;
      // Wait until the chunks around the player have meshes.
      const t0 = performance.now();
      while (performance.now() - t0 < 8000) {
        renderer.updateChunks(game.world, game.player.x, game.player.z, 2, 50);
        if (game.world.dirtyChunks.size === 0 || [...game.world.dirtyChunks].every((k) => {
          const c = game.world.chunks.get(k);
          return !c || Math.max(Math.abs(c.cx - (Math.floor(game.player.x) >> 4)), Math.abs(c.cz - (Math.floor(game.player.z) >> 4))) > 2;
        })) break;
        await new Promise((r) => setTimeout(r, 0));
      }
      await game.save();
      ui.show(null, null);
      controls.setEnabled(true);
      controls.requestPointerLock();
      ui.toast(i18n.t('msg.welcome', { name: meta.name }), 3);
      setTimeout(() => ui.toast(i18n.t(controls.touchMode ? 'msg.tip.touch' : 'msg.tip.desktop'), 5), 3200);
      if (game.creative && controls.touchMode) setTimeout(() => ui.toast(i18n.t('msg.flyHint'), 3), 8500);
    },
    pause() {
      if (!game || ui.blocking) return;
      game.paused = true;
      controls.setEnabled(false);
      controls.exitPointerLock();
      ui.showPause();
    },
    resume() {
      if (!game) return;
      game.paused = false;
      ui.show(null, null);
      controls.setEnabled(true);
      controls.requestPointerLock();
    },
    async quitToTitle() {
      if (game) {
        controls.setEnabled(false);
        ui.showLoading('loading.loading');
        await game.close();
        entityRenderer.clear();
        hand.setItem(null);
        game = null;
        ui.game = null;
      }
      ui.showTitle();
    },
    respawn() {
      game.respawn();
      ui.show(null, null);
      controls.setEnabled(true);
      controls.requestPointerLock();
    },
    onSettingsChanged() {
      sound.applyVolume();
      resize();
      i18n.setLanguage(settings.language);
      document.documentElement.lang = i18n.lang;
      const touch = settings.touchControls === 'on' || (settings.touchControls !== 'off' && isTouchDevice());
      controls.touchMode = touch;
      controls.layer.classList.toggle('touch-on', touch);
      if (game) game.controlsTouch = touch;
      ui.hud.classList.toggle('touch', touch);
    },
    saveSettings,
    onScreenChanged(name) {
      if (game) {
        const inGame = name === null;
        controls.setEnabled(inGame && !game.survival.dead);
        if (!inGame) controls.exitPointerLock();
      }
    },
  };

  const ui = new UI({
    root: document.getElementById('screens'), hud: document.getElementById('hud'), i18n, icons, app, data,
    settings, sound, registries, crafting, furnaceLogic,
  });
  ui.hud.classList.toggle('touch', controls.touchMode);
  document.body.classList.add('ready');

  // Menus use the dirt texture as background, like a classic title screen.
  const dirt = atlas.tileImage('dirt');
  const dc = document.createElement('canvas');
  dc.width = dc.height = dirt.size;
  const dctx = dc.getContext('2d');
  const img = dctx.createImageData(dirt.size, dirt.size);
  img.data.set(dirt.data);
  dctx.putImageData(img, 0, 0);
  document.documentElement.style.setProperty('--dirt', `url(${dc.toDataURL()})`);

  const unlockAudio = () => sound.unlock();
  window.addEventListener('pointerdown', unlockAudio, { once: true });
  window.addEventListener('keydown', unlockAudio, { once: true });

  document.addEventListener('visibilitychange', () => {
    if (document.hidden && game?.running) {
      app.pause();
      game.save().catch((err) => console.error(err));
    }
  });
  window.addEventListener('pagehide', () => { game?.save(); });

  ui.showTitle();

  let last = performance.now();
  let fpsFrames = 0, fpsTime = 0, fps = 0;
  const holdMs = data.game.interaction.holdToBreakMs;
  const frame = (now) => {
    requestAnimationFrame(frame);
    const dt = Math.min(0.25, (now - last) / 1000);
    last = now;
    fpsFrames++; fpsTime += dt;
    if (fpsTime >= 1) { fps = Math.round(fpsFrames / fpsTime); fpsFrames = 0; fpsTime = 0; }
    if (!game || !game.running) return;

    const input = controls.sample(holdMs);
    if (controls.took('inventory')) {
      if (ui.inv.kind) ui.inv.close();
      else if (!ui.blocking && !game.survival.dead) { ui.inv.open('inventory'); }
    }
    if (controls.took('pause')) {
      if (ui.inv.kind) ui.inv.close();
      else if (ui.screenName === 'pause') app.resume();
      else if (!ui.blocking) app.pause();
    }
    if (controls.took('debug')) settings.showFps = !settings.showFps;
    if (controls.took('hideHud')) game.hideHud = !game.hideHud;
    if (!controls.enabled) {
      input.forward = 0; input.strafe = 0; input.jump = false; input.breakHeld = false; input.useHeld = false;
      input.lookX = 0; input.lookY = 0; input.wheel = 0;
      controls.pressed.clear();
    }

    game.frame(dt, input, controls);
    controls.setFlying(game.player.flying);
    const p = game.player;
    renderer.updateChunks(game.world, p.x, p.z, settings.renderDistance, data.game.render.meshBudgetMs);
    entityRenderer.sync(game.entities, dt, now / 1000, renderer.daylight);

    const eye = p.eye();
    const bobAmount = p.onGround && !p.flying ? Math.min(1, Math.hypot(p.vx, p.vz) / 4) : 0;
    const bob = p.distanceWalked * 1.9;
    const view = {
      eye: { x: eye.x + Math.sin(bob) * 0.03 * bobAmount, y: eye.y - Math.abs(Math.cos(bob)) * 0.04 * bobAmount, z: eye.z },
      yaw: p.yaw, pitch: p.pitch, roll: game.hurtTilt * 0.12 * Math.sin(now / 40),
      timeOfDay: game.timeOfDay, renderDistance: settings.renderDistance,
      submerged: p.eyeIn, dt, fovScale: p.sprinting ? 1.12 : (p.flying ? 1.05 : 1), clouds: settings.clouds,
    };
    view.eye = Object.assign(eye, view.eye);
    hand.setItem(game.heldStack ? game.heldStack.id : null);
    const sky = game.world.getSkyLight(Math.floor(p.x), Math.floor(eye.y), Math.floor(p.z));
    const blk = game.world.getBlockLight(Math.floor(p.x), Math.floor(eye.y), Math.floor(p.z));
    hand.update(dt, { bob, bobAmount, sky, block: blk, visible: !game.survival.dead && !game.hideHud });
    renderer.render(view);
    ui.updateHud(game, dt, fps);
    ui.inv.update();
    sound.listener.x = eye.x; sound.listener.y = eye.y; sound.listener.z = eye.z; sound.listener.yaw = p.yaw;
    sound.updateMusic(dt);
  };
  requestAnimationFrame(frame);

  // Exposed for automated smoke tests and debugging.
  window.blockheim = { app, get game() { return game; }, renderer, settings, ui };
}

boot().catch((err) => {
  console.error(err);
  const el = document.getElementById('boot-error');
  if (el) { el.textContent = `Startfel / Startup error: ${err.message}`; el.style.display = 'block'; }
});
