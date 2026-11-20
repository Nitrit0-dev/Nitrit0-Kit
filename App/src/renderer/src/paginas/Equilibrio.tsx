import { useState } from 'react'
import { PageHeader, Medidor } from '../componentes/Basicos'
import type { Eq, EstadoPrueba, Tono } from '../tipos'

const PERFILES = [
  { id: 'General', texto: 'General', ayuda: 'Uso mixto de todos los días.' },
  { id: 'Juegos', texto: 'Juegos', ayuda: 'Pesa más la gráfica y la memoria de vídeo.' },
  { id: 'Creacion', texto: 'Creación', ayuda: 'Edición de vídeo, diseño y 3D: pide más RAM y CPU.' },
  { id: 'Oficina', texto: 'Oficina', ayuda: 'Navegador y documentos: lo básico basta.' }
]
const TONO: Record<EstadoPrueba, Tono | undefined> = { OK: undefined, Info: undefined, Aviso: 'aviso', Fallo: 'error' }

export default function Equilibrio({ eq, ocupado, alAnalizar }: { eq: Eq | null; ocupado: boolean; alAnalizar: (perfil: string) => void }) {
  const [perfil, setPerfil] = useState('General')
  const a = eq?.analisis
  const trabajando = !!eq?.trabajando

  return (
    <div className="pagina">
      <PageHeader
        titulo="Qué lo frena"
        subtitulo="Mide qué pieza frena a las demás: procesador, gráfica, memoria (doble o simple canal) o disco."
        acciones={<button className="boton principal-b" disabled={ocupado || trabajando} onClick={() => alAnalizar(perfil)}>{trabajando ? 'Analizando…' : a ? 'Analizar otra vez' : 'Analizar equipo'}</button>}
      />
      <div className="filtros" role="group" aria-label="Perfil de uso">
        {PERFILES.map((p) => <button key={p.id} className="chip" aria-pressed={perfil === p.id} onClick={() => setPerfil(p.id)} disabled={trabajando}>{p.texto}</button>)}
      </div>
      <p className="nota-opcion">{PERFILES.find((p) => p.id === perfil)?.ayuda} El análisis tarda unos segundos y mide la velocidad del disco con un archivo temporal de 128 MB.</p>

      {eq?.error && <p className="aviso-txt" role="alert">{eq.error}</p>}
      {trabajando && !a && <div className="estado-ejec" role="status">Leyendo CPU, gráfica, memoria y disco…</div>}

      {a && (
        <>
          <section aria-label="Veredicto" className="resumen-dx">
            <h2 className={a.clase === 'Fallo' ? 'mal' : a.clase === 'Aviso' ? 'aviso' : 'ok'}>{a.veredicto}</h2>
            <p>Perfil {PERFILES.find((p) => p.id === a.perfil)?.texto.toLowerCase() ?? a.perfil}{a.portatil ? ', equipo portátil' : ', equipo de sobremesa'}.</p>
          </section>
          <section className="bloque" aria-label="Componentes">
            <h2>Equilibrio entre piezas</h2>
            {a.componentes.map((c) => {
              const debil = a.pieza === c.clave
              return (
                <div className="unidad comp" key={c.clave}>
                  <b>{c.clave}</b>
                  <div>
                    <div>{c.nombre.replace(/\s*\d+-Core Processor/, '')}</div>
                    <div className="sub">{[c.detalle, c.anio ? `de ${c.anio}` : '', c.gama].filter(Boolean).join(' · ')}</div>
                    <Medidor etiqueta={`Puntuación de ${c.clave}`} valor={c.score} tono={debil ? 'aviso' : undefined} />
                  </div>
                  <span className="num">{c.score}{debil ? ' · la más justa' : ''}</span>
                </div>
              )
            })}
          </section>
          <section className="bloque" aria-label="Hallazgos">
            <h2>Qué se ha encontrado</h2>
            {a.hallazgos.map((h) => (
              <details className="prueba" key={h.id} open={h.estado === 'Fallo'}>
                <summary>
                  <span className={`punto ${TONO[h.estado] ?? (h.estado === 'Info' ? 'info' : 'ok')}`} role="img" aria-label={h.estado === 'OK' ? 'Correcto' : h.estado === 'Aviso' ? 'Aviso' : h.estado === 'Fallo' ? 'Problema' : 'Información'} />
                  <span className="cuerpo"><b>{h.titulo}</b><span className="det">{h.resumen}</span></span>
                </summary>
                {(h.detalle || h.siguiente) && (
                  <div className="prueba-detalle">
                    {h.detalle && <pre>{h.detalle}</pre>}
                    {h.siguiente && <p className="siguiente-txt"><b>Siguiente paso:</b> {h.siguiente}</p>}
                  </div>
                )}
              </details>
            ))}
          </section>
        </>
      )}
    </div>
  )
}
