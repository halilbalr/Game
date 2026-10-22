// PROTOTYPE - NOT FOR PRODUCTION
// Question: Är det roligt att kapa skepp med Clash-liknande anfall?
// Date: 2026-10-22
//
// Syntetiserade ljudeffekter och en enkel pentatonisk trumslinga (WebAudio, inga ljudfiler).
(function () {
  const K = window.K;
  const S = (K.sfx = { ctx: null, muted: false, last: {}, master: null, noiseBuf: null, musicOn: false });

  S.init = function () {
    if (S.ctx) { if (S.ctx.state === 'suspended') S.ctx.resume().catch(() => {}); return; }
    try {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return;
      S.ctx = new AC();
      S.master = S.ctx.createGain(); S.master.gain.value = S.muted ? 0 : 0.55; S.master.connect(S.ctx.destination);
      S.musicGain = S.ctx.createGain(); S.musicGain.gain.value = 0.32; S.musicGain.connect(S.master);
      const len = S.ctx.sampleRate * 1;
      S.noiseBuf = S.ctx.createBuffer(1, len, S.ctx.sampleRate);
      const d = S.noiseBuf.getChannelData(0);
      for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    } catch (e) { S.ctx = null; }
  };

  // Vibration på mobiler som stöder det (Android). Följer ljudinställningen.
  S.buzz = function (pattern) {
    if (S.muted || !navigator.vibrate) return;
    const now = performance.now();
    if (now - (S.lastBuzz || 0) < 70) return;
    S.lastBuzz = now;
    try { navigator.vibrate(pattern); } catch (e) { /* stöds inte */ }
  };

  S.setMuted = function (m) {
    S.muted = m;
    if (S.master) S.master.gain.setTargetAtTime(m ? 0 : 0.55, S.ctx.currentTime, 0.05);
  };

  function tone(f, dur, type = 'sine', vol = 0.2, f2 = null, delay = 0, out = null) {
    const c = S.ctx, t = c.currentTime + delay;
    const o = c.createOscillator(), g = c.createGain();
    o.type = type; o.frequency.setValueAtTime(f, t);
    if (f2) o.frequency.exponentialRampToValueAtTime(Math.max(20, f2), t + dur);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(vol, t + 0.008);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g); g.connect(out || S.master);
    o.start(t); o.stop(t + dur + 0.05);
  }
  function noise(dur, vol = 0.3, freq = 1000, ftype = 'lowpass', q = 1, delay = 0, out = null) {
    const c = S.ctx, t = c.currentTime + delay;
    const src = c.createBufferSource(); src.buffer = S.noiseBuf;
    const f = c.createBiquadFilter(); f.type = ftype; f.frequency.value = freq; f.Q.value = q;
    const g = c.createGain();
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    src.connect(f); f.connect(g); g.connect(out || S.master);
    src.start(t, Math.random() * 0.5); src.stop(t + dur + 0.05);
  }

  const GAP = { coin: 0.05, hit: 0.035, shot: 0.04, water: 0.12, deploy: 0.03, hook: 0.05, die: 0.05, ko: 0.05, cannon: 0.05, collapse: 0.08, boom: 0.06, wall: 0.06, thud: 0.06 };

  S.play = function (name) {
    if (!S.ctx || S.muted) return;
    const now = S.ctx.currentTime;
    if (now - (S.last[name] || 0) < (GAP[name] || 0.02)) return;
    S.last[name] = now;
    switch (name) {
      case 'cannon': noise(0.35, 0.45, 900); tone(110, 0.3, 'sine', 0.45, 40); break;
      case 'boom': noise(0.7, 0.6, 500); tone(80, 0.6, 'sine', 0.5, 28); break;
      case 'mortar': tone(220, 0.25, 'sine', 0.3, 70); noise(0.2, 0.25, 700); break;
      case 'shot': noise(0.08, 0.22, 2600, 'bandpass', 0.8); break;
      case 'hit': noise(0.06, 0.18, 1900, 'bandpass', 2); tone(620 + Math.random() * 200, 0.05, 'square', 0.04, 300); break;
      case 'thud': tone(130, 0.16, 'sine', 0.4, 55); noise(0.12, 0.2, 400); break;
      case 'collapse': noise(0.8, 0.45, 650); tone(90, 0.5, 'triangle', 0.25, 40); noise(0.4, 0.2, 2500, 'bandpass', 1, 0.1); break;
      case 'wall': noise(0.25, 0.3, 1300, 'bandpass', 1); tone(300, 0.12, 'square', 0.05, 120); break;
      case 'coin': tone(1320, 0.07, 'triangle', 0.1); tone(1980, 0.09, 'triangle', 0.08, null, 0.05); break;
      case 'deploy': noise(0.14, 0.12, 2400, 'highpass'); tone(320, 0.1, 'sine', 0.08, 640); break;
      case 'hook': noise(0.08, 0.1, 3500, 'highpass'); tone(980, 0.04, 'triangle', 0.06); break;
      case 'die': tone(520, 0.22, 'triangle', 0.12, 180); break;
      case 'ko': tone(420, 0.18, 'square', 0.05, 140); break;
      case 'star': [880, 1108, 1318, 1760].forEach((f, i) => tone(f, 0.18, 'triangle', 0.16, null, i * 0.06)); break;
      case 'capture': [523, 659, 784, 1046, 784, 1046].forEach((f, i) => tone(f, 0.22, 'square', 0.07, null, i * 0.11)); noise(0.6, 0.2, 800, 'lowpass', 1, 0.05); break;
      case 'win': [392, 523, 659, 784, 659, 784, 1046].forEach((f, i) => { tone(f, 0.26, 'square', 0.07, null, i * 0.13); tone(f / 2, 0.26, 'triangle', 0.1, null, i * 0.13); }); break;
      case 'lose': [440, 392, 349, 262].forEach((f, i) => tone(f, 0.34, 'triangle', 0.14, null, i * 0.2)); break;
      case 'click': tone(760, 0.04, 'triangle', 0.12); break;
      case 'error': tone(190, 0.12, 'square', 0.08); tone(150, 0.14, 'square', 0.08, null, 0.08); break;
      case 'heal': [660, 880, 990].forEach((f, i) => tone(f, 0.3, 'sine', 0.12, null, i * 0.08)); break;
      case 'drum': [0, 0.14, 0.28, 0.36].forEach((d, i) => { tone(i % 2 ? 140 : 100, 0.18, 'sine', 0.4, 50, d); noise(0.06, 0.15, 900, 'lowpass', 1, d); }); break;
      case 'roar': noise(0.5, 0.35, 380, 'bandpass', 1.5); tone(160, 0.45, 'sawtooth', 0.08, 90); break;
      case 'alarm': for (let i = 0; i < 4; i++) tone(i % 2 ? 700 : 940, 0.14, 'square', 0.05, null, i * 0.15); break;
      case 'water': noise(0.16, 0.06, 2200, 'highpass'); break;
      case 'upgrade': [523, 784, 1046, 1568].forEach((f, i) => tone(f, 0.2, 'triangle', 0.13, null, i * 0.07)); break;
      case 'train': tone(600, 0.06, 'triangle', 0.1, 900); break;
      case 'splash': noise(0.3, 0.2, 1500, 'lowpass'); break;
    }
  };

  // ---------- musik: pentatonisk slinga med trumma ----------
  const SCALE = [0, 2, 4, 7, 9, 12, 14, 16];
  const MEL = [0, 2, 4, 2, 5, 4, 2, 0, 1, 2, 4, 5, 7, 5, 4, 2, 0, 2, 4, 2, 5, 4, 3, 4, 2, 1, 0, -1, 0, 2, 1, 0];
  let step = 0, nextT = 0, timer = null;
  S.startMusic = function () {
    if (!S.ctx || timer) return;
    S.musicOn = true;
    nextT = S.ctx.currentTime + 0.1;
    timer = setInterval(() => {
      if (!S.ctx) return;
      const spb = 60 / 104 / 2;
      while (nextT < S.ctx.currentTime + 0.25) {
        const d = nextT - S.ctx.currentTime;
        const s = step % 32;
        if (!S.muted) {
          if (s % 8 === 0 || s % 8 === 3 || s % 8 === 6) tone(s % 8 === 0 ? 75 : 95, 0.18, 'sine', 0.5, 45, Math.max(0, d), S.musicGain);
          if (s % 2 === 1) noise(0.04, 0.06, 7000, 'highpass', 1, Math.max(0, d), S.musicGain);
          const m = MEL[s];
          if (m >= 0 && (s % 2 === 0 || s % 4 === 3)) {
            const f = 293.66 * Math.pow(2, SCALE[m] / 12);
            tone(f, 0.22, 'triangle', 0.12, null, Math.max(0, d), S.musicGain);
          }
          if (s % 8 === 0) tone(146.83 * Math.pow(2, SCALE[(s / 8) % 2 ? 3 : 0] / 12), 0.6, 'sine', 0.12, null, Math.max(0, d), S.musicGain);
        }
        nextT += spb; step++;
      }
    }, 90);
  };
})();
