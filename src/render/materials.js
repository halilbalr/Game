/**
 * Shader materials for terrain and block-shaped entities. Lighting is resolved
 * per fragment from the baked sky/block light levels so day/night changes only
 * update a uniform - no chunk remeshing.
 */
import * as THREE from 'three';

const VERT = /* glsl */ `
attribute vec4 light;
attribute vec4 tint;
varying vec2 vUv;
varying vec3 vLight;
varying vec3 vTint;
varying float vFogDepth;
uniform vec3 uEntityLight;
void main() {
  vUv = uv;
  vLight = uEntityLight.z > 0.5 ? vec3(uEntityLight.xy, light.z) : light.xyz;
  vTint = tint.rgb;
  vec4 mv = modelViewMatrix * vec4(position, 1.0);
  vFogDepth = length(mv.xyz);
  gl_Position = projectionMatrix * mv;
}
`;

const FRAG = /* glsl */ `
uniform sampler2D uAtlas;
uniform float uDaylight;
uniform vec3 uFogColor;
uniform float uFogNear;
uniform float uFogFar;
uniform float uAlphaTest;
uniform float uBrightness;
uniform vec3 uFlash;
varying vec2 vUv;
varying vec3 vLight;
varying vec3 vTint;
varying float vFogDepth;

float curve(float l) { return l / (2.0 - l); }

void main() {
  vec4 tex = texture2D(uAtlas, vUv);
  if (tex.a < uAlphaTest) discard;
  vec3 col = tex.rgb;
  if (tex.a > 0.99 && tex.a < 0.999) { col *= vTint; tex.a = 1.0; }
  float skyB = curve(vLight.x * uDaylight);
  float blockB = curve(vLight.y);
  vec3 skyCol = vec3(skyB) * mix(vec3(0.62, 0.68, 0.95), vec3(1.0), clamp(uDaylight * 1.4 - 0.3, 0.0, 1.0));
  vec3 blockCol = vec3(blockB) * vec3(1.0, 0.9, 0.76);
  vec3 lightCol = max(max(skyCol, blockCol), vec3(0.035)) * uBrightness;
  col *= lightCol * vLight.z;
  col = mix(col, uFlash, step(0.001, dot(uFlash, uFlash)) * 0.45);
  float f = smoothstep(uFogNear, uFogFar, vFogDepth);
  col = mix(col, uFogColor, f);
  gl_FragColor = vec4(col, tex.a);
}
`;

/**
 * Shared uniforms so one update affects every chunk material.
 * @param {THREE.Texture} atlasTexture
 */
export function createWorldUniforms(atlasTexture) {
  return {
    uAtlas: { value: atlasTexture },
    uDaylight: { value: 1 },
    uFogColor: { value: new THREE.Color(0.7, 0.8, 1.0) },
    uFogNear: { value: 40 },
    uFogFar: { value: 64 },
    uBrightness: { value: 1 },
  };
}

/**
 * @param {object} shared uniforms from createWorldUniforms
 * @param {'opaque'|'translucent'|'entity'} kind
 */
export function createBlockMaterial(shared, kind) {
  const uniforms = {
    ...shared,
    uAlphaTest: { value: kind === 'translucent' ? 0.02 : 0.5 },
    uEntityLight: { value: new THREE.Vector3(1, 0, 0) },
    uFlash: { value: new THREE.Color(0, 0, 0) },
  };
  const mat = new THREE.ShaderMaterial({
    uniforms,
    vertexShader: VERT,
    fragmentShader: FRAG,
    transparent: kind === 'translucent',
    depthWrite: kind !== 'translucent',
    side: kind === 'translucent' ? THREE.DoubleSide : THREE.FrontSide,
  });
  if (kind === 'entity') uniforms.uEntityLight.value.set(1, 0, 1);
  return mat;
}

/** Wraps the RGBA atlas buffer as a nearest-filtered texture. */
export function createAtlasTexture(atlas) {
  const tex = new THREE.DataTexture(new Uint8Array(atlas.data.buffer), atlas.size, atlas.size, THREE.RGBAFormat);
  tex.magFilter = THREE.NearestFilter;
  tex.minFilter = THREE.NearestFilter;
  tex.generateMipmaps = false;
  tex.colorSpace = THREE.NoColorSpace;
  tex.needsUpdate = true;
  return tex;
}

/**
 * Builds a BufferGeometry from mesher output.
 * @param {{position: Float32Array, uv: Float32Array, light: Uint8Array, tint: Uint8Array, index: Uint16Array|Uint32Array}} data
 */
export function geometryFromMesh(data) {
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(data.position, 3));
  g.setAttribute('uv', new THREE.BufferAttribute(data.uv, 2));
  g.setAttribute('light', new THREE.BufferAttribute(data.light, 4, true));
  g.setAttribute('tint', new THREE.BufferAttribute(data.tint, 4, true));
  g.setIndex(new THREE.BufferAttribute(data.index, 1));
  return g;
}
