# ADR-0001: Ship Blockheim as a Three.js web game

## Status

Proposed

## Date

2026-10-04

## Last Verified

2026-10-04

## Decision Makers

User (request: "a mobile game that plays like Minecraft"), implemented by Claude Code.

## Summary

The project template expects Godot, Unity or Unreal, but none was installed or configured and the request was for a mobile game that can be played immediately. Blockheim is built as a browser game (JavaScript ES modules + Three.js r186, bundled by esbuild into one HTML file) that runs on any phone browser and installs as a PWA.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Web: Three.js 0.186.1 (WebGL2), esbuild 0.28 |
| **Domain** | Core / Rendering / Input |
| **Layer** | Foundation |
| **Knowledge Risk** | LOW — Three.js core APIs used (BufferGeometry, ShaderMaterial, DataTexture) are long-stable |
| **References Consulted** | three.js docs for ShaderMaterial GLSL compatibility and color management |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Frame rate on a mid-range Android phone and on iOS Safari at render distance 4 |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None |
| **Enables** | All gameplay systems in `src/` |
| **Blocks** | None |
| **Ordering Note** | `project.yaml` keeps `engine.name` unset because the template's engine-specific skills (gdUnit4, Unity test runner) do not apply; tests run with `node --test`. |

## Context

- No game engine was installed in the build environment, so a Godot/Unity/Unreal project could not be built, run or screenshot-verified here.
- "Mobile game" must be playable on the user's phone without store review; a URL is the shortest path.
- The template's coding standards (data-driven values, dependency injection, tests, retained screenshots) are engine-agnostic and still apply.

## Decision

- Code lives in `src/` as ES modules; `src/main.js` is the only composition root and every system receives its dependencies explicitly.
- All gameplay values live in `src/data/*.json`. Textures, sprites, mob skins, icons and sounds are generated at runtime from data and code, so the build ships no binary art.
- Pure logic (world generation, lighting, liquids, meshing, physics, crafting, survival, storage) has no DOM or WebGL dependency and is covered by `node --test` suites in `tests/`.
- `npm run build` emits a single self-contained `dist/index.html` plus PWA manifest, service worker and icons; `npm run evidence` drives the build in headless Chromium and writes screenshots to `production/qa/evidence/`.

## Alternatives Considered

- **Godot 4 with Android export**: best long-term engine fit for the template, but needs the editor, export templates and the Android SDK, and produces an APK that must be side-loaded. Not verifiable in this environment.
- **Unity**: heavier toolchain and license setup for the same result.
- **Capacitor/Cordova wrapper now**: possible later on top of this web build if a store release is wanted.

## Consequences

- Positive: instant play on any device, one artifact to deploy (GitHub Pages or any static host), fast unit tests.
- Negative: single-threaded meshing/generation (time-budgeted per frame); WebGL draw calls scale with visible chunk sections, so render distance defaults to 4 on touch devices.
- The engine-specific template skills (`/setup-engine`, gdUnit4 CI commands) do not apply until/unless the project is ported.
