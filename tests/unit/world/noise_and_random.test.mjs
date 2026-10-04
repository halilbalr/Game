import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SimplexNoise } from '../../../src/core/noise.js';
import { mulberry32, seedFromString, hash3 } from '../../../src/core/random.js';

test('seedFromString maps numeric strings to themselves and text deterministically', () => {
  assert.equal(seedFromString('12345'), 12345);
  assert.equal(seedFromString('hello'), seedFromString('hello'));
  assert.notEqual(seedFromString('hello'), seedFromString('hellp'));
});

test('mulberry32 is deterministic and in [0, 1)', () => {
  const a = mulberry32(42), b = mulberry32(42);
  for (let i = 0; i < 1000; i++) {
    const v = a();
    assert.equal(v, b());
    assert.ok(v >= 0 && v < 1);
  }
});

test('hash3 differs per coordinate', () => {
  assert.notEqual(hash3(1, 0, 0, 0), hash3(1, 1, 0, 0));
  assert.notEqual(hash3(1, 0, 0, 0), hash3(1, 0, 0, 1));
  assert.equal(hash3(7, -5, 3, 9), hash3(7, -5, 3, 9));
});

test('simplex noise is seeded, bounded and continuous', () => {
  const n1 = new SimplexNoise(5), n2 = new SimplexNoise(5), n3 = new SimplexNoise(6);
  let diff = 0;
  for (let i = 0; i < 500; i++) {
    const x = i * 0.37, z = i * 0.11;
    const v = n1.noise2(x, z);
    assert.equal(v, n2.noise2(x, z));
    assert.ok(v >= -1.01 && v <= 1.01);
    const w = n1.noise3(x, z, x - z);
    assert.ok(w >= -1.01 && w <= 1.01);
    diff += Math.abs(v - n3.noise2(x, z));
    // small step -> small change
    assert.ok(Math.abs(n1.noise2(x + 0.001, z) - v) < 0.05);
  }
  assert.ok(diff > 1, 'different seeds should give different noise');
});
