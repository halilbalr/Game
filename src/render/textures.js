/**
 * Procedural texture atlas. Every block texture is painted at startup from the
 * small recipes in data/textures.json and every item/plant sprite from the
 * pixel grids in data/sprites.json - no image files are shipped, and all art
 * is original to this project.
 *
 * Painting works on plain RGBA byte buffers so it runs (and is tested) without
 * a DOM. Pixels with alpha 254 are a "tint mask": the shader multiplies them by
 * the biome grass/foliage colour.
 */
import { mulberry32, seedFromString } from '../core/random.js';

export const TINT_ALPHA = 254;
const CRACK_STAGES = 10;

/** A square RGBA pixel buffer. */
export class Tile {
  constructor(size) {
    this.size = size;
    this.data = new Uint8ClampedArray(size * size * 4);
  }
  set(x, y, rgb, a = 255) {
    if (x < 0 || y < 0 || x >= this.size || y >= this.size) return;
    const i = (y * this.size + x) * 4;
    this.data[i] = rgb[0]; this.data[i + 1] = rgb[1]; this.data[i + 2] = rgb[2]; this.data[i + 3] = a;
  }
  get(x, y) {
    const i = (y * this.size + x) * 4;
    return [this.data[i], this.data[i + 1], this.data[i + 2], this.data[i + 3]];
  }
  alpha(x, y) { return this.data[(y * this.size + x) * 4 + 3]; }
  copy() {
    const t = new Tile(this.size);
    t.data.set(this.data);
    return t;
  }
}

/** '#rrggbb' -> [r, g, b] */
export function hex(c) {
  const v = parseInt(c.slice(1), 16);
  return [(v >> 16) & 255, (v >> 8) & 255, v & 255];
}

function scale(rgb, f) {
  return [rgb[0] * f, rgb[1] * f, rgb[2] * f];
}

function mix(a, b, t) {
  return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
}

function vary(rgb, rand, amount) {
  return scale(rgb, 1 + (rand() * 2 - 1) * amount);
}

/** Smooth random field on a tiling grid, for organic blobs (lava, ice). */
function valueNoise(rand, size, cells) {
  const g = [];
  for (let i = 0; i < cells * cells; i++) g.push(rand());
  const at = (x, y) => g[((y % cells + cells) % cells) * cells + ((x % cells + cells) % cells)];
  return (x, y) => {
    const fx = (x / size) * cells, fy = (y / size) * cells;
    const x0 = Math.floor(fx), y0 = Math.floor(fy);
    const tx = fx - x0, ty = fy - y0;
    const sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty);
    const a = at(x0, y0) + (at(x0 + 1, y0) - at(x0, y0)) * sx;
    const b = at(x0, y0 + 1) + (at(x0 + 1, y0 + 1) - at(x0, y0 + 1)) * sx;
    return a + (b - a) * sy;
  };
}

/* ------------------------------------------------------------------ painters */

