/**
 * Synthesised sound effects and generative ambient music (WebAudio). Every
 * sound is built from oscillators and filtered noise at runtime, so the game
 * ships no audio files and all sounds are original.
 */

const MATERIALS = {
  stone: { type: 'bandpass', freq: 1500, q: 1.2, dur: 0.12, gain: 0.5 },
  wood: { type: 'bandpass', freq: 650, q: 3.5, dur: 0.12, gain: 0.6, tone: 180 },
  grass: { type: 'highpass', freq: 2200, q: 0.7, dur: 0.14, gain: 0.35 },
  gravel: { type: 'bandpass', freq: 900, q: 0.8, dur: 0.16, gain: 0.55, crunch: 3 },
  sand: { type: 'highpass', freq: 2800, q: 0.5, dur: 0.15, gain: 0.3 },
  snow: { type: 'highpass', freq: 1800, q: 0.5, dur: 0.14, gain: 0.3 },
  cloth: { type: 'lowpass', freq: 700, q: 0.6, dur: 0.12, gain: 0.4 },
  glass: { type: 'bandpass', freq: 3200, q: 6, dur: 0.1, gain: 0.35, ping: true },
  metal: { type: 'bandpass', freq: 2400, q: 8, dur: 0.18, gain: 0.35, tone: 880 },
};

export class SoundSystem {
  /** @param {{volume:number, music:number}} settings */
  constructor(settings) {
    this.settings = settings;
    this.ctx = null;
    this.listener = { x: 0, y: 0, z: 0, yaw: 0 };
    this._musicTimer = 20;
  }

  /** Must be called from a user gesture (browsers block autoplay). */
  unlock() {
    if (!this.ctx) {
      const AC = globalThis.AudioContext || globalThis.webkitAudioContext;
      if (!AC) return;
      this.ctx = new AC();
      this.master = this.ctx.createGain();
      this.master.connect(this.ctx.destination);
      this.musicBus = this.ctx.createGain();
      this.musicBus.connect(this.master);
      const len = this.ctx.sampleRate;
      this.noise = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
      const d = this.noise.getChannelData(0);
      for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    }
    if (this.ctx.state === 'suspended') this.ctx.resume();
    this.applyVolume();
  }

  applyVolume() {
    if (!this.ctx) return;
    this.master.gain.value = this.settings.volume;
    this.musicBus.gain.value = this.settings.music;
  }

  _out(x, y, z) {
    const ctx = this.ctx;
    const g = ctx.createGain();
    if (x === undefined) { g.connect(this.master); return g; }
    const dx = x - this.listener.x, dy = y - this.listener.y, dz = z - this.listener.z;
    const dist = Math.hypot(dx, dy, dz);
    const vol = Math.max(0, 1 - dist / 20);
    if (vol <= 0) return null;
    const pan = ctx.createStereoPanner ? ctx.createStereoPanner() : null;
    const out = ctx.createGain();
    out.gain.value = vol;
    g.connect(out);
    if (pan) {
      const ang = Math.atan2(dx, -dz) - (-this.listener.yaw);
      pan.pan.value = Math.max(-1, Math.min(1, Math.sin(-ang) * -0.8));
      out.connect(pan); pan.connect(this.master);
    } else out.connect(this.master);
    return g;
  }

  _noise(dest, t, dur, { type, freq, q, gain }, rate = 1) {
    const ctx = this.ctx;
    const src = ctx.createBufferSource();
    src.buffer = this.noise;
    src.playbackRate.value = rate;
    const f = ctx.createBiquadFilter();
    f.type = type; f.frequency.value = freq; f.Q.value = q;
    const g = ctx.createGain();
    g.gain.setValueAtTime(gain, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    src.connect(f); f.connect(g); g.connect(dest);
    src.start(t, Math.random() * 0.5, dur + 0.05);
  }

  _tone(dest, t, dur, freq, endFreq, type = 'sine', gain = 0.3, attack = 0.005) {
    const ctx = this.ctx;
    const o = ctx.createOscillator();
    o.type = type;
    o.frequency.setValueAtTime(freq, t);
    if (endFreq) o.frequency.exponentialRampToValueAtTime(endFreq, t + dur);
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(gain, t + attack);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g); g.connect(dest);
    o.start(t); o.stop(t + dur + 0.05);
    return o;
  }

