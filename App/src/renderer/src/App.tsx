import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react'
import { ScanSearch, PackageCheck, Hammer, Usb, Moon, Sun, Monitor, Loader, SquareTerminal, Scale, UserRound, CircleHelp, House, Eraser, ShieldCheck, Type, MonitorCheck, ClipboardCheck, Wrench, Heart } from 'lucide-react'
import Inicio from './paginas/Inicio'
import Tareas from './paginas/Tareas'
import Ajustes from './paginas/Ajustes'
import PanelEquipo from './componentes/PanelEquipo'
import { anotarHito } from './componentes/criatura'
import { resumenGuardado } from './equipo'
import Desplegable from './componentes/Desplegable'
import Pagina from './paginas/Pagina'
import EjecucionVista from './paginas/Ejecucion'
import Diagnostico from './paginas/Diagnostico'
import Equilibrio from './paginas/Equilibrio'
import Discos from './paginas/Discos'
import Prueba from './paginas/Prueba'
import Pruebas from './paginas/Pruebas'
import RevisionTotal from './paginas/RevisionTotal'
import { revisionActiva, useRevisionTotal } from './revision'
import Arreglar from './paginas/Arreglar'
import Combos from './paginas/Combos'
import { PerfilDialogo } from './componentes/PerfilUso'
import { AyudaDialogo, Confirmar, EntregaDialogo, ErrorBoundary, FichaDialogo, Solapas } from './componentes/Basicos'
import logo from './recursos/logo-nitrit0.png'
import { autoNuevo, fichaVacia, usaEjecutor, verbo, type EnCola, type Auto, type AutoDetectado, type AutoLinea, type AutoResultado, type Catalogo, type Dx, type EstadoPaso, type Ejecucion, type Elemento, type Eq, type IdPerfil, type EqAnalisis, type Estado, type Ficha, type PruebaPlan, type Ultima } from './tipos'

