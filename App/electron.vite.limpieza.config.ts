import { resolve } from 'node:path'
import { defineConfig } from 'electron-vite'
import react from '@vitejs/plugin-react'

// «Nitrit0 Limpieza»: segunda aplicación del mismo proyecto. Sale en out-limpieza y comparte la base visual (src/renderer/src/diseno).
export default defineConfig({
  main: { build: { outDir: 'out-limpieza/main', rollupOptions: { input: resolve(__dirname, 'src/limpieza/main/index.ts') } } },
  preload: { build: { outDir: 'out-limpieza/preload', rollupOptions: { input: resolve(__dirname, 'src/limpieza/preload/index.ts') } } },
  renderer: {
    root: resolve(__dirname, 'src/limpieza/renderer'),
    plugins: [react()],
    build: { outDir: resolve(__dirname, 'out-limpieza/renderer'), emptyOutDir: true, rollupOptions: { input: resolve(__dirname, 'src/limpieza/renderer/index.html') } }
  }
})
