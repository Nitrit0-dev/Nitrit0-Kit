import { resolve } from 'node:path'
import { defineConfig } from 'electron-vite'
import react from '@vitejs/plugin-react'

// «Nitrit0 Clonador»: cuarta aplicación del mismo proyecto. Sale en out-clonador y comparte la base visual (src/renderer/src/diseno).
export default defineConfig({
  main: { build: { outDir: 'out-clonador/main', rollupOptions: { input: resolve(__dirname, 'src/clonador/main/index.ts') } } },
  preload: { build: { outDir: 'out-clonador/preload', rollupOptions: { input: resolve(__dirname, 'src/clonador/preload/index.ts') } } },
  renderer: {
    root: resolve(__dirname, 'src/clonador/renderer'),
    plugins: [react()],
    build: { outDir: resolve(__dirname, 'out-clonador/renderer'), emptyOutDir: true, rollupOptions: { input: resolve(__dirname, 'src/clonador/renderer/index.html') } }
  }
})
