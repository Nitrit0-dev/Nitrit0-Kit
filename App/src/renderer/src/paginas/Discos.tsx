import { useEffect, useState } from 'react'
import { PageHeader, Sello, Tarjeta, Veredicto } from '../componentes/Basicos'
import { numero as num } from '../equipo'
import type { DiscoFicha, Tono } from '../tipos'

const limpiar = (e: unknown) => String(e).replace(/^Error: (Error invoking remote method '[^']+': )?(Error: )?/, '')
const TIPO: Record<string, string> = { SSD: 'SSD', HDD: 'Disco duro (HDD)', Unspecified: 'USB o sin tipo', SCM: 'Memoria SCM' }

/** Bueno / Atención / Mal a partir de lo que Windows informa; los contadores que faltan no cuentan ni a favor ni en contra. */
export function valorar(d: DiscoFicha): { tono: Tono; texto: string; motivos: string[] } {
  if (d.salud !== 'Healthy') return { tono: 'error', texto: 'Mal', motivos: [`Windows lo marca como «${d.salud || 'sin dato'}»: haz copia de seguridad ya.`] }
  const m: string[] = []
  if (d.temperatura !== null && d.temperatura >= 70) m.push(`Temperatura alta (${d.temperatura} °C).`)
  if (d.desgaste !== null && d.desgaste >= 80) m.push(`Desgaste del ${d.desgaste} %: está cerca del final de su vida.`)
  if ((d.erroresLectura ?? 0) > 0 || (d.erroresEscritura ?? 0) > 0) m.push(`Errores de lectura/escritura: ${d.erroresLectura ?? 0} / ${d.erroresEscritura ?? 0}.`)
  return m.length ? { tono: 'aviso', texto: 'Atención', motivos: m } : { tono: 'ok', texto: 'Bueno', motivos: [] }
}

export default function Discos({ admin }: { admin?: boolean }) {
  const [lista, setLista] = useState<DiscoFicha[] | null>(null)
  const [fallo, setFallo] = useState('')
  const [leyendo, setLeyendo] = useState(false)
  const leer = () => {
    setFallo(''); setLeyendo(true)
    window.kit.discos().then((r: DiscoFicha[]) => setLista(Array.isArray(r) ? r : [])).catch((e: unknown) => setFallo(limpiar(e))).finally(() => setLeyendo(false))
  }
  useEffect(leer, [])

  if (fallo && !lista) return <div className="pagina"><PageHeader titulo="Salud de los discos" subtitulo="No se pudo leer los discos." /><p className="vacio">{fallo}</p><div><button className="boton" onClick={leer}>Volver a intentarlo</button></div></div>
  if (!lista) return <div className="pagina"><PageHeader titulo="Salud de los discos" subtitulo="Leyendo los discos, tarda unos segundos…" /></div>

  const val = lista.map(valorar)
  const mal = val.filter((v) => v.tono === 'error').length, atencion = val.filter((v) => v.tono === 'aviso').length
  const sinContadores = lista.length > 0 && lista.every((d) => d.temperatura === null && d.horas === null && d.desgaste === null)
  const tono: Tono = mal ? 'error' : atencion ? 'aviso' : 'ok'
  const titular = lista.length === 0 ? 'Windows no ha devuelto ningún disco'
    : mal ? `${mal === 1 ? 'Un disco avisa' : `${mal} discos avisan`} de problemas`
    : atencion ? `${atencion === 1 ? 'Un disco merece' : `${atencion} discos merecen`} atención` : `${lista.length === 1 ? 'El disco está sano' : `Los ${lista.length} discos están sanos`}`

  return (
    <div className="pagina">
      <PageHeader titulo="Salud de los discos" subtitulo="Cómo está cada disco según Windows: estado, temperatura, horas de uso y desgaste. Solo lectura: no cambia nada."
        comoUsar={['Mira el veredicto de arriba.', 'Un disco en «Atención» o «Mal» merece copia de seguridad.', 'Para un examen a fondo, usa CrystalDiskInfo desde Herramientas.']}
        acciones={<button className="boton" onClick={leer} disabled={leyendo}>{leyendo ? 'Leyendo…' : 'Volver a leer'}</button>} />
      <Veredicto tono={tono} titulo={titular}>
        {mal ? 'No uses ese disco para guardar nada importante hasta tener una copia.' : atencion ? 'Nada grave todavía, pero conviene vigilarlo y tener copia de lo importante.' : 'Sin avisos de Windows en ningún disco.'}
      </Veredicto>
      {sinContadores && <p className="nota-vacia">{admin === false ? 'Windows no da la temperatura ni el desgaste sin permisos de administrador: pulsa «Elevar permisos» en el menú y vuelve a leer.' : 'Windows no da la temperatura ni el desgaste de estos discos (pasa con algunos USB y NVMe).'}</p>}
      <div className="cajas">
        {lista.map((d, i) => (
          <Tarjeta key={`${d.nombre}${i}`} titulo={d.nombre}
            datos={[
              ['Estado', <span key="e"><Sello tipo={val[i].tono === 'ok' ? 'ok' : val[i].tono === 'aviso' ? 'aviso' : 'error'}>{val[i].texto}</Sello></span>],
              ['Tipo', `${TIPO[d.tipo] ?? (d.tipo || 'Sin dato')} · ${d.bus || 'bus desconocido'} · ${num(d.gb, 0)} GB`],
              ['Unidades', d.letras.length ? d.letras.map((l) => `${l}:`).join(' ') : 'Sin letra'],
              ['Temperatura', d.temperatura !== null && <span className="num" key="t">{d.temperatura} °C</span>],
              ['Horas encendido', d.horas !== null && <span className="num" key="h">{num(d.horas, 0)} h ({num(d.horas / 24, 0)} días)</span>],
              ['Desgaste', d.desgaste !== null && <span className="num" key="d">{d.desgaste} %</span>],
              ['Errores lect./escr.', d.erroresLectura !== null && <span className="num" key="er">{d.erroresLectura} / {d.erroresEscritura ?? 0}</span>],
              ['Firmware', d.firmware && <span className="num" key="f">{d.firmware}</span>]
            ]}>
            {val[i].motivos.length > 0 && <ul className="motivos">{val[i].motivos.map((m) => <li key={m}>{m}</li>)}</ul>}
          </Tarjeta>
        ))}
      </div>
    </div>
  )
}
