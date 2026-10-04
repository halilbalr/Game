/**
 * Sky dome with day/night colours, a square sun and moon, stars and a slowly
 * drifting blocky cloud layer.
 */
import * as THREE from 'three';
import { mulberry32 } from '../core/random.js';

const SKY_VERT = /* glsl */ `
varying vec3 vDir;
void main() {
  vDir = normalize(position);
  vec4 mv = modelViewMatrix * vec4(position, 1.0);
  gl_Position = projectionMatrix * mv;
}
`;
const SKY_FRAG = /* glsl */ `
uniform vec3 uTop;
uniform vec3 uHorizon;
uniform vec3 uSunDir;
uniform vec3 uGlow;
uniform float uGlowAmount;
varying vec3 vDir;
void main() {
  float h = clamp(vDir.y, -0.2, 1.0);
  vec3 col = mix(uHorizon, uTop, smoothstep(-0.05, 0.45, h));
  float s = max(dot(normalize(vDir), uSunDir), 0.0);
  col += uGlow * uGlowAmount * pow(s, 6.0) * (1.0 - smoothstep(0.0, 0.5, h));
  gl_FragColor = vec4(col, 1.0);
}
`;

function pixelTexture(size, draw) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const ctx = c.getContext('2d');
  draw(ctx, size);
  const t = new THREE.CanvasTexture(c);
  t.magFilter = THREE.NearestFilter;
  t.minFilter = THREE.NearestFilter;
  t.generateMipmaps = false;
  t.colorSpace = THREE.NoColorSpace;
  return t;
}

