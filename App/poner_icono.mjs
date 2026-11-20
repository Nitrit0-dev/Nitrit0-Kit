// Pone el icono de Nitrit0 en el .exe de win-unpacked. electron-builder lo omite (signAndEditExecutable: false, porque su paquete winCodeSign
// no se extrae sin privilegios de enlace simbólico) y la barra de tareas y el explorador enseñarían el icono de Electron.
// Uso: node poner_icono.mjs "<ruta al .exe>"   (se ejecuta tras electron-builder, en los scripts npm de empaquetado)
import { execFileSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const aqui = dirname(fileURLToPath(import.meta.url))
const rcedit = join(aqui, 'node_modules', 'electron-winstaller', 'vendor', 'rcedit.exe')
const ico = join(aqui, 'build', 'icono.ico')
const exe = process.argv[2]
if (!exe || !existsSync(exe)) { console.error(`No encuentro el .exe: ${exe}`); process.exit(1) }
if (!existsSync(rcedit) || !existsSync(ico)) { console.error('Falta rcedit.exe (node_modules/electron-winstaller/vendor) o build/icono.ico'); process.exit(1) }
execFileSync(rcedit, [exe, '--set-icon', ico], { stdio: 'inherit' })
console.log(`Icono puesto en ${exe}`)