const PAINTERS = {
  noise(t, s, rand) {
    const base = hex(s.base);
    const spots = (s.spots ?? []).map(([c, p]) => [hex(c), p]);
    const a = s.tint ? TINT_ALPHA : 255;
    for (let y = 0; y < t.size; y++) {
      for (let x = 0; x < t.size; x++) {
        let c = vary(base, rand, s.var ?? 0.1);
        for (const [sc, p] of spots) if (rand() < p) { c = vary(sc, rand, 0.05); break; }
        t.set(x, y, c, a);
      }
    }
    if (s.streaks) {
      const sc = hex(s.streaks);
      for (let k = 0; k < 4; k++) {
        const y = Math.floor(rand() * t.size), x0 = Math.floor(rand() * t.size);
        const len = 2 + Math.floor(rand() * 4);
        for (let i = 0; i < len; i++) t.set((x0 + i) % t.size, y, vary(sc, rand, 0.04), a);
      }
    }
  },

  grass_side(t, s, rand, ctx) {
    ctx.blit(t, s.under);
    const band = hex(s.band);
    const a = s.tint ? TINT_ALPHA : 255;
    for (let x = 0; x < t.size; x++) {
      let depth = 3 + (rand() < 0.5 ? 1 : 0) + (rand() < 0.25 ? 1 : 0);
      if (rand() < 0.12) depth += 2;
      for (let y = 0; y < depth; y++) t.set(x, y, vary(band, rand, 0.12), a);
    }
  },

  cobble(t, s, rand) {
    const base = hex(s.base), mortar = hex(s.mortar);
    const moss = s.moss ? hex(s.moss) : null;
    const pts = [];
    for (let i = 0; i < s.cells; i++) pts.push([rand() * t.size, rand() * t.size, 0.82 + rand() * 0.3]);
    const N = t.size;
    for (let y = 0; y < N; y++) {
      for (let x = 0; x < N; x++) {
        let d1 = 1e9, d2 = 1e9, best = 0;
        for (let i = 0; i < pts.length; i++) {
          for (let oy = -1; oy <= 1; oy++) for (let ox = -1; ox <= 1; ox++) {
            const dx = x + 0.5 - (pts[i][0] + ox * N), dy = y + 0.5 - (pts[i][1] + oy * N);
            const d = Math.sqrt(dx * dx + dy * dy);
            if (d < d1) { d2 = d1; d1 = d; best = i; } else if (d < d2) d2 = d;
          }
        }
        let c;
        if (d2 - d1 < 1.1) c = vary(mortar, rand, 0.08);
        else c = vary(scale(base, pts[best][2] + (d2 - d1 > 3 ? 0.06 : 0)), rand, 0.07);
        if (moss && rand() < 0.35 * (1 - y / N) + 0.08) c = vary(moss, rand, 0.15);
        t.set(x, y, c);
      }
    }
  },

  planks(t, s, rand) {
    const base = hex(s.base), dark = hex(s.dark);
    const N = t.size;
    for (let row = 0; row < 4; row++) {
      const seam = Math.floor(rand() * N);
      const tone = 0.92 + rand() * 0.14;
      for (let y = row * 4; y < row * 4 + 4; y++) {
        const grain = rand() < 0.4 ? 0.93 : 1;
        for (let x = 0; x < N; x++) {
          let c = vary(scale(base, tone * grain), rand, 0.05);
          if (y === row * 4 + 3 || x === seam) c = vary(dark, rand, 0.06);
          t.set(x, y, c);
        }
      }
    }
  },

  bark(t, s, rand) {
    const base = hex(s.base), dark = hex(s.dark);
    const N = t.size;
    const cols = [];
    for (let x = 0; x < N; x++) cols.push(rand() < 0.3 ? dark : scale(base, 0.9 + rand() * 0.2));
    for (let y = 0; y < N; y++) {
      for (let x = 0; x < N; x++) {
        let c = vary(cols[x], rand, 0.08);
        if (rand() < 0.05) c = vary(dark, rand, 0.1);
        t.set(x, y, c);
      }
    }
  },

  birch_bark(t, s, rand) {
    const base = hex(s.base), mark = hex(s.mark);
    const N = t.size;
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) t.set(x, y, vary(base, rand, 0.04));
    for (let k = 0; k < 9; k++) {
      const y = Math.floor(rand() * N), x0 = Math.floor(rand() * N), len = 1 + Math.floor(rand() * 4);
      for (let i = 0; i < len; i++) t.set((x0 + i) % N, y, vary(mark, rand, 0.2));
    }
  },

  rings(t, s, rand) {
    const bark = hex(s.bark), inner = hex(s.inner), ring = hex(s.ring);
    const N = t.size, c0 = (N - 1) / 2;
    for (let y = 0; y < N; y++) {
      for (let x = 0; x < N; x++) {
        let c;
        if (x === 0 || y === 0 || x === N - 1 || y === N - 1) c = vary(bark, rand, 0.08);
        else {
          const d = Math.max(Math.abs(x - c0), Math.abs(y - c0));
          c = Math.floor(d) % 2 === 0 ? vary(ring, rand, 0.05) : vary(inner, rand, 0.05);
        }
        t.set(x, y, c);
      }
    }
  },

  leaves(t, s, rand) {
    const base = hex(s.base);
    const a = s.tint ? TINT_ALPHA : 255;
    const N = t.size;
    for (let y = 0; y < N; y++) {
      for (let x = 0; x < N; x++) {
        if (rand() < s.holes) { t.set(x, y, [0, 0, 0], 0); continue; }
        const f = rand() < 0.25 ? 0.72 : (rand() < 0.2 ? 1.15 : 1);
        t.set(x, y, vary(scale(base, f), rand, 0.1), a);
      }
    }
  },

  glass(t, s, rand) {
    const frame = hex(s.frame), streak = hex(s.streak);
    const N = t.size;
    for (let y = 0; y < N; y++) {
      for (let x = 0; x < N; x++) {
        if (x === 0 || y === 0 || x === N - 1 || y === N - 1) t.set(x, y, vary(frame, rand, 0.05));
        else t.set(x, y, [0, 0, 0], 0);
      }
    }
    for (const [x, y] of [[3, 4], [4, 3], [5, 2], [3, 5], [10, 12], [11, 11], [12, 10], [13, 9]]) {
      t.set(Math.round(x * N / 16), Math.round(y * N / 16), streak);
    }
  },

  ore(t, s, rand, ctx) {
    ctx.blit(t, s.under);
    const spot = hex(s.spot), light = hex(s.light);
    const N = t.size;
    const clusters = 4 + Math.floor(rand() * 3);
    for (let k = 0; k < clusters; k++) {
      let x = 2 + Math.floor(rand() * (N - 4)), y = 2 + Math.floor(rand() * (N - 4));
      const n = 2 + Math.floor(rand() * 3);
      for (let i = 0; i < n; i++) {
        t.set(x, y, i === 0 ? light : vary(spot, rand, 0.1));
        if (rand() < 0.5) x += rand() < 0.5 ? 1 : -1; else y += rand() < 0.5 ? 1 : -1;
      }
    }
  },

  pebbles(t, s, rand) {
    const colors = s.colors.map(hex);
    const N = t.size;
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) t.set(x, y, vary(colors[0], rand, 0.08));
    for (let k = 0; k < 26; k++) {
      const c = colors[Math.floor(rand() * colors.length)];
      const x = Math.floor(rand() * N), y = Math.floor(rand() * N);
      const w = 1 + Math.floor(rand() * 2), h = 1 + Math.floor(rand() * 2);
      for (let dy = 0; dy < h; dy++) for (let dx = 0; dx < w; dx++) t.set((x + dx) % N, (y + dy) % N, vary(c, rand, 0.05));
    }
  },

  sandstone(t, s, rand) {
    const base = hex(s.base), dark = hex(s.dark), light = hex(s.light);
    const N = t.size;
    for (let y = 0; y < N; y++) {
      for (let x = 0; x < N; x++) {
        let c = vary(base, rand, 0.04);
        if (y < 3) c = vary(light, rand, 0.04);
        else if (y === 3 || y === 11) c = vary(dark, rand, 0.05);
        else if (y > 12) c = vary(mix(base, dark, 0.5), rand, 0.04);
        t.set(x, y, c);
      }
    }
  },

  water(t, s, rand) {
    const base = hex(s.base), light = hex(s.light);
    const a = Math.round(s.alpha * 255);
    const N = t.size;
    const field = valueNoise(rand, N, 4);
    for (let y = 0; y < N; y++) {
      for (let x = 0; x < N; x++) {
        const v = field(x, y);
        t.set(x, y, vary(v > 0.62 ? light : base, rand, 0.04), a);
      }
    }
  },

  lava(t, s, rand) {
    const dark = hex(s.dark), mid = hex(s.mid), light = hex(s.light);
    const N = t.size;
    const field = valueNoise(rand, N, 4);
    for (let y = 0; y < N; y++) {
      for (let x = 0; x < N; x++) {
        const v = field(x, y);
        const c = v < 0.4 ? dark : v < 0.75 ? mid : light;
        t.set(x, y, vary(c, rand, 0.06));
      }
    }
  },

  ice(t, s, rand) {
    const base = hex(s.base), light = hex(s.light);
    const a = Math.round(s.alpha * 255);
    const N = t.size;
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) t.set(x, y, vary(base, rand, 0.03), a);
    for (let k = 0; k < 5; k++) {
      let x = Math.floor(rand() * N), y = Math.floor(rand() * N);
      for (let i = 0; i < 5; i++) { t.set(x, y, light, a); x = (x + 1) % N; y = (y + N - 1) % N; }
    }
  },

  cactus_side(t, s, rand) {
    const base = hex(s.base), light = hex(s.light), dark = hex(s.dark), thorn = hex(s.thorn);
    const N = t.size;
    for (let y = 0; y < N; y++) {
      for (let x = 0; x < N; x++) {
        const m = x % 4;
        const c = m === 1 ? light : m === 3 ? dark : base;
        t.set(x, y, vary(c, rand, 0.05));
      }
    }
    for (let k = 0; k < 8; k++) t.set(1 + 4 * Math.floor(rand() * 4), Math.floor(rand() * N), thorn);
  },

  crafting_top(t, s, rand, ctx) {
    ctx.blit(t, s.under);
    const line = hex(s.line);
    const N = t.size;
    for (let i = 0; i < N; i++) {
      for (const k of [0, N - 1, Math.round(N / 3), Math.round(2 * N / 3)]) {
        t.set(i, k, vary(line, rand, 0.06));
        t.set(k, i, vary(line, rand, 0.06));
      }
    }
  },

  frame(t, s, rand, ctx) {
    ctx.blit(t, s.under);
    const edge = hex(s.edge);
    const N = t.size;
    for (let i = 0; i < N; i++) {
      for (const k of [0, N - 1]) { t.set(i, k, vary(edge, rand, 0.06)); t.set(k, i, vary(edge, rand, 0.06)); }
      for (let b = 1; b < (s.band ?? 0); b++) t.set(i, b, vary(edge, rand, 0.1));
    }
    if (s.overlay) ctx.overlay(t, s.overlay, 0, s.overlayY ?? 0);
  },

  chest_side(t, s, rand, ctx) {
    ctx.blit(t, s.under);
    const edge = hex(s.edge);
    const N = t.size;
    for (let i = 0; i < N; i++) {
      for (const k of [0, N - 1]) { t.set(i, k, vary(edge, rand, 0.06)); t.set(k, i, vary(edge, rand, 0.06)); }
      t.set(i, s.seam, vary(edge, rand, 0.06));
    }
    if (s.overlay) ctx.overlay(t, s.overlay, 0, s.overlayY ?? 0);
  },

  bricks(t, s, rand) {
    const base = hex(s.base), mortar = hex(s.mortar);
    const N = t.size;
    for (let y = 0; y < N; y++) {
      const row = Math.floor(y / 4);
      const offset = (row % 2) * 4;
      const tone = 0.9 + ((row * 7) % 5) * 0.04;
      for (let x = 0; x < N; x++) {
        const isMortar = y % 4 === 3 || (x + offset) % 8 === 0;
        t.set(x, y, isMortar ? vary(mortar, rand, 0.05) : vary(scale(base, tone), rand, 0.08));
      }
    }
  },

  stone_bricks(t, s, rand) {
    const base = hex(s.base), seam = hex(s.seam), light = hex(s.light);
    const N = t.size;
    for (let y = 0; y < N; y++) {
      for (let x = 0; x < N; x++) {
        const top = y < 8;
        const seamX = top ? (x === 15) : (x === 7);
        let c;
        if (y === 7 || y === 15 || seamX) c = vary(seam, rand, 0.05);
        else if (y === 0 || y === 8 || (top ? x === 0 : x === 8)) c = vary(light, rand, 0.04);
        else c = vary(base, rand, 0.07);
        t.set(x, y, c);
      }
    }
  },

  glowstone(t, s, rand) {
    const base = hex(s.base), mid = hex(s.mid), light = hex(s.light);
    const N = t.size;
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) t.set(x, y, vary(base, rand, 0.1));
    for (let k = 0; k < 14; k++) {
      const x = Math.floor(rand() * (N - 2)), y = Math.floor(rand() * (N - 2));
      const c = rand() < 0.4 ? light : mid;
      t.set(x, y, c); t.set(x + 1, y, c); t.set(x, y + 1, c); t.set(x + 1, y + 1, vary(c, rand, 0.15));
    }
  },

  farmland(t, s, rand) {
    const base = hex(s.base), light = hex(s.light);
    const N = t.size;
    for (let y = 0; y < N; y++) {
      for (let x = 0; x < N; x++) t.set(x, y, vary(y % 4 < 2 ? light : base, rand, 0.1));
    }
  },

  wool(t, s, rand) {
    const base = hex(s.base);
    const N = t.size;
    for (let y = 0; y < N; y++) {
      for (let x = 0; x < N; x++) {
        const f = ((x + y * 2) % 5 === 0) ? 0.9 : 1;
        t.set(x, y, vary(scale(base, f), rand, 0.06));
      }
    }
  },

  bookshelf(t, s, rand, ctx) {
    ctx.blit(t, s.under);
    const colors = s.colors.map(hex);
    const N = t.size;
    for (const [y0, y1] of [[2, 6], [9, 13]]) {
      let x = 1;
      while (x < N - 1) {
        const w = 1 + Math.floor(rand() * 2);
        const c = colors[Math.floor(rand() * colors.length)];
        const top = y0 + Math.floor(rand() * 2);
        for (let y = top; y <= y1; y++) for (let i = 0; i < w && x + i < N - 1; i++) {
          t.set(x + i, y, vary(y === top ? scale(c, 1.25) : c, rand, 0.05));
        }
        x += w + (rand() < 0.2 ? 1 : 0);
      }
    }
  },

  metal(t, s, rand) {
    const base = hex(s.base), light = hex(s.light), dark = hex(s.dark);
    const N = t.size;
    for (let y = 0; y < N; y++) {
      for (let x = 0; x < N; x++) {
        let c = vary(base, rand, 0.03);
        if (x === 0 || y === 0) c = light;
        else if (x === N - 1 || y === N - 1) c = dark;
        else if (x === 1 || y === 1) c = mix(base, light, 0.5);
        else if ((x + y) % 7 === 0) c = mix(base, light, 0.35);
        t.set(x, y, c);
      }
    }
  },

  pumpkin_side(t, s, rand) {
    const base = hex(s.base), dark = hex(s.dark), light = hex(s.light);
    const N = t.size;
    for (let y = 0; y < N; y++) {
      for (let x = 0; x < N; x++) {
        const rib = x % 4 === 0 ? dark : x % 4 === 2 ? light : base;
        t.set(x, y, vary(rib, rand, 0.05));
      }
    }
  },

  pumpkin_top(t, s, rand) {
    const base = hex(s.base), dark = hex(s.dark), stem = hex(s.stem);
    const N = t.size, c0 = (N - 1) / 2;
    for (let y = 0; y < N; y++) {
      for (let x = 0; x < N; x++) {
        const d = Math.hypot(x - c0, y - c0);
        let c = Math.floor(d) % 3 === 0 ? dark : base;
        if (d < 1.6) c = stem;
        t.set(x, y, vary(c, rand, 0.05));
      }
    }
  },

  bed_top(t, s, rand) {
    const sheet = hex(s.sheet), pillow = hex(s.pillow);
    const N = t.size;
    for (let y = 0; y < N; y++) {
      for (let x = 0; x < N; x++) {
        let c = vary(sheet, rand, 0.05);
        if (s.head && y >= 1 && y <= 6 && x >= 2 && x <= N - 3) c = vary(pillow, rand, 0.03);
        if (!s.head && y >= N - 3) c = vary(scale(sheet, 0.8), rand, 0.05);
        if (x === 0 || x === N - 1) c = vary(scale(sheet, 0.85), rand, 0.05);
        t.set(x, y, c);
      }
    }
  },

  bed_side(t, s, rand) {
    const sheet = hex(s.sheet), pillow = hex(s.pillow), wood = hex(s.wood);
    const N = t.size;
    for (let y = 0; y < N; y++) {
      for (let x = 0; x < N; x++) {
        if (y < 7) { t.set(x, y, [0, 0, 0], 0); continue; }
        let c;
        if (y <= 9) c = vary(s.head && x < 6 ? pillow : sheet, rand, 0.05);
        else if (y <= 12) c = vary(wood, rand, 0.08);
        else if (x <= 2 || x >= N - 3) c = vary(scale(wood, 0.8), rand, 0.08);
        else { t.set(x, y, [0, 0, 0], 0); continue; }
        t.set(x, y, c);
      }
    }
  },
};

