import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { DatabaseZap, Eraser, PackageX, Power } from 'lucide-react'
import logo from '../../renderer/src/recursos/logo-nitrit0.png'
import { Confirmar, ErrorBoundary } from '../../renderer/src/componentes/Basicos'
import Limpiador, { type Categoria, type Resultado } from './paginas/Limpiador'
import Inicio, { type Arranque, type ItemInicio } from './paginas/Inicio'
import Programas, { type Programa } from './paginas/Programas'
import Registro, { type Resto } from './paginas/Registro'

type Evento = Record<string, unknown> & { op: string; evento: string }

export default function App() {
  const [vista, setVista] = useState<'limpiador' | 'inicio' | 'programas' | 'registro'>('limpiador')
  const [oscuro, setOscuro] = useState(true)
  const [pie, setPie] = useState('')
  const [ocupado, setOcupado] = useState(false)
  const [admin, setAdmin] = useState<boolean | null>(null)
  const [cerrando, setCerrando] = useState(false)
  // Limpiador
  const [cats, setCats] = useState<Categoria[]>([])
  const [sel, setSel] = useState<Set<string>>(new Set())
  const [fase, setFase] = useState<'analizando' | 'listo' | 'limpiando' | 'hecho'>('analizando')
  const [resultados, setResultados] = useState<Record<string, Resultado>>({})
  const [liberado, setLiberado] = useState<number | null>(null)
  const [avisos, setAvisos] = useState<string[]>([])
  // Inicio
  const [items, setItems] = useState<ItemInicio[] | null>(null)
  const [arranque, setArranque] = useState<Arranque | null>(null)
  // Registro
  const [restos, setRestos] = useState<Resto[] | null>(null)
  const [salidaReg, setSalidaReg] = useState<string[]>([])
  const [faseReg, setFaseReg] = useState<'inicial' | 'analizando' | 'listo' | 'limpiando' | 'hecho'>('inicial')
  // Programas
  const [salidaDes, setSalidaDes] = useState<string[]>([])
  const [desMarcha, setDesMarcha] = useState(false)
  const [programas, setProgramas] = useState<Programa[] | null>(null)
  const primeraSeleccion = useRef(true)

  useEffect(() => {
    void window.limpieza.estado().then((e) => {
      const mq = window.matchMedia('(prefers-color-scheme: dark)')
      const poner = () => setOscuro(e.tema === 'sistema' ? mq.matches : e.tema === 'oscuro')
      poner(); mq.addEventListener('change', poner)
    })
  }, [])
  useEffect(() => { document.documentElement.dataset.tema = oscuro ? 'oscuro' : 'claro' }, [oscuro])

  // Un solo suscriptor de eventos del motor para toda la app
  useEffect(() => {
    const quitar = window.limpieza.alEvento((ev: Evento) => {
      const t = (k: string) => (typeof ev[k] === 'string' ? (ev[k] as string) : '')
      const n = (k: string) => (typeof ev[k] === 'number' ? (ev[k] as number) : 0)
      if (ev.op === 'Analizar') {
        if (ev.evento === 'categoria') {
          const c: Categoria = { id: t('id'), grupo: t('grupo'), nombre: t('nombre'), ayuda: t('ayuda'), marcada: ev.marcada === true, riesgo: t('riesgo'), bytes: n('bytes'), archivos: n('archivos'), admin: ev.admin === true, abiertos: Array.isArray(ev.abiertos) ? (ev.abiertos as unknown[]).filter((x): x is string => typeof x === 'string') : [] }
          setCats((l) => [...l.filter((x) => x.id !== c.id), c])
          if (primeraSeleccion.current && c.marcada) setSel((s) => new Set(s).add(c.id))
        }
        if (ev.evento === 'fin') { setAdmin(ev.esAdmin === true); primeraSeleccion.current = false }
      } else if (ev.op === 'Limpiar') {
        if (ev.evento === 'categoria') setResultados((r) => ({ ...r, [t('id')]: { bytes: n('bytes'), enUso: n('enUso') } }))
        if (ev.evento === 'error') { if (t('id')) setResultados((r) => ({ ...r, [t('id')]: { bytes: 0, enUso: 0, error: t('mensaje') } })); else setPie(t('mensaje')) }
        if (ev.evento === 'aviso') setAvisos((a) => [...a, t('mensaje')])
        if (ev.evento === 'fin') setLiberado(n('bytes'))
      } else if (ev.op === 'InicioListar') {
        if (ev.evento === 'inicio') setItems((l) => [...(l ?? []), { tipo: t('tipo') as 'registro' | 'tarea', id: t('id'), nombre: t('nombre'), ambito: t('ambito'), orden: t('orden'), activo: ev.activo === true, icono: t('icono') || undefined }])
        if (ev.evento === 'arranque') setArranque({ segundos: n('segundos'), escritorio: n('escritorio'), fecha: t('fecha'), lentos: Array.isArray(ev.lentos) ? (ev.lentos as unknown[]).filter((x): x is string => typeof x === 'string') : [] })
        if (ev.evento === 'fin') setAdmin(ev.esAdmin === true)
      } else if (ev.op === 'RegistroAnalizar') {
        if (ev.evento === 'resto') setRestos((l) => [...(l ?? []), { conf: t('conf'), grupo: t('grupo'), detalle: t('detalle') }])
        if (ev.evento === 'fin') setAdmin(ev.esAdmin === true)
      } else if (ev.op === 'RegistroLimpiar') {
        if (ev.evento === 'salida') setSalidaReg((s) => [...s, t('texto')])
        if (ev.evento === 'error') setPie(t('mensaje'))
      } else if (ev.op === 'ProgramasListar') {
        if (ev.evento === 'programa') setProgramas((l) => [...(l ?? []), { nombre: t('nombre'), editor: t('editor'), version: t('version'), mb: n('mb'), fecha: t('fecha'), ambito: t('ambito'), ultimoUso: t('ultimoUso') }])
        if (ev.evento === 'fin') setAdmin(ev.esAdmin === true)
      } else if (ev.op === 'DesinstalarFondo') {
        if (ev.evento === 'salida') setSalidaDes((s) => [...s.slice(-400), t('texto')])
        if (ev.evento === 'error') setPie(t('mensaje'))
      } else if (ev.op === 'InicioCambiar' && ev.evento === 'error') setPie(t('mensaje'))
    })
    const quitarCierre = window.limpieza.alCerrando(() => setCerrando(true))
    return () => { quitar(); quitarCierre() }
  }, [])

  const analizar = useCallback(async () => {
    setOcupado(true); setFase('analizando'); setCats([]); setResultados({}); setLiberado(null); setAvisos([])
    const r = await window.limpieza.motor('Analizar')
    if (!r.ok) setPie(r.mensaje)
    setFase('listo'); setOcupado(false)
  }, [])
  const cargarInicio = useCallback(async () => {
    setOcupado(true); setItems([]); setArranque(null)
    const r = await window.limpieza.motor('InicioListar')
    if (!r.ok) setPie(r.mensaje)
    setOcupado(false)
  }, [])
  const cargarProgramas = useCallback(async () => {
    setOcupado(true); setProgramas([])
    const r = await window.limpieza.motor('ProgramasListar')
    if (!r.ok) setPie(r.mensaje)
    setOcupado(false)
  }, [])
  const analizarRegistro = useCallback(async () => {
    setOcupado(true); setFaseReg('analizando'); setRestos([]); setSalidaReg([])
    const r = await window.limpieza.motor('RegistroAnalizar')
    if (!r.ok) setPie(r.mensaje)
    setFaseReg('listo'); setOcupado(false)
  }, [])
  const limpiarRegistro = async (modo: 'Auto' | 'Manual') => {
    setOcupado(true); setFaseReg('limpiando'); setSalidaReg([])
    const r = await window.limpieza.motor('RegistroLimpiar', { modo })
    if (!r.ok && r.mensaje) setPie(r.mensaje)
    setFaseReg(r.codigo === null ? 'listo' : 'hecho'); setOcupado(false)   // codigo null: el motor rechazó la petición o no llegó a arrancar; no se dice «hecho»
  }
  const desinstalar = async (lista: Programa[]) => {
    const quien = lista.length === 1 ? lista[0].nombre : `${lista.length} programas`
    setOcupado(true); setDesMarcha(true); setSalidaDes([]); setPie(`Desinstalando ${quien}…`)
    const r = await window.limpieza.motor('DesinstalarFondo', { nombres: lista.map((p) => p.nombre) })
    setPie(r.ok ? `${quien}: terminado.` : r.mensaje || `${quien}: no se completó del todo.`)
    setDesMarcha(false); setOcupado(false); void cargarProgramas()
  }
  useEffect(() => { void analizar() }, [analizar])
  useEffect(() => { if (vista === 'inicio' && items === null) void cargarInicio() }, [vista, items, cargarInicio])
  useEffect(() => { if (vista === 'programas' && programas === null) void cargarProgramas() }, [vista, programas, cargarProgramas])

  const limpiar = async () => {
    setOcupado(true); setFase('limpiando'); setResultados({}); setLiberado(null); setAvisos([])
    const ids = cats.filter((c) => sel.has(c.id) && (!c.admin || admin)).map((c) => c.id)
    const r = await window.limpieza.motor('Limpiar', { ids })
    if (!r.ok && r.mensaje) setPie(r.mensaje)
    setFase(r.codigo === null ? 'listo' : 'hecho'); setOcupado(false)   // codigo null: el motor rechazó la petición o no llegó a arrancar; no se dice «hecho»
  }
  const cambiarInicio = async (it: ItemInicio, activar: boolean) => {
    setOcupado(true); setPie('')
    const r = await window.limpieza.motor('InicioCambiar', { tipo: it.tipo, id: it.id, activar })
    if (r.ok) { setItems((l) => (l ?? []).map((x) => (x.id === it.id && x.tipo === it.tipo ? { ...x, activo: activar } : x))); setPie(`${it.nombre}: ${activar ? 'volverá a cargarse' : 'ya no se cargará'} al iniciar Windows.`) }
    else if (r.mensaje) setPie((p) => p || r.mensaje)   // si el propio motor ya explicó el fallo se conserva; si se rechazó antes de arrancar, esto es lo único que verá la persona
    setOcupado(false)
  }

  const nav = useMemo(() => [
    { id: 'limpiador' as const, texto: 'Limpiador', icono: <Eraser size={18} strokeWidth={1.75} /> },
    { id: 'programas' as const, texto: 'Programas', icono: <PackageX size={18} strokeWidth={1.75} /> },
    { id: 'registro' as const, texto: 'Registro', icono: <DatabaseZap size={18} strokeWidth={1.75} /> },
    { id: 'inicio' as const, texto: 'Inicio de Windows', icono: <Power size={18} strokeWidth={1.75} /> }
  ], [])

  return (
    <div className="app">
      <div className="barra-titulo"><img src={logo} alt="" /><b>Nitrit0 Limpieza</b></div>
      <nav className="lateral" aria-label="Secciones">
        {nav.map((n) => <button key={n.id} className="nav" disabled={ocupado && vista !== n.id} aria-current={vista === n.id ? 'page' : undefined} onClick={() => setVista(n.id)}>{n.icono}{n.texto}</button>)}
        <div className="pie-lateral">
          {admin !== null && <div className={`nota-admin ${admin ? '' : 'aviso'}`}>{admin ? 'Con permisos de administrador' : 'Sin administrador: no se pueden limpiar los temporales de Windows ni cambiar programas de todos los usuarios'}</div>}
        </div>
      </nav>
      <main className="principal">
        <ErrorBoundary>
          {vista === 'limpiador' && <Limpiador cats={cats} sel={sel} alSel={setSel} fase={fase} resultados={resultados} liberado={liberado} avisos={avisos} admin={admin === true} ocupado={ocupado} alAnalizar={() => void analizar()} alLimpiar={() => void limpiar()} alCancelar={() => void window.limpieza.cancelarAnalisis()} />}
          {vista === 'programas' && <Programas lista={programas} admin={admin === true} ocupado={ocupado} marcha={desMarcha} salida={salidaDes} alRecargar={() => void cargarProgramas()} alDesinstalar={(l) => void desinstalar(l)} />}
          {vista === 'registro' && <Registro restos={restos} salida={salidaReg} fase={faseReg} admin={admin === true} ocupado={ocupado} alAnalizar={() => void analizarRegistro()} alLimpiar={(m) => void limpiarRegistro(m)} />}
          {vista === 'inicio' && <Inicio items={items} arranque={arranque} admin={admin === true} ocupado={ocupado} alRecargar={() => void cargarInicio()} alCambiar={(it, on) => void cambiarInicio(it, on)} />}
        </ErrorBoundary>
      </main>
      <div className="pie-estado" role="status" aria-live="polite"><span>{pie}</span></div>
      <Confirmar abierto={cerrando} titulo="Hay una operación en marcha" texto="Si cierras ahora se interrumpe lo que se está haciendo. Lo que ya se borró no se recupera." textoOk="Cerrar de todos modos" textoNo="Seguir esperando" alAceptar={() => void window.limpieza.cerrar()} alCancelar={() => setCerrando(false)} />
    </div>
  )
}
