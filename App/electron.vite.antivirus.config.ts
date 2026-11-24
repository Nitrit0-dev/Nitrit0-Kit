import { resolve } from 'node:path'
import { defineConfig } from 'electron-vite'
import react from '@vitejs/plugin-react'

// «Nitrit0 Antivirus»: tercera aplicación del mismo proyecto. Sale en out-antivirus y comparte la base visual (src/renderer/src/diseno).
export default defineConfig({
  main: { build: { outDir: 'out-antivirus/main', rollupOptions: { input: resolve(__dirname, 'src/antivirus/main/index.ts') } } },
  preload: { build: { outDir: 'out-antivirus/preload', rollupOptions: { input: resolve(__dirname, 'src/antivirus/preload/index.ts') } } },
  renderer: {
    root: resolve(__dirname, 'src/antivirus/renderer'),
    plugins: [react()],
    build: { outDir: resolve(__dirname, 'out-antivirus/renderer'), emptyOutDir: true, rollupOptions: { input: resolve(__dirname, 'src/antivirus/renderer/index.html') } }
  }
})