/* --------------------------------------------------------------- atlas */

function paintSprite(t, sprite, palette) {
  const scaleF = t.size / sprite.rows.length;
  for (let y = 0; y < t.size; y++) {
    for (let x = 0; x < t.size; x++) {
      const ch = sprite.rows[Math.floor(y / scaleF)][Math.floor(x / scaleF)];
      if (ch === '.') { t.set(x, y, [0, 0, 0], 0); continue; }
      const col = palette[ch];
      if (!col) throw new Error(`sprite colour "${ch}" missing`);
      if (col[0] === 't') t.set(x, y, hex(col.slice(1)), TINT_ALPHA);
      else t.set(x, y, hex(col));
    }
  }
}

function paintCrack(t, stage, size) {
  const rand = mulberry32(0xc7ac);
  const walks = [];
  for (let k = 0; k < 7; k++) {
    let x = size / 2 + (rand() - 0.5) * 3, y = size / 2 + (rand() - 0.5) * 3;
    const ang = rand() * Math.PI * 2;
    const pts = [];
    for (let i = 0; i < size; i++) {
      x += Math.cos(ang) + (rand() - 0.5) * 0.9;
      y += Math.sin(ang) + (rand() - 0.5) * 0.9;
      pts.push([Math.floor(x), Math.floor(y)]);
    }
    walks.push(pts);
  }
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) t.set(x, y, [0, 0, 0], 0);
  const frac = (stage + 1) / CRACK_STAGES;
  for (const pts of walks) {
    const n = Math.ceil(pts.length * frac * 0.75);
    for (let i = 0; i < n; i++) t.set(pts[i][0], pts[i][1], [20, 20, 20], 210);
  }
}

