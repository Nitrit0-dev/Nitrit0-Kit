import { useState } from 'react'
import { ChevronRight, ClipboardCheck, HeartPulse } from 'lucide-react'
import { Medidor, NotaSalud, PageHeader, Veredicto } from '../componentes/Basicos'
import { resumenRevision, type Area, type EstadoPaso, type Marca, type RevTotal } from '../revision'
import type { Dx, Elemento } from '../tipos'

const PUNTO: Record<EstadoPaso | Area['estado'], string> = { espera: 'espera', curso: 'activo', ok: '', aviso: 'aviso', fallo: 'error', noeval: 'info' }
const ETIQUETA: Record<EstadoPaso | Area['estado'], string> = { espera: 'En espera', curso: 'En curso', ok: 'Correcto', aviso: 'Aviso', fallo: 'Fallo', noeval: 'No evaluado' }

interface Props {
  rev: RevTotal | null; dx: Dx | null; manual: Elemento[]; elementos: Elemento[]; ocupado: boolean
  alIniciar: (m: 'chequeo' | 'fondo') => void; alDetener: () => void; alMarcar: (id: string, m: Marca) => void; alAbrir: (e: Elemento) => void
  alTerminarManual: () => void; alReiniciar: () => void; alDetalle: () => void; alInforme: () => void; alLanzar: (e: Elemento) => void
}