// Un icono de navegación por página; Lucide con un solo grosor de trazo para que se lean como un mismo juego.
const ICONO: Record<string, ReactNode> = {
  Comprobar: <ScanSearch size={18} strokeWidth={1.75} />, 'Preparar equipo': <PackageCheck size={18} strokeWidth={1.75} />,
  'Reparar y mantener': <Hammer size={18} strokeWidth={1.75} />, Kit: <Usb size={18} strokeWidth={1.75} />
}
const PAGINA_PROPIA = 'Nuestras herramientas'   // lo que hemos creado nosotros: entrada propia en el lateral
const SUBTITULO: Record<string, string> = {
  'Nuestras herramientas': 'Herramientas creadas para este kit: discos y copias, drivers, sistema. Las que cambian el equipo solo salen en el pack personal.',
  Comprobar: 'Mide y revisa el equipo sin cambiar nada: hardware, discos, memoria, pantalla, estrés y red.',
  'Preparar equipo': 'Configura, actualiza y deja el equipo listo para entregarlo.',
  'Reparar y mantener': 'Arregla fallos de Windows, limpia, copia datos y desinstala a fondo.',
  Kit: 'Historial, informes y estado del propio pendrive.'
}
const NOMBRE_TEMA = { oscuro: 'oscuro', claro: 'claro', sistema: 'igual que Windows' } as const
const slug = (p: string) => p.split(' ')[0].toLowerCase()
/** Lo que dice el ejecutor, en una frase que entienda cualquiera y diga qué hacer. */
const motivoLlano = (m: string) => /tiempo máximo/i.test(m) ? 'Esto tardó más de lo previsto y lo he cerrado.' : /código/i.test(m) ? 'Algo ha fallado por dentro. Puedes volver a intentarlo o copiar lo ocurrido para enseñárselo a un técnico.' : `No ha terminado: ${m.toLowerCase()}.`
const limpiar = (e: unknown) => String(e).replace(/^Error: (Error invoking remote method '[^']+': )?(Error: )?/, '')

interface Dialogo { titulo: string; texto: string; detalle?: string | null; textoOk: string; textoNo?: string; alAceptar: () => void }

export default function App() {
  const [vistaPedida, setVista] = useState<string>(() => location.hash.slice(1) || 'portada')
  const [catalogo, setCatalogo] = useState<Catalogo | null>(null)
  const [errorCatalogo, setErrorCatalogo] = useState('')
  const [estado, setEstado] = useState<Estado | null>(null)
  const [zoomSel, setZoomSel] = useState<number | null>(null)
  const [prueba, setPrueba] = useState<{ titulo: string; url: string } | null>(null)
  const volverDePrueba = useRef('portada')
  const [consulta, setConsulta] = useState('')
  const [pie, setPie] = useState('Listo')
  const [dialogo, setDialogo] = useState<Dialogo | null>(null)
  const [ejec, setEjec] = useState<Ejecucion | null>(null)
  const [cola, setCola] = useState<EnCola[]>([])   // herramientas esperando a que termine la que está en marcha
  const [dx, setDx] = useState<Dx | null>(null)
  const [eq, setEq] = useState<Eq | null>(null)
  const [auto, setAuto] = useState<Auto | null>(null)
  const [ficha, setFicha] = useState<Ficha>(fichaVacia)
  const [fichaAbierta, setFichaAbierta] = useState(false)
  const [entregaAbierta, setEntregaAbierta] = useState(false)
  const [tallerPendiente, setTallerPendiente] = useState(false)
  const [opcionPedida, setOpcionPedida] = useState<string | null>(null)   // opción de «Arreglar mi equipo» que se abre desde la portada
  const buscador = useRef<HTMLInputElement>(null)
  const ultimaPag = useRef('comprobar')    // última pestaña de Herramientas, para volver a ella desde el menú
  const previa = useRef('inicio')          // vista desde la que se lanzó el último script, para «Volver al kit»
  const perfilPedido = useRef('General')
  // Tema: oscuro, claro o «Igual que Windows» (sigue al sistema mientras la app está abierta)
  const [sistemaOscuro, setSistemaOscuro] = useState(() => matchMedia('(prefers-color-scheme: dark)').matches)
  useEffect(() => {
    const m = matchMedia('(prefers-color-scheme: dark)'), f = () => setSistemaOscuro(m.matches)
    m.addEventListener('change', f)
    return () => m.removeEventListener('change', f)
  }, [])
  const modoTema = estado?.tema ?? 'oscuro'
  const oscuro = modoTema === 'sistema' ? sistemaOscuro : modoTema === 'oscuro'
  // Modo sencillo: una sola pantalla de ayuda, sin menú. El técnico pasa al modo técnico con un botón y se recuerda.
  const simple = (estado?.modo ?? 'sencillo') === 'sencillo'
  // Modo sencillo: cuatro entradas (Inicio, Revisar mi equipo, Arreglarlo y Mi informe, que abre el informe de entrega)
  const VISTAS_SENCILLAS = ['inicio', 'revision', 'arreglar']
  const vista = simple ? (VISTAS_SENCILLAS.includes(vistaPedida) ? vistaPedida : 'arreglar') : vistaPedida
  const [reinicioPedido, setReinicioPedido] = useState(false)
  const [ayudaAbierta, setAyudaAbierta] = useState(false)
  const [perfilCerrado, setPerfilCerrado] = useState(false)
  const [ultima, setUltima] = useState<Ultima | null>(null)
  const opciones = useRef<{ actualizar: boolean; antivirus: boolean; cliente: string; enfoque: string } | null>(null)   // última revisión (se recupera de Ajustes al abrir)
  const accion = useRef<{ k: 'auto' } | { k: 'combo'; pasos: string[] } | null>(null)   // lo último que se lanzó, sea revisión o combo: es lo que repite «Volver a intentarlo»
  const esCombo = useRef(false)

  const cargar = useCallback(() => {
    setErrorCatalogo('')
    window.kit.catalogo().then((c: Catalogo) => setCatalogo(c)).catch((e: unknown) => setErrorCatalogo(limpiar(e)))
  }, [])
  useEffect(() => {
    cargar(); void window.kit.estado().then((e: Estado) => { setEstado(e); if (e.ultima && e.ultima.enfoque) { setUltima(e.ultima); opciones.current = { enfoque: e.ultima.enfoque, actualizar: e.ultima.actualizar, antivirus: e.ultima.antivirus, cliente: e.ultima.cliente } } })
    // Si la interfaz se vuelve a montar con un script vivo, se recupera en vez de dejarlo huérfano
    void window.kit.ejecucionActual().then((a: { id: string; titulo: string; limite: number; clase: string; t0: number; lineas: string[] } | null) => {
      if (!a) return
      setEjec({ id: a.id, titulo: a.titulo, limite: a.limite, lineas: a.lineas, aviso: null, informe: null, fin: null, t0: a.t0, clase: a.clase })
      void window.kit.cola().then((c: EnCola[]) => setCola(c))
      if (a.clase === 'script' || a.clase === 'auto') setVista('ejecucion')
    })
  }, [cargar])

  useEffect(() => { document.documentElement.dataset.tema = oscuro ? 'oscuro' : 'claro' }, [oscuro])

  // Al cambiar de pantalla el foco pasa al título: el teclado y los lectores de pantalla notan el cambio
  useEffect(() => { document.querySelector<HTMLElement>('main h1')?.focus() }, [vista, auto?.fase])   // también al pasar de fase en el modo sencillo, donde la vista no cambia

  // Eventos del script en marcha
  useEffect(() => {
    const quitar = [
      window.kit.alIniciar((v) => {
        setPie('Listo')   // el mensaje de la tarea anterior no se queda
        setEjec({ id: v.id, titulo: v.titulo, limite: v.limite, lineas: [], aviso: null, informe: null, fin: null, t0: Date.now(), clase: v.clase })
        if (v.clase === 'auto') { setAuto({ ...autoNuevo(), combo: esCombo.current }); esCombo.current = false; setPie('Listo'); setReinicioPedido(false); setVista((v) => (v === 'combos' ? 'combos' : 'arreglar')) }
        else if (v.clase === 'diagnostico') { setDx({ modo: 'Rapido', plan: [], resultados: {}, actual: null, fin: null }); if (!revisionActiva.actual) setVista('diagnostico') }   // dentro de la Revisión total el diagnóstico no cambia de pantalla
        else if (v.clase === 'equilibrio') { setEq({ perfil: perfilPedido.current, analisis: null, error: null, trabajando: true }); setVista('equilibrio') }
        else setVista((actual) => { if (actual !== 'ejecucion') previa.current = actual; return 'ejecucion' })
      }),
      window.kit.alLlegarLineas((ls) => setEjec((p) => (p ? { ...p, lineas: [...p.lineas, ...ls].slice(-4000) } : p))),
      window.kit.alProgreso((pr) => setEjec((p) => (p ? { ...p, progreso: pr } : p))),
      window.kit.alInforme((i) => setEjec((p) => (p ? { ...p, informe: i } : p))),
      window.kit.alDx((m) => {
        if (m.t === 'aviso') { setEjec((q) => (q ? { ...q, aviso: String(m.texto ?? '') } : q)); return }
        setDx((p) => {
        if (!p) return p
        const id = String(m.id ?? '')
        if (m.t === 'plan') return { ...p, modo: m.modo as Dx['modo'], plan: m.pruebas as PruebaPlan[] }
        if (m.t === 'inicio') return { ...p, actual: id }
        if (m.t === 'fin') return { ...p, actual: null, resultados: { ...p.resultados, [id]: { estado: m.estado as never, resumen: String(m.resumen ?? ''), detalle: String(m.detalle ?? ''), seg: Number(m.seg ?? 0) } } }
        if (m.t === 'terminado') return { ...p, actual: null, fin: { seg: Number(m.seg), historial: (m.historial as string) ?? null, comparacion: (m.comparacion as NonNullable<Dx['fin']>['comparacion']) ?? null, fallos: Number(m.fallos), avisos: Number(m.avisos), interrumpido: m.interrumpido === true, motivo: m.interrumpido === true ? 'No se completó' : undefined } }
        return p
      }) }),
      window.kit.alAuto((m) => setAuto((p) => {
        if (!p) return p
        const t = String(m.t ?? '')
        if (t === 'fase') return { ...p, fase: m.fase === 'verificando' ? 'verificando' : 'analisis', hechas: 0, total: 0, actual: '' }
        if (t === 'analisis') return { ...p, hechas: Number(m.hechas ?? 0), total: Number(m.total ?? 0), actual: String(m.actual ?? '') }
        if (t === 'plan') {
          const pasos = (m.pasos as { id: string; titulo: string; que: string; min: number }[] | undefined) ?? []
          return { ...p, fase: m.espera === true ? 'confirmar' : 'arreglando', revisadas: Number(m.revisadas ?? 0), detectados: (m.detectados as AutoDetectado[] | undefined) ?? [], pasos: pasos.map((x) => ({ ...x, estado: 'espera' as EstadoPaso, texto: '', lineas: [], desde: null, silencio: 0 })) }
        }
        if (t === 'paso') {
          const id = String(m.id ?? '')
          return { ...p, pasos: p.pasos.map((x) => (x.id !== id ? x : m.estado === 'inicio'
            ? { ...x, estado: 'activo' as EstadoPaso, desde: Date.now(), texto: '', silencio: 0 }
            : { ...x, estado: m.resultado as EstadoPaso, seg: Number(m.seg ?? 0), texto: String(m.texto ?? ''), lineas: (m.lineas as AutoLinea[] | undefined) ?? [], desde: null })) }
        }
        if (t === 'estado') {
          const id = String(m.id ?? '')
          return { ...p, pasos: p.pasos.map((x) => (x.id === id && x.estado === 'activo' ? { ...x, texto: String(m.texto ?? '') || x.texto, silencio: Number(m.silencio ?? 0) } : x)) }
        }
        if (t === 'fin') return { ...p, fase: 'fin', resultado: m.resultado as unknown as AutoResultado }
        if (t === 'error') return { ...p, fase: 'error', error: String(m.texto ?? 'Algo salió mal.') }
        return p
      })),
      window.kit.alEq((m) => setEq((p) => (p ? { ...p, analisis: m as unknown as EqAnalisis, trabajando: false, error: null } : p))),
      window.kit.alAvisar((a) => setEjec((p) => (p ? { ...p, aviso: a } : p))),
      window.kit.alCola((c) => setCola(c)),
      window.kit.alTerminar((f) => {
        if (f.id === 'perfil') void window.kit.estado().then((e: Estado) => setEstado(e))   // el perfil activo cambia solo si el script terminó bien
        setEjec((p) => (p ? { ...p, fin: { motivo: f.motivo, seg: f.seg, correcto: f.correcto, cancelado: f.cancelado, registro: f.registro } } : p))
        setPie(`${f.titulo}: ${f.motivo.toLowerCase()}.`)
        // Si el script se detuvo sin entregar su resultado final, la página lo dice en vez de quedarse esperando
        setDx((p) => {
          if (!p || p.fin || f.id !== 'diagnostico') return p
          const r = Object.values(p.resultados)
          return { ...p, actual: null, fin: { seg: f.seg, historial: null, comparacion: null, fallos: r.filter((x) => x.estado === 'Fallo').length, avisos: r.filter((x) => x.estado === 'Aviso').length, interrumpido: true, motivo: f.motivo } }
        })
        // Si el script se paró sin entregar su informe (cancelado, tiempo máximo, error), la pantalla lo dice en vez de quedarse esperando
        setAuto((p) => (p && f.id === 'auto' && p.fase !== 'fin' && p.fase !== 'error' ? { ...p, fase: 'error', cancelado: /cancelado/i.test(f.motivo), error: /cancelado/i.test(f.motivo) ? 'Has parado lo que estaba en marcha.' : motivoLlano(f.motivo) } : p))
        setEq((p) => (p && p.trabajando && f.id === 'equilibrio' ? { ...p, trabajando: false, error: `El análisis no terminó: ${f.motivo.toLowerCase()}.` } : p))
      })
    ]
    return () => quitar.forEach((q) => q())
  }, [])

  // Ctrl+F lleva a la búsqueda del kit
  const paginas = catalogo ? Object.keys(catalogo.paginas) : []
  useEffect(() => {
    const f = (ev: KeyboardEvent) => {
      if (!(ev.ctrlKey && ev.key.toLowerCase() === 'f') || !paginas.length || simple) return
      ev.preventDefault()
      setVista((v) => (paginas.some((p) => slug(p) === v) ? v : slug(paginas[0])))
      setTimeout(() => buscador.current?.focus(), 0)
    }
    window.addEventListener('keydown', f)
    return () => window.removeEventListener('keydown', f)
  }, [paginas, simple])

  const enMarcha = !!ejec && !ejec.fin
  // Con un script normal en marcha, otro script se pone en cola en vez de estar apagado (diagnóstico, cuello de botella y revisión automática no admiten cola)
  const puedeEncolar = enMarcha && ejec?.clase === 'script'
  const elementos = catalogo?.elementos ?? []
  const permitidos = elementos.filter((e) => !(estado?.ocultarPeligro && e.peligro && !e.publicoOk))   // para pantallas que usan también lo «oculto» de las listas (el botón del Asistente guiado)
  const visibles = elementos.filter((e) => !e.oculta && !(estado?.ocultarPeligro && e.peligro && !e.publicoOk))   // pack público: sin las herramientas marcadas como peligrosas

  const ejecutar = async (e: Elemento) => {
    if (e.tipo === 'html') {   // las pruebas se ven dentro de la app, no en el navegador
      const p = await window.kit.pruebaUrl(e.id)
      if (p.ok && p.url) { volverDePrueba.current = vista; setPrueba({ titulo: p.titulo ?? e.titulo, url: p.url }); setVista('prueba') } else setPie(p.mensaje)
      return
    }
    const r = await window.kit.lanzar(e.id)
    setPie(r.mensaje)
  }
  // Al ocultar la ventana (cierre a la bandeja) la búsqueda se vacía: al volver a abrirla sale en blanco
  useEffect(() => {
    const alCambiar = () => { if (document.visibilityState === 'hidden') setConsulta('') }
    document.addEventListener('visibilitychange', alCambiar)
    return () => document.removeEventListener('visibilitychange', alCambiar)
  }, [])
  // Tras la «Ficha de drivers», un botón para instalar de una vez los que faltan (solo si esa herramienta está disponible en este pack)
  const siguienteTras = (id: string): { texto: string; accion: () => void } | null => {
    const el = id === 'Ficha_Drivers.ps1' ? visibles.find((x) => x.id === 'Instalar_Drivers_Faltantes.ps1' && x.disponible && x.soportado) : undefined
    return el ? { texto: 'Instalar los drivers que faltan', accion: () => lanzar(el) } : null
  }
  const lanzar = (e: Elemento) => {
    if (e.peligro) setDialogo({ titulo: e.titulo, texto: e.descripcion, detalle: e.ayuda, textoOk: puedeEncolar && usaEjecutor(e) ? 'Poner en cola de todos modos' : `${verbo(e)} de todos modos`, alAceptar: () => { setDialogo(null); void ejecutar(e) } })
    else void ejecutar(e)
  }
  const cancelar = () => setDialogo({ titulo: 'Cancelar la ejecución', texto: 'Se cerrará el script y los procesos que haya lanzado. Lo que ya cambió no se deshace solo.', textoOk: 'Sí, cancelar', textoNo: 'Seguir ejecutando', alAceptar: () => { setDialogo(null); void window.kit.cancelar() } })

  const empezarDx = async (modo: 'Rapido' | 'Completo', fichaUso: Ficha = ficha) => {
    const r = await window.kit.diagnostico({ modo, ficha: { ...fichaUso } })
    if (!r.ok) setPie(r.mensaje)
  }
  const rt = useRevisionTotal({ dx, elementos: visibles, empezarDx })
  const detenerDx = () => setDialogo({ titulo: 'Detener el diagnóstico', texto: 'Se pararán las pruebas en curso. Lo hecho hasta ahora no se guarda en el historial.', textoOk: 'Sí, detener', textoNo: 'Seguir con el diagnóstico', alAceptar: () => { setDialogo(null); void window.kit.cancelar() } })
  const analizarEq = async (perfil: string) => {
    // El estado anterior solo se limpia cuando el proceso confirma que arrancó (evento de inicio): si no acepta, se conserva el análisis que ya había
    perfilPedido.current = perfil
    const r = await window.kit.equilibrio(perfil)
    if (!r.ok) setPie(r.mensaje)
  }
  const empezarAuto = async (o: { actualizar: boolean; antivirus: boolean; cliente: string; enfoque: string }) => {
    opciones.current = o; accion.current = { k: 'auto' }; esCombo.current = false
    setFicha((f) => ({ ...f, Cliente: o.cliente.trim() || f.Cliente }))
    const r = await window.kit.revisionAuto(o)
    if (!r.ok) setPie(r.mensaje)
  }
  const detenerAuto = () => setDialogo({ titulo: 'Parar lo que está en marcha', texto: 'Se paran los arreglos en curso. Lo que ya se haya cambiado se queda, y se puede deshacer con «Deshacer los últimos cambios».', textoOk: 'Sí, detener', textoNo: 'Seguir', alAceptar: () => { setDialogo(null); void window.kit.cancelar() } })
  const confirmarPlan = async (ids: string[]) => {
    const r = await window.kit.autoConfirmar(ids)
    if (!r.ok) { setPie(r.mensaje); return }
    setAuto((p) => (p && p.fase === 'confirmar' ? { ...p, fase: 'arreglando' } : p))
  }
  const pedir = (d: { titulo: string; texto: string; ok: string; no?: string; alAceptar: () => void }) =>
    setDialogo({ titulo: d.titulo, texto: d.texto, textoOk: d.ok, textoNo: d.no, alAceptar: () => { setDialogo(null); d.alAceptar() } })
  const repetirRevision = () => { if (opciones.current) void empezarAuto(opciones.current) }
  const repetir = () => { const a = accion.current; if (a?.k === 'combo') void empezarCombo(a.pasos); else repetirRevision() }
  const deshacer = () => pedir({ titulo: 'Deshacer los últimos cambios', texto: 'Devuelve los ajustes cambiados a como estaban antes. No recupera los archivos temporales que se borraron.', ok: 'Sí, deshacer', no: 'Ahora no', alAceptar: () => void empezarCombo(['deshacer']) })
  useEffect(() => {
    const r = auto?.fase === 'fin' ? auto.resultado : null
    if (r && r.modo !== 'combo' && !r.soloMirar && !auto?.cancelado && r.equipo) anotarHito(r.equipo, 'arreglado')
    if (r && r.modo !== 'combo' && opciones.current) { const u = { titular: r.titular, hora: Date.now(), enfoque: opciones.current.enfoque, actualizar: opciones.current.actualizar, antivirus: opciones.current.antivirus, cliente: opciones.current.cliente }; setUltima(u); void window.kit.guardarUltima(u) }
  }, [auto?.fase, auto?.resultado])
  // Atajos: F1 ayuda en cualquier modo; Ctrl+1..4 saltan entre espacios en el modo técnico
  useEffect(() => {
    const f = (ev: KeyboardEvent) => {
      if (ev.key === 'F1') { ev.preventDefault(); setAyudaAbierta(true); return }
      if (!ev.ctrlKey || simple) return
      const mapa: Record<string, string> = { '1': 'portada', '2': 'inicio', '3': 'diagnostico', '4': ultimaPag.current }   // «Arreglar mi equipo» es solo del modo sencillo: el técnico no lleva guía
      if (mapa[ev.key]) { ev.preventDefault(); setVista(mapa[ev.key]) }
    }
    window.addEventListener('keydown', f)
    return () => window.removeEventListener('keydown', f)
  }, [simple])
  const empezarCombo = async (pasos: string[]) => {
    accion.current = { k: 'combo', pasos }; esCombo.current = true
    const r = await window.kit.combo({ pasos, cliente: ficha.Cliente })
    if (!r.ok) setPie(r.mensaje)
  }
  const elegirPerfil = async (id: IdPerfil) => {
    setPerfilCerrado(true); void window.kit.perfilPreguntado()
    const r = await window.kit.perfil(id)
    setPie(r.mensaje)
  }
  const cerrarPerfil = () => { setPerfilCerrado(true); void window.kit.perfilPreguntado() }
  const cambiarArranque = async (on: boolean) => {
    const r = await window.kit.arranque(on)
    setPie(r.mensaje)
    void window.kit.estado().then((e: Estado) => setEstado(e))
  }
  const refrescarEstado = () => { void window.kit.estado().then((e: Estado) => setEstado(e)) }
  const hacerInstalacion = async () => { setPie('Instalando…'); const r = await window.kit.instalar(); setPie(r.mensaje); refrescarEstado() }
  const instalar = () => pedir({ titulo: 'Instalar en este equipo', texto: 'Se copia la app (unos 110 MB, sin las herramientas de terceros) a Archivos de programa, se crea el acceso en el menú Inicio y se activa el arranque con Windows con el icono junto al reloj. Se puede quitar desde aquí.', ok: 'Instalar', no: 'Ahora no', alAceptar: () => void hacerInstalacion() })
  const quitarInstalacion = () => pedir({ titulo: 'Quitar la instalación', texto: 'Se borra la copia de Archivos de programa, el acceso del menú Inicio y el arranque con Windows. El pendrive o la carpeta de donde venía no se toca.', ok: 'Quitar', no: 'Ahora no', alAceptar: () => void window.kit.quitarInstalacion().then((r: { mensaje: string }) => { setPie(r.mensaje); refrescarEstado() }) })
  const liberarMemoria = async () => { setPie('Liberando memoria…'); const r = await window.kit.memoria(); setPie(r.mensaje) }
  const cambiarMemoriaAuto = async (on: boolean) => { await window.kit.memoriaAuto(on); refrescarEstado() }
  const informeEntrega = async (d: { cliente: string; notas: string }) => {
    setEntregaAbierta(false)
    const r = await window.kit.informeEntrega(d)
    setPie(r.mensaje); const eq = resumenGuardado()?.equipo; if (r.ok && eq) anotarHito(eq, 'entregado')
  }

  const favoritas = estado?.favoritos ?? []
  const alFavorita = (titulo: string) => {
    const nuevas = favoritas.includes(titulo) ? favoritas.filter((t) => t !== titulo) : [...favoritas, titulo]
    setEstado((s) => (s ? { ...s, favoritos: nuevas } : s))
    void window.kit.favoritos(nuevas)
  }
  const cambiarModo = () => {
    const m = simple ? 'tecnico' : 'sencillo'
    setEstado((s) => (s ? { ...s, modo: m } : s))
    void window.kit.modo(m)
  }
  const reiniciar = () => setDialogo({ titulo: 'Reiniciar el ordenador', texto: 'El ordenador se reiniciará en 30 segundos. Guarda antes lo que tengas abierto.', textoOk: 'Sí, reiniciar', textoNo: 'Ahora no', alAceptar: () => { setDialogo(null); void window.kit.reiniciar().then((r: { ok: boolean; mensaje: string }) => { setPie(r.mensaje); if (r.ok) setReinicioPedido(true) }) } })
  const cancelarReinicio = () => { void window.kit.cancelarReinicio().then((r: { mensaje: string }) => { setPie(r.mensaje); setReinicioPedido(false) }) }
  const cambiarTema = (t: 'oscuro' | 'claro' | 'sistema') => {
    setEstado((s) => (s ? { ...s, tema: t } : s))
    void window.kit.tema(t)
  }
  const siguienteTema = () => cambiarTema(modoTema === 'oscuro' ? 'claro' : modoTema === 'claro' ? 'sistema' : 'oscuro')   // en el modo sencillo, un solo enlace que va pasando por los tres

  const nav = (id: string, texto: string, icono: ReactNode, cuenta?: number) => (
    <button className="nav" aria-current={vista === id ? 'page' : undefined} onClick={() => setVista(id)}>
      {icono}{texto}{cuenta !== undefined && <span className="cuenta num">{cuenta}</span>}
    </button>
  )

  const paginaActual = paginas.find((p) => slug(p) === vista)
  useEffect(() => { if (vista !== 'arreglar') setOpcionPedida(null) }, [vista])
  const dxCorriendo = enMarcha && ejec?.id === 'diagnostico'
  // Siete secciones; cada vista y cada página del catálogo cuelga de una sola (antes había dos menús paralelos con lo mismo repetido)
  const IDS_REVISAR = ['inicio', 'revision', 'diagnostico', 'discos', 'equilibrio']
  // Menú por recorrido: Revisar, Probar, Arreglar (reparar y limpiar), Entregar (abre el informe de entrega)
  const PAGS_LIMPIAR = ['Preparar equipo', 'Reparar y mantener']
  const IDS_ARREGLAR = ['arreglar', 'combos', ...PAGS_LIMPIAR.map(slug), 'ajustes']
  const PAGS_HERR = ['Comprobar', PAGINA_PROPIA]
  const IDS_HERR = PAGS_HERR.map(slug)
  const enRevisar = IDS_REVISAR.includes(vista)
  const enArreglar = IDS_ARREGLAR.includes(vista)
  const enHerr = IDS_HERR.includes(vista)
  const tabPag = (p: string) => ({ id: slug(p), texto: p, cuenta: visibles.filter((e) => e.pagina === p).length })
  const irA = (ids: string[], porDefecto: string) => () => setVista(ids.includes(vista) ? vista : ids.includes(ultimaPag.current) ? ultimaPag.current : porDefecto)
  const panelAuto = catalogo && (
    <Arreglar auto={auto} simple={simple} reinicioPedido={reinicioPedido} alReiniciar={reiniciar} alCancelarReinicio={cancelarReinicio} ocupado={enMarcha && ejec?.id !== 'auto'} cliente={ficha.Cliente} soluciones={catalogo.soluciones} elementos={visibles} informe={ejec?.id === 'auto' ? ejec.informe : null}
      alEmpezar={(o) => void empezarAuto(o)} alSaltar={() => void window.kit.autoSaltar()} alConfirmarPlan={(ids) => void confirmarPlan(ids)} alPedir={pedir} ultima={ultima} puedeRepetir={!!accion.current} alRepetir={repetir} alRepetirRevision={repetirRevision} enfoque={opciones.current?.enfoque} alDeshacer={deshacer} lineas={ejec?.lineas ?? []} alDetener={detenerAuto} alCancelarSinPreguntar={() => void window.kit.cancelar()} alNueva={() => { setAuto(null); setReinicioPedido(false) }} alLanzar={lanzar} opcionInicial={opcionPedida} />
  )

  return (
    <div className={`app ${simple ? 'simple' : ''}`}>
      <div className="barra-titulo"><img src={logo} alt="" /><b>Nitrit0 Kit</b></div>
      {!simple && <nav className="lateral" aria-label="Secciones">
        {nav('portada', 'Inicio', <House size={18} strokeWidth={1.75} />)}
        <hr />
        <button className="nav" aria-current={enRevisar ? 'page' : undefined} onClick={irA(IDS_REVISAR, 'inicio')}><ClipboardCheck size={18} strokeWidth={1.75} />Revisar</button>
        {nav('pruebas', 'Probar', <MonitorCheck size={18} strokeWidth={1.75} />)}
        <button className="nav" aria-current={enArreglar ? 'page' : undefined} onClick={irA(IDS_ARREGLAR, 'arreglar')}><Wrench size={18} strokeWidth={1.75} />Arreglar</button>
        <button className="nav" onClick={() => setEntregaAbierta(true)}><Eraser size={18} strokeWidth={1.75} />Entregar</button>
        <button className="nav" aria-current={enHerr ? 'page' : undefined} onClick={irA(IDS_HERR, 'comprobar')}><Hammer size={18} strokeWidth={1.75} />Herramientas<span className="cuenta num">{visibles.filter((e) => PAGS_HERR.includes(e.pagina)).length}</span></button>
        {paginas.includes('Kit') && nav(slug('Kit'), 'Kit', <Usb size={18} strokeWidth={1.75} />)}
        {ejec && (<><hr />{nav('ejecucion', enMarcha ? (cola.length ? `En marcha · ${cola.length} en cola` : 'En marcha') : 'Última ejecución', enMarcha ? <Loader size={18} strokeWidth={1.75} /> : <SquareTerminal size={18} strokeWidth={1.75} />)}</>)}
        <div className="pie-lateral">
          <PanelEquipo admin={estado?.admin} alVerEstado={() => setVista('inicio')} />
          {estado && <div className={`nota-admin ${estado.admin ? '' : 'aviso'}`}>{estado.admin ? 'Con permisos de administrador' : 'Sin administrador: algunas herramientas pedirán permiso'}</div>}
          {estado && !estado.admin && <button className="nav" disabled={enMarcha} onClick={() => { setPie('Pidiendo permiso de administrador…'); window.kit.elevar().then((r) => setPie(r.mensaje)).catch(() => setPie('No se pudo pedir el permiso de administrador.')) }}><ShieldCheck size={18} strokeWidth={1.75} />Elevar permisos</button>}
          <button className="nav" onClick={() => setAyudaAbierta(true)}><CircleHelp size={18} strokeWidth={1.75} />Ayuda<span className="cuenta num">F1</span></button>
          <button className="nav" onClick={cambiarModo}><UserRound size={18} strokeWidth={1.75} />Modo sencillo</button>
          {estado?.ocultarPeligro && <button className="nav" onClick={() => void window.kit.donar()}><Heart size={18} strokeWidth={1.75} />Apoyar el proyecto</button>}
          <Desplegable lateral etiqueta="Tema de la aplicación" valor={modoTema} alElegir={(k) => cambiarTema(k as 'oscuro' | 'claro' | 'sistema')}
            icono={modoTema === 'sistema' ? <Monitor size={18} strokeWidth={1.75} /> : oscuro ? <Moon size={18} strokeWidth={1.75} /> : <Sun size={18} strokeWidth={1.75} />}
            textoBoton={`Tema: ${NOMBRE_TEMA[modoTema]}`} opciones={[{ k: 'oscuro', t: 'Oscuro' }, { k: 'claro', t: 'Claro' }, { k: 'sistema', t: 'Igual que Windows' }]} />
          <Desplegable lateral etiqueta="Tamaño de letra" valor={String(zoomSel ?? estado?.zoom ?? 1)} icono={<Type size={18} strokeWidth={1.75} />} textoBoton={`Letra: ${Math.round((zoomSel ?? estado?.zoom ?? 1) * 100)} %`}
            alElegir={(k) => { setZoomSel(Number(k)); void window.kit.zoom(Number(k)) }}
            opciones={[{ k: '1', t: 'Normal (100 %)' }, { k: '1.15', t: 'Grande (115 %)' }, { k: '1.3', t: 'Mayor (130 %)' }, { k: '1.5', t: 'Máximo (150 %)' }]} />
        </div>
      </nav>}
      <main className="principal">
        {ejec?.aviso && enMarcha && <div className="aviso-banda" role="alert">{ejec.aviso}</div>}
        <ErrorBoundary>
        {errorCatalogo && <div className="pagina"><h1 tabIndex={-1}>No se pudo cargar el catálogo</h1><p className="vacio">{errorCatalogo}</p><div><button className="boton" onClick={cargar}>Volver a intentarlo</button></div></div>}
        {!errorCatalogo && !catalogo && <div className="pagina cargando" role="status"><div className="cargando-logo" aria-hidden="true"><img src={logo} alt="" /></div><h1 tabIndex={-1}>Cargando el kit…</h1><p className="vacio">Un momento, preparo las herramientas.</p></div>}
        {/* Las solapas van siempre arriba, antes del contenido (antes las de «Estado del equipo» quedaban debajo de la pantalla) */}
        {catalogo && simple && <Solapas etiqueta="Qué quieres hacer" activo={vista} alCambiar={(id) => { if (id === 'informe') { setEntregaAbierta(true); return } setVista(id) }}
          items={[{ id: 'inicio', texto: 'Inicio' }, { id: 'revision', texto: 'Revisar mi equipo' }, { id: 'arreglar', texto: 'Arreglarlo' }, { id: 'informe', texto: 'Mi informe' }]} />}
        {catalogo && !simple && enRevisar && <Solapas etiqueta="Revisar" activo={vista}
          alCambiar={(id) => { if (id === 'antivirus') { window.kit.abrirAntivirus().then((r) => setPie(r.mensaje)).catch(() => setPie('No se pudo abrir el antivirus.')); return } setVista(id) }}
          items={[{ id: 'inicio', texto: 'Resumen' }, { id: 'revision', texto: 'Revisión total' }, { id: 'diagnostico', texto: 'Diagnóstico' }, { id: 'discos', texto: 'Discos' }, { id: 'equilibrio', texto: 'Qué lo frena' }, ...(estado?.antivirus ? [{ id: 'antivirus', texto: 'Antivirus' }] : [])]} />}
        {catalogo && enArreglar && <Solapas etiqueta="Arreglar" activo={vista} alCambiar={(id) => { if (id !== 'arreglar' && id !== 'combos') ultimaPag.current = id; setVista(id) }}
          items={[{ id: 'arreglar', texto: 'Por síntoma' }, { id: 'combos', texto: 'Combos' }, ...PAGS_LIMPIAR.filter((p) => paginas.includes(p)).map(tabPag), { id: 'ajustes', texto: 'Ajustes de Windows' }]} />}
        {catalogo && enHerr && <Solapas etiqueta="Herramientas" activo={vista} alCambiar={(id) => { ultimaPag.current = id; setVista(id) }}
          items={PAGS_HERR.filter((p) => paginas.includes(p)).map(tabPag)} />}
        {catalogo && vista === 'portada' && (
          <Tareas instalada={estado?.instalada === true} hayInstalacion={estado?.hayInstalacion === true} puedeInstalar={estado?.puedeInstalar === true} memoriaAuto={estado?.memoriaAuto === true} alInstalar={instalar} alQuitarInstalacion={quitarInstalacion} alMemoria={() => void liberarMemoria()} alMemoriaAuto={(on) => void cambiarMemoriaAuto(on)} perfil={estado?.perfil ?? null} arranque={estado?.arranque === true} alPerfil={(id) => void elegirPerfil(id)} alArranque={(on) => void cambiarArranque(on)} elementos={visibles} favoritas={favoritas} ocupado={enMarcha} totalHerramientas={visibles.length}
            alLanzar={lanzar} alDiagnostico={() => setVista('diagnostico')} alCombos={() => setVista('combos')} alAjustes={() => { ultimaPag.current = 'ajustes'; setVista('ajustes') }} alHerramientas={() => setVista(ultimaPag.current)} alEntrega={() => setEntregaAbierta(true)} />
        )}
        {catalogo && vista === 'inicio' && (
          <Inicio elementos={permitidos} favoritas={favoritas} alLanzar={lanzar} ocupado={enMarcha} encolar={puedeEncolar}
            alDiagnostico={() => { setVista('diagnostico'); void empezarDx('Rapido') }} alEquilibrio={() => setVista('equilibrio')} />
        )}
        {catalogo && vista === 'revision' && (
          <RevisionTotal rev={rt.rev} dx={dx} manual={visibles.filter((e) => e.tipo === 'html' && e.soportado && e.disponible && e.titulo !== 'Placa de vídeo (GPU)' && e.titulo !== 'Prueba de procesador')} elementos={visibles} ocupado={enMarcha && !rt.rev}
            alIniciar={rt.iniciar} alDetener={rt.detener} alMarcar={rt.marcar} alAbrir={(e) => void ejecutar(e)} alTerminarManual={rt.terminarManual} alReiniciar={rt.reiniciar}
            alDetalle={() => setVista('diagnostico')} alInforme={() => setEntregaAbierta(true)} alLanzar={lanzar} />
        )}
        {catalogo && vista === 'pruebas' && <Pruebas elementos={visibles} alAbrir={(e) => void ejecutar(e)} alHerramientas={() => setVista(ultimaPag.current)} />}
        {catalogo && vista === 'prueba' && prueba && <Prueba titulo={prueba.titulo} url={prueba.url} alVolver={() => setVista(volverDePrueba.current === 'prueba' ? 'portada' : volverDePrueba.current)} />}
        {catalogo && vista === 'discos' && <Discos admin={estado?.admin} />}
        {catalogo && vista === 'arreglar' && panelAuto}
        {catalogo && vista === 'combos' && (auto ? panelAuto : <Combos ocupado={enMarcha} alPedir={pedir} alEjecutar={(p) => void empezarCombo(p)} />)}
        {catalogo && vista === 'diagnostico' && (
          <Diagnostico dx={dx} funcionando={dxCorriendo} ocupado={enMarcha} ficha={ficha} soluciones={catalogo.soluciones} elementos={visibles}
            alFicha={() => setFichaAbierta(true)} alTaller={() => { setTallerPendiente(true); setFichaAbierta(true) }} alEmpezar={(m) => void empezarDx(m)} alCancelar={detenerDx} alLanzar={lanzar} alInformeEntrega={() => setEntregaAbierta(true)} />
        )}
        {catalogo && vista === 'equilibrio' && <Equilibrio eq={eq} ocupado={enMarcha} alAnalizar={(p) => void analizarEq(p)} />}
        {catalogo && paginaActual && (
          <Pagina key={paginaActual} titulo={paginaActual} subtitulo={SUBTITULO[paginaActual] ?? ''} grupos={catalogo.paginas[paginaActual]} elementos={visibles} favoritas={favoritas}
            ocupado={enMarcha && !puedeEncolar} consulta={consulta} alConsulta={setConsulta} buscadorRef={buscador} alFavorita={alFavorita} alLanzar={lanzar} />
        )}
        {catalogo && vista === 'ajustes' && <Ajustes />}
        {catalogo && vista === 'ejecucion' && (ejec
          ? <EjecucionVista e={ejec} alCancelar={cancelar} alVolver={() => setVista(previa.current)} alMensaje={setPie} siguiente={siguienteTras(ejec.id)} cola={cola} detallesAbiertos={estado?.modo === 'tecnico'} alQuitarDeCola={(id) => void window.kit.colaQuitar(id)} alVaciarCola={() => void window.kit.colaVaciar()} />
          : <div className="pagina"><p className="vacio">No hay ninguna ejecución reciente.</p></div>)}
        </ErrorBoundary>
      </main>
      <div className="pie-estado" role="status" aria-live="polite"><span>{pie}</span>{estado && (simple ? <><button className="enlace al-final" onClick={() => setAyudaAbierta(true)}>Ayuda</button>{estado.ocultarPeligro && <button className="enlace" onClick={() => void window.kit.donar()}>Apoyar el proyecto</button>}<button className="enlace" onClick={siguienteTema}>Tema: {NOMBRE_TEMA[modoTema]}</button><button className="enlace" onClick={cambiarModo}>Modo técnico</button></> : <span className="num al-final">{estado.kit}</span>)}</div>
      <Confirmar abierto={!!dialogo} titulo={dialogo?.titulo ?? ''} texto={dialogo?.texto ?? ''} detalle={dialogo?.detalle} textoOk={dialogo?.textoOk ?? ''} textoNo={dialogo?.textoNo}
        alAceptar={() => dialogo?.alAceptar()} alCancelar={() => setDialogo(null)} />
      <PerfilDialogo abierto={!!estado && !simple && !estado.preguntado && !perfilCerrado && !!catalogo && !enMarcha} alElegir={(id) => void elegirPerfil(id)} alCerrar={cerrarPerfil} />
      <AyudaDialogo abierto={ayudaAbierta} tecnico={!simple} alCerrar={() => setAyudaAbierta(false)} />
      <EntregaDialogo abierto={entregaAbierta} clienteInicial={ficha.Cliente} alGenerar={(d) => void informeEntrega(d)} alCancelar={() => setEntregaAbierta(false)} />
      {rt.marco}
      <FichaDialogo abierto={fichaAbierta} ficha={ficha} alGuardar={(f) => { setFicha(f); setFichaAbierta(false); if (tallerPendiente) { setTallerPendiente(false); void empezarDx('Rapido', f) } }} alCancelar={() => { setFichaAbierta(false); setTallerPendiente(false) }} />
    </div>
  )
}