/**
 * Lists every atlas entry needed by the registries: block faces, crop stages,
 * item sprites (tools keyed by "sprite:palette") and crack overlays.
 * @param {import('../world/registry.js').BlockRegistry} blocks
 * @param {import('../world/registry.js').ItemRegistry} items
 */
export function collectTextureNames(blocks, items) {
  const names = new Set(blocks.allTextureNames());
  for (const item of items.byId.values()) if (item.sprite) names.add(itemSpriteKey(item));
  for (let i = 0; i < CRACK_STAGES; i++) names.add(`crack_${i}`);
  return [...names];
}

/** Atlas key for an item's sprite. */
export function itemSpriteKey(item) {
  return item.palette ? `${item.sprite}:${item.palette}` : item.sprite;
}

/**
 * Paints the atlas.
 * @param {string[]} names texture names to include
 * @param {object} texData parsed textures.json
 * @param {object} spriteData parsed sprites.json
 * @returns {{size:number, tileSize:number, tilesPerRow:number, data:Uint8ClampedArray, tiles:Map<string,number>, tile:(name:string)=>number, tileImage:(name:string)=>Tile}}
 */
export function buildAtlas(names, texData, spriteData) {
  const tileSize = texData.tileSize;
  const perRow = texData.atlasTiles;
  if (names.length > perRow * perRow) throw new Error(`Atlas overflow: ${names.length} textures`);
  const size = tileSize * perRow;
  const data = new Uint8ClampedArray(size * size * 4);
  const tiles = new Map();
  const images = new Map();

  const paint = (name) => {
    if (images.has(name)) return images.get(name);
    const t = new Tile(tileSize);
    const rand = mulberry32(seedFromString(name));
    const spec = texData.textures[name];
    if (spec) {
      const painter = PAINTERS[spec.p];
      if (!painter) throw new Error(`Unknown painter "${spec.p}" for ${name}`);
      painter(t, spec, rand, ctx);
    } else if (name.startsWith('crack_')) {
      paintCrack(t, Number(name.slice(6)), tileSize);
    } else {
      const [spriteName, paletteName] = name.split(':');
      const sprite = spriteData.sprites[spriteName];
      if (!sprite) throw new Error(`No texture or sprite named "${name}"`);
      const palette = { ...sprite.palette, ...(paletteName ? spriteData.toolPalettes[paletteName] : {}) };
      paintSprite(t, sprite, palette);
    }
    images.set(name, t);
    return t;
  };
  const ctx = {
    blit(target, name) { target.data.set(paint(name).data); },
    overlay(target, name, dx, dy) {
      const sprite = spriteData.sprites[name];
      const o = new Tile(tileSize);
      paintSprite(o, sprite, sprite.palette);
      for (let y = 0; y < tileSize; y++) {
        for (let x = 0; x < tileSize; x++) {
          const p = o.get(x, y);
          if (p[3] > 0) target.set(x + dx, y + dy, p, p[3]);
        }
      }
    },
  };

  names.forEach((name, index) => {
    const t = paint(name);
    tiles.set(name, index);
    const ox = (index % perRow) * tileSize, oy = Math.floor(index / perRow) * tileSize;
    for (let y = 0; y < tileSize; y++) {
      const src = y * tileSize * 4;
      data.set(t.data.subarray(src, src + tileSize * 4), ((oy + y) * size + ox) * 4);
    }
  });

  return {
    size, tileSize, tilesPerRow: perRow, data, tiles,
    tile(name) {
      const i = tiles.get(name);
      if (i === undefined) throw new Error(`Texture "${name}" not in atlas`);
      return i;
    },
    tileImage(name) { return paint(name); },
  };
}
