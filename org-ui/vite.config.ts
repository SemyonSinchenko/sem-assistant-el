import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Served by Apache under /ui/ on the WebDAV origin (see webdav/apache).
// `npm run dev` proxies WebDAV requests to DAV_TARGET for local work.
const davTarget = process.env.DAV_TARGET;

export default defineConfig({
  base: '/ui/',
  plugins: [react()],
  build: { outDir: 'dist', emptyOutDir: true, sourcemap: false, chunkSizeWarningLimit: 900 },
  server: davTarget
    ? {
        proxy: {
          '^/(?!ui/|@|node_modules/|src/).*': { target: davTarget, changeOrigin: true, secure: false },
        },
      }
    : undefined,
  test: { environment: 'node', include: ['src/**/*.test.ts'] },
});
