import { useEffect, useState } from 'react'
import { PageHeader, Medidor, Tarjeta } from '../componentes/Basicos'
import { usaEjecutor, verbo, type Elemento, type Resumen, type Tono, type Vivo } from '../tipos'
import { diasEncendido, leerResumen, numero as num, resumenCaducado, resumenGuardado } from '../equipo'

export interface Revision { tono: Tono; titulo: string; detalle: string; accion?: string }

const plural = (n: number, uno: string, varios: string) => `${n} ${n === 1 ? uno : varios}`
const limpiar = (e: unknown) => String(e).replace(/^Error: (Error invoking remote method '[^']+': )?(Error: )?/, '')

/** Revisiones a partir de datos reales. Cada una apunta, si hace falta, a la herramienta que resuelve lo que encuentra. */
export function revisiones(r: Resumen, v: Vivo | null): Revision[] {
  const lista: Revision[] = []
  const malos = r.discos.filter((d) => d.salud !== 'Healthy')
  lista.push(malos.length
    ? { tono: 'error', titulo: 'Un disco avisa de problemas', detalle: malos.map((d) => `${d.nombre}: ${d.salud}`).join(', '), accion: 'CrystalDiskInfo' }
    : { tono: 'ok', titulo: 'Discos con buena salud', detalle: `${plural(r.discos.length, 'disco', 'discos')} sin avisos de Windows.` })
  const justo = r.volumenes.filter((x) => x.totalGb > 0).map((x) => ({ x, libre: x.libreGb / x.totalGb })).sort((a, b) => a.libre - b.libre)[0]
  if (justo) {
    const pct = `${num(justo.libre * 100, 0)} % libre`
    lista.push(justo.libre < 0.15
      ? { tono: justo.libre < 0.05 ? 'error' : 'aviso', titulo: `${justo.x.letra}: va justo de espacio`, detalle: `${pct}, ${num(justo.x.libreGb, 0)} GB de ${num(justo.x.totalGb, 0)}.`, accion: 'Analizar_Espacio_Disco.ps1' }
      : { tono: 'ok', titulo: 'Espacio suficiente', detalle: `La unidad más llena es ${justo.x.letra}: con ${pct}.` })
  }
  if (v) lista.push(v.ramUsadaGb / v.ramGb > 0.9
    ? { tono: 'aviso', titulo: 'La memoria está casi llena', detalle: `${num(v.ramUsadaGb)} de ${num(v.ramGb)} GB en uso.`, accion: 'Gestion_Memoria_RAM.ps1' }
    : { tono: 'ok', titulo: 'Memoria con margen', detalle: `${num(v.ramUsadaGb)} de ${num(v.ramGb)} GB en uso.` })
  const dias = diasEncendido(r)
  if (Number.isFinite(dias)) lista.push(dias > 14
    ? { tono: 'aviso', titulo: 'Lleva mucho sin reiniciarse', detalle: `${Math.floor(dias)} días encendido. Reiniciar aplica actualizaciones pendientes.` }
    : { tono: 'ok', titulo: 'Reinicio reciente', detalle: `Encendido desde hace ${dias < 1 ? `${Math.max(1, Math.round(dias * 24))} h` : `${num(dias)} días`}.` })
  return lista
}

const saludTexto = (s: string) => (s === 'Healthy' ? 'Sin avisos' : s === 'Warning' ? 'Aviso' : s === 'Unhealthy' ? 'Fallo' : s || 'Sin dato')

export default function Inicio({ elementos, favoritas, alLanzar, ocupado, encolar = false, alDiagnostico, alEquilibrio }: {
  elementos: Elemento[]; favoritas: string[]; alLanzar: (e: Elemento) => void; ocupado: boolean; encolar?: boolean; alDiagnostico: () => void; alEquilibrio: () => void
}) {
  const [r, setR] = useState<Resumen | null>(resumenGuardado())
  const [v, setV] = useState<Vivo | null>(null)
  const [fallo, setFallo] = useState('')
  const [leyendo, setLeyendo] = useState(false)
  const [copiado, setCopiado] = useState(false)

  const cargar = () => {
    setFallo(''); setLeyendo(true)
    // La lectura se conserva y se refresca detrás (equipo.ts), para no volver a esperar cada vez que se entra en Inicio
    leerResumen()
      .then(setR)
      .catch((e: unknown) => setFallo(limpiar(e)))
      .finally(() => setLeyendo(false))
  }
  useEffect(() => { if (resumenCaducado()) cargar() }, [])
  useEffect(() => {
    const t = () => window.kit.vivo().then(setV)
    void t()
    const id = setInterval(t, 2000)
    return () => clearInterval(id)
  }, [])

  const porId = (id?: string) => elementos.find((e) => e.id === id && e.soportado && e.disponible)

  if (fallo && !r) return (
    <div className="pagina"><PageHeader titulo="Inicio" subtitulo="No se pudo leer los datos del equipo." />
      <p className="vacio">{fallo}</p><div><button className="boton" onClick={cargar}>Volver a intentarlo</button></div></div>
  )
  if (!r) return <div className="pagina"><PageHeader titulo="Inicio" subtitulo="Leyendo el equipo, tarda unos segundos…" /></div>

  const lista = revisiones(r, v)
  const pendientes = lista.filter((x) => x.tono !== 'ok').length
  const dias = diasEncendido(r)
  const favs = favoritas.map((t) => elementos.find((e) => e.titulo === t)).filter((e): e is Elemento => !!e && e.soportado && e.disponible)
  const equipo = r.equipo || 'este equipo'
  /** Resumen para pegar al pedir ayuda: nunca lleva el nombre del equipo ni números de serie. */
  const copiarResumen = async () => {
    const t = [`RESUMEN ${new Date().toLocaleString('es-ES')}`, `Equipo: ${r.modelo}`, `Windows: ${r.windows} ${r.version}${r.arquitectura ? ` (${r.arquitectura})` : ''}`, `Placa: ${r.placa ?? '-'} · BIOS ${r.bios}${r.biosFecha ? ` (${r.biosFecha})` : ''}`,
      `CPU: ${r.cpu} · ${r.nucleos} núcleos / ${r.hilos} hilos`, `RAM: ${r.ramGb} GB`, ...(r.graficas ?? []).map((g) => `Gráfica: ${g.nombre} (driver ${g.driver})`),
      ...r.discos.map((d) => `Disco: ${d.nombre} · ${d.tipo} · ${d.gb} GB · ${saludTexto(d.salud)}`), ...r.volumenes.map((x) => `Unidad ${x.letra}: ${num(x.libreGb, 0)} GB libres de ${num(x.totalGb, 0)}`),
      '', ...lista.map((x) => `[${x.tono === 'ok' ? 'OK' : x.tono === 'aviso' ? 'AVISO' : 'FALLO'}] ${x.titulo}: ${x.detalle}`)].join('\n')
    try { await navigator.clipboard.writeText(t); setCopiado(true); setTimeout(() => setCopiado(false), 2500) } catch { /* sin portapapeles */ }
  }

  return (
    <div className="pagina">
      <PageHeader
        titulo={pendientes ? `${pendientes === 1 ? 'Hay una cosa' : `Hay ${pendientes} cosas`} que mirar en ${equipo}` : `Sin avisos en la revisión rápida de ${equipo}`}
        subtitulo={[r.modelo, r.windows].filter(Boolean).join(' · ') || undefined}
        comoUsar={['Mira la revisión rápida.', 'Si algo avisa, pulsa su botón.', 'Para pedir ayuda, «Copiar resumen» (sin nombre del equipo ni serie).']}
        acciones={<>
          <button className="boton" onClick={() => void copiarResumen()}>{copiado ? 'Copiado' : 'Copiar resumen'}</button>
          <button className="boton" onClick={alEquilibrio}>Qué lo frena</button>
          <button className="boton principal-b" disabled={ocupado} onClick={alDiagnostico}>Diagnóstico rápido</button>
        </>}
      />
      {fallo && <p className="aviso-txt" role="alert">No se pudo actualizar los datos: {fallo}</p>}
      <div className="inicio">
        <div className="columna">
          <section className="bloque" aria-label="Revisiones">
            <h2>Revisión rápida{leyendo && <span className="num actualizando"> · actualizando…</span>}</h2>
            {lista.map((x) => {
              const e = porId(x.accion)
              return (
                <div className="revision" key={x.titulo}>
                  <span className={`punto ${x.tono}`} role="img" aria-label={x.tono === 'ok' ? 'Correcto' : x.tono === 'aviso' ? 'Aviso' : 'Problema'} />
                  <div><b>{x.titulo}</b><div className="det">{x.detalle}</div></div>
                  {e && x.tono !== 'ok' && <button className="boton" disabled={ocupado && !encolar && usaEjecutor(e)} onClick={() => alLanzar(e)} aria-label={`${verbo(e)} ${e.titulo}`}>{e.titulo}</button>}
                </div>
              )
            })}
          </section>
          <section className="bloque" aria-label="Unidades">
            <h2>Unidades</h2>
            {r.volumenes.length === 0 && <p className="nota-vacia">No hay unidades fijas con tamaño medible (una unidad bloqueada o sin formato no aparece).</p>}
            {[...r.volumenes].sort((a, b) => (a.letra.toUpperCase() === 'C' ? -1 : b.letra.toUpperCase() === 'C' ? 1 : a.letra.localeCompare(b.letra))).map((x) => {
              const usado = x.totalGb - x.libreGb, pct = usado / x.totalGb
              return (
                <div className="unidad" key={x.letra}>
                  <b className="num">{x.letra}:</b>
                  <div><div>{x.etiqueta || 'Sin etiqueta'}</div><Medidor etiqueta={`Espacio usado en ${x.letra}:`} valor={usado} max={x.totalGb} tono={pct > 0.95 ? 'error' : pct > 0.9 ? 'aviso' : undefined} /></div>
                  <span className="sub num">{num(x.libreGb, 0)} libres de {num(x.totalGb, 0)} GB</span>
                </div>
              )
            })}
          </section>
          <section className="bloque" aria-label="Favoritas">
            <h2>Tus favoritas</h2>
            {favs.length === 0 && <p className="nota-vacia">Marca la estrella de una herramienta y aparecerá aquí.</p>}
            {favs.map((e) => (
              <div className="fila-simple" key={e.id}>
                <span>{e.titulo}</span>
                <button className="boton" disabled={ocupado && !encolar && usaEjecutor(e)} onClick={() => alLanzar(e)} aria-label={`${verbo(e)} ${e.titulo}`}>{verbo(e)}</button>
              </div>
            ))}
          </section>
        </div>
        <div className="columna">
          <Tarjeta titulo="Sistema" datos={[['Windows', r.windows], ['Versión', r.version && <span className="num">{r.version}</span>], ['Arquitectura', r.arquitectura], ['Instalado el', r.instalado && <span className="num">{r.instalado}</span>], ['Encendido hace', Number.isFinite(dias) ? <span className="num">{dias < 1 ? `${Math.max(1, Math.round(dias * 24))} h` : `${num(dias)} días`}</span> : '']]} />
          <Tarjeta titulo="Placa base y BIOS" datos={[['Equipo', r.modelo], ['Placa', r.placa], ['BIOS', r.bios && <span className="num">{r.bios}</span>], ['Fecha de la BIOS', r.biosFecha && <span className="num">{r.biosFecha}</span>]]} />
          <Tarjeta titulo="Procesador y memoria" datos={[['Procesador', r.cpu.replace(/\s*\d+-Core Processor/, '')], ['Núcleos / hilos', <span className="num" key="n">{r.nucleos} / {r.hilos}</span>], ['Memoria', <span className="num" key="m">{r.ramGb} GB</span>], ['En uso ahora', v ? <span className="num" key="v">CPU {v.cpu} % · RAM {num(v.ramUsadaGb)} / {num(r.ramGb, 0)} GB</span> : '']]} />
          {(r.graficas ?? []).map((g, i) => <Tarjeta key={`${g.nombre}${i}`} titulo={(r.graficas ?? []).length > 1 ? `Gráfica ${i + 1}` : 'Gráfica'} datos={[['Modelo', g.nombre], ['Driver', g.driver && <span className="num">{g.driver}</span>]]} />)}
          <section className="bloque" aria-label="Discos físicos">
            <h2>Discos físicos</h2>
            {r.discos.map((d) => (
              <div className="fila-simple" key={d.nombre}>
                <div>{d.nombre}<div className="sub-linea">{d.tipo === 'Unspecified' ? 'USB o sin tipo' : d.tipo} · <span className="num">{num(d.gb, 0)} GB</span></div></div>
                <span className={`num salud ${d.salud === 'Healthy' ? 'ok' : 'mal'}`}>{saludTexto(d.salud)}</span>
              </div>
            ))}
          </section>
        </div>
      </div>
    </div>
  )
}
