// Empaqueta la app en App\bin\Nitrit0\ (carpeta portátil, sin instalador) con permisos de administrador.
// Uso: npm run empaquetar. Se ejecuta desde el pendrive: el exe sube hasta encontrar Datos\kit.id.
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { packager } from '@electron/packager'

const aqui = dirname(fileURLToPath(import.meta.url))
const png = join(aqui, 'build', 'icono-256.png')
const ico = join(aqui, 'build', 'icono.ico')

// El logo es de 500 px y un .ico admite 256 como máximo: se reduce una vez con System.Drawing y se envuelve el PNG en un .ico.
if (!existsSync(ico)) {
  mkdirSync(join(aqui, 'build'), { recursive: true })
  const ps = `Add-Type -AssemblyName System.Drawing; $o=[Drawing.Image]::FromFile('${join(aqui, 'src/renderer/src/recursos/logo-nitrit0.png')}'); $b=New-Object Drawing.Bitmap 256,256; $g=[Drawing.Graphics]::FromImage($b); $g.InterpolationMode='HighQualityBicubic'; $g.DrawImage($o,0,0,256,256); $b.Save('${png}',[Drawing.Imaging.ImageFormat]::Png)`
  execFileSync(join(process.env.SystemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe'), ['-NoProfile', '-Command', ps])
  const datos = readFileSync(png)
  const cab = Buffer.alloc(22)
  cab.writeUInt16LE(1, 2); cab.writeUInt16LE(1, 4)           // tipo icono, 1 imagen
  cab.writeUInt16LE(1, 10); cab.writeUInt16LE(32, 12)        // 1 plano, 32 bits (ancho/alto 0 = 256)
  cab.writeUInt32LE(datos.length, 14); cab.writeUInt32LE(22, 18)
  writeFileSync(ico, Buffer.concat([cab, datos]))
}

const salida = await packager({
  dir: aqui,
  out: join(aqui, 'bin'),
  name: 'Nitrit0',
  executableName: 'Nitrit0',
  platform: 'win32',
  arch: 'x64',
  overwrite: true,
  asar: true,
  prune: false,
  icon: ico,
  // Solo hace falta lo compilado: las dependencias del renderer ya van dentro del paquete de Vite.
  ignore: [/^\/(src|node_modules|bin|build|datos|docs)(\/|$)/, /^\/(empaquetar\.mjs|electron\.vite\.config\.ts|tsconfig\.json|DESIGN\.md|Gemini\.txt|package-lock\.json|captura_.*|revision_.*)$/],
  win32metadata: {
    CompanyName: 'Nitrit0',
    FileDescription: 'Nitrit0 Kit',
    ProductName: 'Nitrit0 Kit',
    'requested-execution-level': 'requireAdministrator'
  }
})
console.log('Listo:', salida.join(', '))
