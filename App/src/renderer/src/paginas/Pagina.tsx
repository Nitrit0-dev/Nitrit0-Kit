import { useMemo, useState } from 'react'
import { Search } from 'lucide-react'
import { PageHeader, Vacio } from '../componentes/Basicos'
import { Fila } from '../componentes/Fila'
import type { Elemento } from '../tipos'

interface Props {
  titulo: string; subtitulo: string; grupos: string[]; elementos: Elemento[]; favoritas: string[]; ocupado: boolean
  consulta: string; alConsulta: (q: string) => void; buscadorRef: React.RefObject<HTMLInputElement | null>
  alFavorita: (titulo: string) => void; alLanzar: (e: Elemento) => void
}

const normalizar = (t: string) => t.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()

/** Una página del kit (Comprobar, Reparar…): filtros por grupo, favoritas y búsqueda. Con búsqueda activa mira en todo el kit. */
export default function Pagina({ titulo, subtitulo, grupos, elementos, favoritas, ocupado, consulta, alConsulta, buscadorRef, alFavorita, alLanzar }: Props) {
  const [filtro, setFiltro] = useState('Todas')
  const q = normalizar(consulta.trim())
  const buscando = q.length > 0

  const propios = elementos.filter((e) => e.pagina === titulo)
  const visibles = useMemo(() => {
    const base = buscando ? elementos : propios
    return base.filter((e) => {
      if (buscando) return normalizar(`${e.titulo} ${e.descripcion} ${e.categoria}`).includes(q)
      if (filtro === 'Favoritas') return favoritas.includes(e.titulo)
      return filtro === 'Todas' || e.grupo === filtro
    })
  }, [elementos, propios, buscando, q, filtro, favoritas])

  // Con búsqueda se agrupa por página; sin ella, por grupo.
  const clave = (e: Elemento) => (buscando ? e.pagina : e.grupo)
  const secciones = useMemo(() => {
    const m = new Map<string, Elemento[]>()
    for (const e of visibles) m.set(clave(e), [...(m.get(clave(e)) ?? []), e])
    return [...m.entries()]
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visibles, buscando])

  const cuenta = (g: string) => (g === 'Todas' ? propios.length : g === 'Favoritas' ? propios.filter((e) => favoritas.includes(e.titulo)).length : propios.filter((e) => e.grupo === g).length)

  return (
    <div className="pagina">
      <PageHeader
        titulo={buscando ? 'Resultados' : titulo}
        subtitulo={buscando ? `${visibles.length} ${visibles.length === 1 ? 'herramienta coincide' : 'herramientas coinciden'} con «${consulta.trim()}» en todo el kit.` : subtitulo}
        acciones={
          <label className="buscador">
            <Search size={16} strokeWidth={1.75} aria-hidden="true" />
            <input ref={buscadorRef} type="search" placeholder="Buscar en el kit" aria-label="Buscar en el kit" value={consulta} onChange={(e) => alConsulta(e.target.value)} />
            <kbd aria-hidden="true">Ctrl+F</kbd>
          </label>
        }
      />
      {!buscando && (
        <div className="filtros" role="group" aria-label="Filtrar por grupo">
          {/* un grupo sin herramientas (por ejemplo, las de estrés en el pack público) no sale */}
          {['Todas', 'Favoritas', ...grupos.filter((g) => cuenta(g) > 0)].map((g) => (
            <button key={g} className="chip" aria-pressed={filtro === g} onClick={() => setFiltro(g)}>{g}<span className="cuenta num">{cuenta(g)}</span></button>
          ))}
        </div>
      )}
      {secciones.length === 0 && (
        <Vacio>
          {buscando
            ? <>Nada coincide con <b>«{consulta.trim()}»</b>. Prueba con una palabra del síntoma, como «disco», «red» o «pantalla».</>
            : filtro === 'Favoritas'
              ? <>Aún no hay favoritas aquí. Marca la estrella de una herramienta y la tendrás a mano en esta pestaña.</>
              : <>No hay herramientas en este grupo.</>}
        </Vacio>
      )}
      {secciones.map(([nombre, lista]) => (
        <section className="grupo" key={nombre} aria-label={nombre}>
          <h2>{nombre}<span className="num">{lista.length}</span></h2>
          {lista.map((e) => (
            <Fila key={e.id} e={e} favorita={favoritas.includes(e.titulo)} ocupado={ocupado} alFavorita={() => alFavorita(e.titulo)} alLanzar={() => alLanzar(e)} />
          ))}
        </section>
      ))}
    </div>
  )
}
