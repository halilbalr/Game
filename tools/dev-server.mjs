/**
 * Development server: bundles src/main.js on the fly with esbuild and serves
 * src/ at http://localhost:8080 (override with PORT).
 */
import * as esbuild from 'esbuild';

const port = Number(process.env.PORT ?? 8080);
const ctx = await esbuild.context({
  entryPoints: { game: 'src/main.js' },
  bundle: true,
  format: 'esm',
  sourcemap: true,
  target: 'es2022',
  outdir: 'src',
  logLevel: 'info',
});
const { hosts } = await ctx.serve({ servedir: 'src', port, host: '0.0.0.0' });
console.log(`Blockheim dev server: http://localhost:${port}/ (${hosts.join(', ')})`);