export class Sky {
  /**
   * @param {THREE.Scene} scene
   * @param {object} cfg sky section of data/game.json
   */
  constructor(scene, cfg) {
    this.cfg = cfg;
    this.group = new THREE.Group();
    scene.add(this.group);
    this.colors = {
      dayTop: new THREE.Color(cfg.dayTop), dayHorizon: new THREE.Color(cfg.dayHorizon),
      nightTop: new THREE.Color(cfg.nightTop), nightHorizon: new THREE.Color(cfg.nightHorizon),
      sunset: new THREE.Color(cfg.sunset),
    };
    this.uniforms = {
      uTop: { value: new THREE.Color() }, uHorizon: { value: new THREE.Color() },
      uSunDir: { value: new THREE.Vector3(0, 1, 0) }, uGlow: { value: this.colors.sunset.clone() },
      uGlowAmount: { value: 0 },
    };
    const dome = new THREE.Mesh(
      new THREE.SphereGeometry(cfg.radius, 24, 12),
      new THREE.ShaderMaterial({
        uniforms: this.uniforms, vertexShader: SKY_VERT, fragmentShader: SKY_FRAG,
        side: THREE.BackSide, depthWrite: false, depthTest: false, fog: false,
      }),
    );
    dome.renderOrder = -10;
    dome.frustumCulled = false;
    this.group.add(dome);

    const sunTex = pixelTexture(16, (ctx) => {
      ctx.fillStyle = '#fff6b0'; ctx.fillRect(2, 2, 12, 12);
      ctx.fillStyle = '#ffffff'; ctx.fillRect(4, 4, 8, 8);
    });
    const moonTex = pixelTexture(16, (ctx) => {
      ctx.fillStyle = '#d8dce8'; ctx.fillRect(3, 3, 10, 10);
      ctx.fillStyle = '#b4b8c8'; ctx.fillRect(5, 5, 2, 2); ctx.fillRect(9, 8, 3, 2); ctx.fillRect(6, 10, 2, 1);
    });
    const quad = (tex, size) => {
      const m = new THREE.Mesh(new THREE.PlaneGeometry(size, size), new THREE.MeshBasicMaterial({
        map: tex, transparent: true, depthWrite: false, depthTest: true, fog: false, blending: THREE.AdditiveBlending,
      }));
      m.renderOrder = -9;
      m.frustumCulled = false;
      this.group.add(m);
      return m;
    };
    this.sun = quad(sunTex, cfg.sunSize);
    this.moon = quad(moonTex, cfg.moonSize);

    const rand = mulberry32(1234);
    const starPos = [];
    for (let i = 0; i < cfg.stars; i++) {
      const u = rand() * 2 - 1, a = rand() * Math.PI * 2, r = Math.sqrt(1 - u * u);
      const v = new THREE.Vector3(r * Math.cos(a), Math.abs(u) * 0.9 + 0.1, r * Math.sin(a)).normalize()
        .multiplyScalar(cfg.radius * 0.9);
      starPos.push(v.x, v.y, v.z);
    }
    const sg = new THREE.BufferGeometry();
    sg.setAttribute('position', new THREE.Float32BufferAttribute(starPos, 3));
    this.starMat = new THREE.PointsMaterial({
      color: 0xffffff, size: 1.6, sizeAttenuation: false, transparent: true, opacity: 0, depthWrite: false, depthTest: true, fog: false,
    });
    this.stars = new THREE.Points(sg, this.starMat);
    this.stars.renderOrder = -9;
    this.stars.frustumCulled = false;
    this.group.add(this.stars);

    // Clouds: a repeating pixel texture on a large plane that follows the camera.
    const cloudTex = pixelTexture(cfg.cloudTexture, (ctx, size) => {
      const r = mulberry32(77);
      const cells = new Uint8Array(size * size);
      for (let i = 0; i < cells.length; i++) cells[i] = r() < 0.42 ? 1 : 0;
      // Two smoothing passes give clumped, blocky clouds.
      for (let pass = 0; pass < 3; pass++) {
        const next = new Uint8Array(cells.length);
        for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
          let n = 0;
          for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
            n += cells[((y + dy + size) % size) * size + ((x + dx + size) % size)];
          }
          next[y * size + x] = n >= 5 ? 1 : 0;
        }
        cells.set(next);
      }
      ctx.clearRect(0, 0, size, size);
      ctx.fillStyle = '#ffffff';
      for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) if (cells[y * size + x]) ctx.fillRect(x, y, 1, 1);
    });
    cloudTex.wrapS = cloudTex.wrapT = THREE.RepeatWrapping;
    const span = cfg.cloudTexture * cfg.cloudCell;
    cloudTex.repeat.set(cfg.cloudSpan / span, cfg.cloudSpan / span);
    this.cloudTex = cloudTex;
    this.cloudMat = new THREE.MeshBasicMaterial({
      map: cloudTex, transparent: true, opacity: cfg.cloudOpacity, depthWrite: false, side: THREE.DoubleSide, fog: false,
    });
    this.clouds = new THREE.Mesh(new THREE.PlaneGeometry(cfg.cloudSpan, cfg.cloudSpan), this.cloudMat);
    this.clouds.rotation.x = -Math.PI / 2;
    this.clouds.renderOrder = 5;
    scene.add(this.clouds);
    this.cloudOffset = 0;
    this.fogColor = new THREE.Color();
  }

  /**
   * @param {number} timeOfDay 0..1 (0 = sunrise, 0.25 = noon, 0.5 = sunset, 0.75 = midnight)
   * @param {THREE.Vector3} cameraPos
   * @param {number} dt seconds
   * @param {boolean} showClouds
   * @returns {{daylight:number, fogColor:THREE.Color}}
   */
  update(timeOfDay, cameraPos, dt, showClouds) {
    const angle = timeOfDay * Math.PI * 2;
    const sunDir = new THREE.Vector3(Math.cos(angle), Math.sin(angle), 0.18).normalize();
    this.uniforms.uSunDir.value.copy(sunDir);
    const sunHeight = sunDir.y;
    const day = THREE.MathUtils.smoothstep(sunHeight, -0.18, 0.22);
    const daylight = this.cfg.minDaylight + (1 - this.cfg.minDaylight) * day;
    const c = this.colors;
    this.uniforms.uTop.value.copy(c.nightTop).lerp(c.dayTop, day);
    this.uniforms.uHorizon.value.copy(c.nightHorizon).lerp(c.dayHorizon, day);
    const glow = Math.max(0, 1 - Math.abs(sunHeight) / 0.35);
    this.uniforms.uGlowAmount.value = glow * 0.9;

    this.group.position.copy(cameraPos);
    const dist = this.cfg.radius * 0.8;
    this.sun.position.copy(sunDir).multiplyScalar(dist);
    this.sun.lookAt(0, 0, 0);
    this.moon.position.copy(sunDir).multiplyScalar(-dist);
    this.moon.lookAt(0, 0, 0);
    this.starMat.opacity = Math.max(0, 1 - day * 1.6) * 0.9;
    this.stars.rotation.z = angle * 0.2;

    this.cloudOffset += dt * this.cfg.cloudSpeed;
    const span = this.cfg.cloudTexture * this.cfg.cloudCell;
    this.clouds.visible = showClouds;
    this.clouds.position.set(cameraPos.x, this.cfg.cloudHeight, cameraPos.z);
    this.cloudTex.offset.set(((cameraPos.x + this.cloudOffset) / span) % 1, (-cameraPos.z / span) % 1);
    this.cloudMat.color.setScalar(0.35 + 0.65 * day);

    // Fog takes the horizon colour, nudged towards the sunset glow when facing it.
    this.fogColor.copy(this.uniforms.uHorizon.value).lerp(c.sunset, glow * 0.25);
    return { daylight, fogColor: this.fogColor, day };
  }
}