  /**
   * Plays a named sound, optionally positioned in the world.
   * @param {string} name e.g. "break_stone", "step_grass", "hurt", "pig_say"
   */
  play(name, x, y, z, volume = 1) {
    if (!this.ctx || this.ctx.state !== 'running' || this.settings.volume <= 0) return;
    const out = this._out(x, y, z);
    if (!out) return;
    out.gain.value = volume;
    const t = this.ctx.currentTime;
    const [kind, mat] = name.split('_');
    const m = MATERIALS[mat];
    if (m && (kind === 'break' || kind === 'dig' || kind === 'step' || kind === 'place')) {
      const scale = kind === 'step' ? 0.35 : kind === 'dig' ? 0.45 : kind === 'place' ? 0.7 : 1;
      const dur = m.dur * (kind === 'break' ? 1.6 : 1);
      const rate = 0.8 + Math.random() * 0.4;
      this._noise(out, t, dur, { ...m, gain: m.gain * scale }, rate);
      if (m.crunch) for (let i = 1; i < m.crunch; i++) this._noise(out, t + i * 0.03, dur * 0.6, { ...m, gain: m.gain * scale * 0.6 }, rate);
      if (m.tone && kind !== 'step') this._tone(out, t, dur, m.tone * rate, m.tone * rate * 0.7, 'triangle', 0.12 * scale);
      if (m.ping && kind === 'break') for (let i = 0; i < 4; i++) this._tone(out, t + i * 0.02, 0.25, 2000 + Math.random() * 2500, null, 'sine', 0.06);
      return;
    }
    switch (name) {
      case 'hurt':
        this._tone(out, t, 0.18, 320, 140, 'sawtooth', 0.12);
        this._noise(out, t, 0.08, { type: 'lowpass', freq: 800, q: 1, gain: 0.3 });
        break;
      case 'pop':
        this._tone(out, t, 0.08, 500 + Math.random() * 300, 1300, 'sine', 0.18);
        break;
      case 'click':
        this._tone(out, t, 0.05, 900, 600, 'square', 0.05);
        break;
      case 'eat':
        for (let i = 0; i < 3; i++) this._noise(out, t + i * 0.12, 0.07, { type: 'bandpass', freq: 1400, q: 2, gain: 0.35 }, 0.9 + Math.random() * 0.3);
        break;
      case 'burp':
        this._tone(out, t, 0.3, 140, 90, 'triangle', 0.15);
        break;
      case 'splash':
        this._noise(out, t, 0.45, { type: 'bandpass', freq: 1100, q: 0.8, gain: 0.5 });
        break;
      case 'explode':
        this._noise(out, t, 1.4, { type: 'lowpass', freq: 500, q: 0.7, gain: 1.0 }, 0.6);
        this._tone(out, t, 0.6, 90, 35, 'sine', 0.6);
        break;
      case 'fuse':
        this._noise(out, t, 1.4, { type: 'highpass', freq: 3500, q: 0.6, gain: 0.25 });
        break;
      case 'levelup':
        [523, 659, 784].forEach((f, i) => this._tone(out, t + i * 0.08, 0.25, f, null, 'triangle', 0.12));
        break;
      case 'pig_say': case 'pig_hurt':
        for (let i = 0; i < 2; i++) this._tone(out, t + i * 0.13, 0.1, 260 + Math.random() * 40, 190, 'square', name.endsWith('hurt') ? 0.08 : 0.05);
        break;
      case 'cow_say': case 'cow_hurt': {
        const o = this._tone(out, t, name.endsWith('hurt') ? 0.4 : 0.9, 125, 95, 'sawtooth', 0.09, 0.08);
        const lfo = this.ctx.createOscillator(); const lg = this.ctx.createGain();
        lfo.frequency.value = 5; lg.gain.value = 6; lfo.connect(lg); lg.connect(o.frequency); lfo.start(t); lfo.stop(t + 1);
        break;
      }
      case 'sheep_say': case 'sheep_hurt': {
        const o = this._tone(out, t, 0.55, 420, 380, 'sawtooth', 0.05, 0.03);
        const lfo = this.ctx.createOscillator(); const lg = this.ctx.createGain();
        lfo.frequency.value = 28; lg.gain.value = 25; lfo.connect(lg); lg.connect(o.frequency); lfo.start(t); lfo.stop(t + 0.6);
        break;
      }
      case 'chicken_say': case 'chicken_hurt':
        for (let i = 0; i < 2; i++) this._tone(out, t + i * 0.09, 0.06, 1300 + Math.random() * 600, 1000, 'triangle', 0.06);
        break;
      case 'zombie_say': case 'zombie_hurt':
        this._tone(out, t, 0.9, 110, 75, 'sawtooth', 0.07, 0.15);
        this._noise(out, t, 0.6, { type: 'lowpass', freq: 400, q: 1, gain: 0.12 });
        break;
      case 'blastling_say': case 'blastling_hurt':
        this._noise(out, t, 0.25, { type: 'bandpass', freq: 2600, q: 2, gain: 0.15 });
        break;
      default:
        break;
    }
  }

  /** Occasional quiet generative melody (pentatonic, slow attack). */
  updateMusic(dt) {
    if (!this.ctx || this.ctx.state !== 'running' || this.settings.music <= 0) return;
    this._musicTimer -= dt;
    if (this._musicTimer > 0) return;
    this._musicTimer = 50 + Math.random() * 70;
    const scale = [261.6, 293.7, 329.6, 392.0, 440.0, 523.3, 587.3, 659.3];
    const t0 = this.ctx.currentTime + 0.1;
    let t = t0;
    const notes = 6 + Math.floor(Math.random() * 7);
    let idx = Math.floor(Math.random() * scale.length);
    for (let i = 0; i < notes; i++) {
      idx = Math.max(0, Math.min(scale.length - 1, idx + Math.floor(Math.random() * 5) - 2));
      const f = scale[idx] * (Math.random() < 0.2 ? 0.5 : 1);
      const dur = 1.6 + Math.random() * 1.4;
      this._tone(this.musicBus, t, dur, f, null, 'sine', 0.06, 0.04);
      this._tone(this.musicBus, t, dur * 0.7, f * 2, null, 'triangle', 0.015, 0.04);
      if (Math.random() < 0.3) this._tone(this.musicBus, t, dur * 1.5, f / 2, null, 'sine', 0.03, 0.2);
      t += 0.5 + Math.random() * 0.9;
    }
  }
}