export default function RevisionTotal({ rev, dx, manual, elementos, ocupado, alIniciar, alDetener, alMarcar, alAbrir, alTerminarManual, alReiniciar, alDetalle, alInforme, alLanzar }: Props) {
  const [copiado, setCopiado] = useState(false)

  if (!rev) return (
    <div className="pagina">
      <PageHeader titulo="Revisión total del equipo" subtitulo="Lanza las pruebas una tras otra y te dice qué está sano y qué puede fallar, con una nota de 0 a 100. Ninguna prueba cambia nada del equipo." />
      {ocupado && <p className="aviso-txt">Hay otra cosa en marcha: espera a que termine para empezar la revisión.</p>}
      <div className="tarjetas" role="group" aria-label="Tipo de revisión">
        <button className="tarjeta" disabled={ocupado} onClick={() => alIniciar('chequeo')}>
          <span className="tarjeta-ficha" aria-hidden="true"><HeartPulse size={20} strokeWidth={1.75} /></span>
          <b>Chequeo de salud · unos 5 min</b>
          <span className="tarjeta-texto">¿Está sano este equipo? Diagnóstico rápido (17 pruebas), placa de vídeo 1 minuto y procesador 30 segundos.</span>
          <ChevronRight className="tarjeta-flecha" size={18} strokeWidth={1.75} aria-hidden="true" />
        </button>
        <button className="tarjeta" disabled={ocupado} onClick={() => alIniciar('fondo')}>
          <span className="tarjeta-ficha" aria-hidden="true"><ClipboardCheck size={20} strokeWidth={1.75} /></span>
          <b>Revisión a fondo · unos 30 min</b>
          <span className="tarjeta-texto">¿Qué puede fallar? Diagnóstico profundo (22 pruebas con SFC y comprobación de disco), procesador 5 minutos y placa de vídeo 5 minutos.</span>
          <ChevronRight className="tarjeta-flecha" size={18} strokeWidth={1.75} aria-hidden="true" />
        </button>
      </div>
      <p className="nota-vacia">Al final se piden unas comprobaciones manuales (pantalla, teclado, ratón, webcam, audio y mando) que se abren aquí dentro. Mientras corren las pruebas de carga, el equipo puede ir algo lento: no lo uses.</p>
    </div>
  )

  const filas = (
    <section className="bloque" aria-label="Pasos de la revisión">
      <h2>Pasos</h2>
      {rev.pasos.map((p, i) => (
        <div className="revision" key={p.id} style={{ gridTemplateColumns: '14px 1fr auto' }}>
          <span className={`punto ${PUNTO[p.estado]}`} role="img" aria-label={ETIQUETA[p.estado]} />
          <div>
            <b>{i + 1}. {p.titulo}</b>
            <div className="det">{p.texto || ETIQUETA[p.estado]}</div>
            {p.estado === 'curso' && <Medidor rol="progressbar" etiqueta={`Progreso de ${p.titulo}`} valor={p.pct} max={100} indeterminado={p.pct === 0} />}
          </div>
          <span className="sub-linea">{ETIQUETA[p.estado]}</span>
        </div>
      ))}
    </section>
  )

  if (rev.fase === 'pasos') return (
    <div className="pagina">
      <PageHeader titulo={rev.modo === 'chequeo' ? 'Chequeo de salud en marcha' : 'Revisión a fondo en marcha'} subtitulo="No cierres la app ni uses el equipo mientras corren las pruebas de carga. Puedes cambiar de pantalla: la revisión sigue."
        acciones={<button className="boton peligro-b" disabled={rev.parada} onClick={alDetener}>{rev.parada ? 'Deteniendo…' : 'Detener revisión'}</button>} />
      {filas}
    </div>
  )

  if (rev.fase === 'manual') return (
    <div className="pagina">
      <PageHeader titulo="Comprobaciones manuales" subtitulo="Lo que solo puedes ver tú. Abre cada una, pruébala y marca cómo ha ido; lo que no apliques (por ejemplo, el mando) déjalo en «Omitir»."
        acciones={<button className="boton principal-b" onClick={alTerminarManual}>Terminar revisión</button>} />
      <section className="bloque" aria-label="Pruebas manuales">
        {manual.length === 0 && <p className="nota-vacia">Este pack no lleva pruebas manuales.</p>}
        {manual.map((e) => {
          const m = rev.manual[e.id] ?? null
          return (
            <div className="revision" key={e.id} style={{ gridTemplateColumns: '14px 1fr auto' }}>
              <span className={`punto ${m === 'bien' ? '' : m === 'mal' ? 'error' : 'info'}`} role="img" aria-label={m ?? 'Sin marcar'} />
              <div><b>{e.titulo}</b><div className="det">{e.descripcion}</div></div>
              <div className="filtros" role="group" aria-label={`Resultado de ${e.titulo}`}>
                <button className="boton" onClick={() => alAbrir(e)}>Abrir</button>
                {(['bien', 'mal', 'omitido'] as const).map((k) => <button key={k} className="chip" aria-pressed={m === k} onClick={() => alMarcar(e.id, k)}>{k === 'bien' ? 'Bien' : k === 'mal' ? 'Mal' : 'Omitir'}</button>)}
              </div>
            </div>
          )
        })}
      </section>
    </div>
  )

  const r = resumenRevision(rev, dx, manual)
  const copiar = async () => { try { await navigator.clipboard.writeText(r.texto); setCopiado(true); setTimeout(() => setCopiado(false), 2500) } catch { /* sin portapapeles */ } }
  const memoria = rev.modo === 'fondo' ? ['Memoria Windows', 'MemTest86 (USB)'].map((t) => elementos.find((e) => e.titulo === t && e.soportado && e.disponible)).filter((e): e is Elemento => !!e) : []
  return (
    <div className="pagina">
      <PageHeader titulo="Resultado de la revisión" subtitulo={`${rev.modo === 'chequeo' ? 'Chequeo de salud' : 'Revisión a fondo'} · ${Math.max(1, Math.round((Date.now() - rev.t0) / 60000))} min en total (con las comprobaciones manuales).`}
        acciones={<><button className="boton" onClick={copiar}>{copiado ? 'Copiado' : 'Copiar resumen'}</button><button className="boton" onClick={alReiniciar}>Nueva revisión</button></>} />
      <section className="resumen-dx con-nota" aria-label="Nota">
        <NotaSalud nota={r.nota} />
        <div style={{ flex: 1, minWidth: 260 }}>
          <Veredicto tono={r.fallos ? 'error' : r.avisos ? 'aviso' : 'ok'} titulo={r.fallos ? `Hay ${r.fallos === 1 ? 'una cosa' : `${r.fallos} cosas`} que arreglar` : r.avisos ? 'Sano, con algún aviso' : 'El equipo está sano'}>
            {r.fallos || r.avisos ? `${r.fallos} fallo(s) y ${r.avisos} aviso(s). Lo que no se pudo evaluar no resta nota.` : 'Sin fallos ni avisos en lo que se ha podido comprobar. Una revisión de minutos no descarta fallos que solo salen tras horas de uso.'}
          </Veredicto>
          <div className="acciones">
            <button className="boton" onClick={alDetalle}>Ver el diagnóstico detallado y arreglar</button>
            <button className="boton" onClick={alInforme}>Informe de entrega</button>
          </div>
        </div>
      </section>
      {filas}
      <section className="bloque" aria-label="Resultado por áreas">
        <h2>Por áreas</h2>
        {r.areas.map((a) => (
          <div className="revision" key={a.nombre} style={{ gridTemplateColumns: '14px 1fr auto' }}>
            <span className={`punto ${PUNTO[a.estado]}`} role="img" aria-label={ETIQUETA[a.estado]} />
            <div><b>{a.nombre}</b>{a.detalle && <div className="det">{a.detalle}</div>}</div>
            <span className="sub-linea">{ETIQUETA[a.estado]}</span>
          </div>
        ))}
      </section>
      {memoria.length > 0 && (
        <section className="bloque" aria-label="Memoria a fondo">
          <h2>Memoria a fondo</h2>
          <p className="nota-vacia">La prueba seria de la RAM necesita reiniciar el equipo y no se puede hacer desde Windows. Si sospechas de la memoria, programa una de estas:</p>
          <div className="acciones">{memoria.map((e) => <button key={e.id} className="boton" disabled={ocupado} onClick={() => alLanzar(e)}>{e.titulo}</button>)}</div>
        </section>
      )}
    </div>
  )
}
