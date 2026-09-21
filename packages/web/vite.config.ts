import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// The app always calls relative paths (/api/polls, /api/qa). In dev this proxy
// stands in for the ingress, so no code changes between laptop and cluster.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    // Needed so a phone on the same wifi can reach the dev server.
    host: true,
    proxy: {
      '/api/polls': { target: 'http://127.0.0.1:8001', changeOrigin: true },
      '/api/qa': { target: 'http://127.0.0.1:8002', changeOrigin: true },
    },
  },
  build: {
    outDir: 'dist',
    sourcemap: true,
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/test/setup.ts'],
    css: false,
  },
})
