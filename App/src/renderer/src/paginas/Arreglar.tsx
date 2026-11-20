import { useEffect, useState, type ReactNode } from 'react'
import { Check, ChevronRight, CircleCheck, Gauge, HardDrive, HeartPulse, ShieldCheck, TriangleAlert, Wifi } from 'lucide-react'
import { Medidor } from '../componentes/Basicos'
import { revisiones, type Revision } from './Inicio'
import { usaEjecutor, verbo, type Auto, type AutoResultado, type Elemento, type EstadoPaso, type PasoVivo, type Resumen, type Tono, type Ultima, type Vivo } from '../tipos'

interface Props {
  auto: Auto | null; ocupado: boolean; simple: boolean; cliente: string; reinicioPedido: boolean
  soluciones: Record<string, string[]>; elementos: Elemento[]; informe: { ruta: string; html: string } | null
  alEmpezar: (o: { actualizar: boolean; antivirus: boolean; cliente: string; enfoque: string }) => void
  alSaltar: () => void; alDetener: () => void; alNueva: () => void; alLanzar: (e: Elemento) => void
  alReiniciar: () => void; alCancelarReinicio: () => void
  alConfirmarPlan: (ids: string[]) => void
  alCancelarSinPreguntar: () => void
  ultima: Ultima | null; puedeRepetir: boolean; alRepetir: () => void; alRepetirRevision: () => void; enfoque?: string; alDeshacer: () => void; lineas: string[]
  alPedir: (d: { titulo: string; texto: string; ok: string; no?: string; alAceptar: () => void }) => void
  opcionInicial?: string | null   // opción que viene ya abierta (desde la portada del modo técnico)
}

/** Lo que la persona puede elegir, en sus palabras. Cada opción abre debajo lo que se va a hacer y el botón de empezar. */
const PROBLEMAS: { id: string; titulo: string; texto: string; hace: string[]; tiempo: string; nota?: string; confirmar?: string; icono: ReactNode }[] = [
  { id: 'todo', titulo: 'No sé qué le pasa', texto: 'Que lo revise todo y me diga qué encuentra.', icono: <HeartPulse size={28} strokeWidth={1.75} />,
    hace: ['Reviso todo lo importante: discos, memoria, Internet, protección y Windows.', 'Te enseño lo que encuentro y qué propongo hacer. Tú decides qué se hace.', 'Al final te cuento qué se ha cambiado.'], tiempo: 'Suele tardar unos minutos.' },
  { id: 'lento', titulo: 'Va lento', texto: 'Tarda en encender, en abrir cosas o se queda pensando.', icono: <Gauge size={28} strokeWidth={1.75} />,
    hace: ['Miro la memoria, el disco y los programas que arrancan al encender.', 'Borro archivos temporales que sobran y libero memoria.'], tiempo: 'Suele tardar uno o dos minutos.' },
  { id: 'internet', titulo: 'No tengo Internet', texto: 'No carga ninguna página o se corta a ratos.', icono: <Wifi size={28} strokeWidth={1.75} />,
    hace: ['Compruebo si hay conexión y si responde el router.', 'Si hace falta, restablezco la configuración de red.'], tiempo: 'Suele tardar un minuto.',
    nota: 'La conexión puede cortarse unos segundos mientras la arreglo.', confirmar: 'Si hay que arreglar la conexión, se cortará unos segundos. ¿Empezamos?' },
  { id: 'avisos', titulo: 'Salen avisos o errores', texto: 'Pantallas azules, se apaga solo o salen mensajes raros.', icono: <TriangleAlert size={28} strokeWidth={1.75} />,
    hace: ['Busco errores graves y apagados inesperados.', 'Compruebo el disco y los archivos de Windows, y reparo los que estén dañados.'], tiempo: 'Mirarlo lleva unos minutos. Si hay que reparar, puede tardar hasta una hora.',
    nota: 'No siempre se puede arreglar la causa sin ayuda. Si es así, te lo diré con claridad.', confirmar: 'Si hay que reparar archivos de Windows, puede tardar hasta una hora. Antes de eso te preguntaré. ¿Empezamos?' },
  { id: 'virus', titulo: 'Creo que tiene un virus', texto: 'Ventanas raras, anuncios o programas que no instalaste.', icono: <ShieldCheck size={28} strokeWidth={1.75} />,
    hace: ['Compruebo que el antivirus y la protección de Internet estén encendidos y al día.', 'Hago un análisis rápido en busca de virus con el antivirus de Windows.', 'Dejo que el antivirus quite lo que encuentre y te cuento qué ha sido.'], tiempo: 'El análisis suele tardar entre 3 y 15 minutos.',
    nota: 'Es el análisis rápido de Windows. Si el problema es grave, que lo revise también una persona.', confirmar: 'El análisis de virus puede tardar un buen rato (de 3 a 15 minutos). ¿Empezamos?' },
  { id: 'espacio', titulo: 'Se queda sin espacio', texto: 'Aparece el aviso de poco espacio o el disco está lleno.', icono: <HardDrive size={28} strokeWidth={1.75} />,
    hace: ['Miro cuánto espacio queda libre.', 'Borro archivos temporales que sobran. No toco tus fotos ni tus documentos.'], tiempo: 'Suele tardar un minuto.' },
]

/** Explicación de los términos de cada opción, plegada: «¿Qué es esto?» */
const AYUDA: Record<string, string> = {
  todo: 'Primero miro, sin cambiar nada. Después te enseño lo que he encontrado y tú decides qué hago.',
  lento: 'Los archivos temporales son restos que dejan los programas y ya no hacen falta. Liberar memoria no cierra nada: recupera la que algunos programas tenían reservada sin usarla.',
  internet: 'Restablecer la configuración de red es reiniciar el «enlace» del ordenador con el router. No borra tu contraseña del Wi-Fi.',
  avisos: 'Los archivos de Windows dañados provocan pantallazos azules o cierres inesperados. Windows trae una herramienta para repararlos y la lanzo yo.',
  virus: 'El antivirus de Windows (Microsoft Defender) ya viene con tu ordenador. Yo solo lo enciendo, lo actualizo y le pido un análisis rápido.',
  espacio: 'Borro solo archivos temporales (restos de programas). Tus fotos, documentos y descargas no se tocan.'
}
const AYUDA_FASE: Record<string, string> = {
  analisis: 'Estoy mirando el ordenador sin cambiar nada.',
  confirmar: 'Todavía no he cambiado nada. Marca o quita lo que quieras y pulsa el botón; si prefieres, pide solo la información.',
  arreglando: 'Estoy aplicando, uno a uno, los pasos que elegiste. Si uno tarda demasiado, lo cierro y sigo con el siguiente.',
  verificando: 'Vuelvo a medir lo que he tocado para comprobar si ha funcionado.'
}
const FASES = ['Revisar', 'Decidir', 'Arreglar', 'Comprobar']
function Fases({ fase }: { fase: Auto['fase'] }) {
  const i = fase === 'analisis' ? 0 : fase === 'confirmar' ? 1 : fase === 'arreglando' ? 2 : 3
  return (
    <ol className="fases" aria-label="Fases">
      {FASES.map((f, k) => (
        <li key={f} aria-current={k === i ? 'step' : undefined} className={k < i ? 'hecha' : k === i ? 'actual' : ''}>
          {k < i && <Check size={16} strokeWidth={2} aria-hidden="true" />}{f}{k < i && <span className="solo-lector"> (hecho)</span>}
        </li>
      ))}
    </ol>
  )
}
const hace = (t: number) => { const m = Math.round((Date.now() - t) / 60000); return m < 1 ? 'menos de un minuto' : m === 1 ? '1 minuto' : m < 60 ? `${m} minutos` : `${Math.round(m / 60)} h` }

/** Programas de diagnóstico del kit que se enseñan en el modo sencillo, con nombre y explicación de calle. El título es el del catálogo. */
const MIRAR: { titulo: string; nombre: string; texto: string }[] = [
  { titulo: 'CrystalDiskInfo', nombre: 'Estado de los discos', texto: 'Dice si el disco está sano y cuánto lleva funcionando.' },
  { titulo: 'HWMonitor', nombre: 'Temperaturas', texto: 'Muestra cuánto se calientan el procesador, la gráfica y los discos.' },
  { titulo: 'WizTree', nombre: 'Qué ocupa el espacio', texto: 'Enseña qué carpetas y archivos llenan el disco.' },
  { titulo: 'CPU-Z', nombre: 'Ficha del ordenador', texto: 'El procesador, la memoria y la placa, con sus nombres exactos.' },
  { titulo: 'MonTest', nombre: 'Probar la pantalla', texto: 'Colores y líneas para ver si hay manchas o píxeles muertos.' },
  { titulo: 'Test de teclado (App)', nombre: 'Probar el teclado', texto: 'Marca cada tecla que pulsas para ver cuáles no responden.' },
  { titulo: 'PhotoRec', nombre: 'Recuperar archivos borrados', texto: 'Busca fotos y documentos que se borraron sin querer.' }
]
/** Qué opción de la portada resuelve cada aviso de la revisión rápida. */
const ACCION_A_OPCION: Record<string, string> = { CrystalDiskInfo: 'avisos', 'Analizar_Espacio_Disco.ps1': 'espacio', 'Gestion_Memoria_RAM.ps1': 'lento' }

const RESULTADO: Record<string, { texto: string; tono: Tono }> = {
  resuelto: { texto: 'Arreglado y comprobado', tono: 'ok' }, hecho: { texto: 'Hecho', tono: 'ok' },
  parcial: { texto: 'Arreglado en parte', tono: 'aviso' }, reinicio: { texto: 'Aplicado: falta reiniciar', tono: 'aviso' },
  preparado: { texto: 'Preparado: falta instalar las actualizaciones', tono: 'aviso' }, avisos: { texto: 'Terminó con avisos', tono: 'aviso' },
  pendiente: { texto: 'Aplicado, pero el problema sigue', tono: 'aviso' }, saltado: { texto: 'Saltado', tono: 'aviso' },
  tiempo: { texto: 'Se cerró porque tardaba demasiado', tono: 'aviso' }, nohecho: { texto: 'No se pudo aplicar ahora', tono: 'aviso' }
}
const PUNTO_PASO: Record<EstadoPaso, string> = { espera: 'espera', activo: 'activo', ok: '', aviso: 'aviso', saltado: 'info', tiempo: 'aviso', nohecho: 'aviso' }
const PUNTO_ESTADO: Record<string, string> = { OK: '', Info: 'info', Aviso: 'aviso', Fallo: 'error' }
const TITULO_ENFOQUE: Record<string, string> = { lento: 'Va lento', internet: 'No tengo Internet', avisos: 'Salen avisos o errores', virus: 'Creo que tiene un virus', espacio: 'Se queda sin espacio' }
const ETIQUETA_PASO: Record<EstadoPaso, string> = { espera: 'Pendiente', activo: 'En curso', ok: 'Hecho', aviso: 'Hecho con avisos', saltado: 'Saltado', tiempo: 'Se cerró por tardar demasiado', nohecho: 'No se pudo aplicar ahora' }
const mmss = (s: number) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`
const esReinicio = (texto: string) => /^Reinicia/.test(texto)

export default function Arreglar(p: Props) {
  const { auto } = p
  if (!auto) return <Portada {...p} />
  if (auto.fase === 'error') return (
    <div className="pagina facil">
      <header className="cabecera"><div><h1 tabIndex={-1}>{auto.cancelado ? 'Lo has parado' : 'No he podido terminar'}</h1><p>{auto.error ?? 'Se interrumpió antes de acabar.'}</p></div></header>
      {auto.pasos.some((x) => x.estado !== 'espera') && <p className="calma">{auto.cancelado ? 'No pasa nada. ' : ''}Lo que se llegó a cambiar antes de parar queda anotado.{auto.pasos.some((x) => x.estado === 'ok' || x.estado === 'aviso') ? <> <button className="enlace" onClick={p.alDeshacer}>Deshacer los últimos cambios</button></> : null}</p>}
      <div className="acciones">
        {p.puedeRepetir && !auto.cancelado && <button className="boton principal-b grande" onClick={p.alRepetir}>Volver a intentarlo</button>}
        <button className={`boton grande ${p.puedeRepetir && !auto.cancelado ? '' : 'principal-b'}`} onClick={p.alNueva}>Volver al principio</button>
        {p.puedeRepetir && auto.cancelado && <button className="boton grande" onClick={p.alRepetir}>Empezar otra vez</button>}
        <CopiarOcurrido auto={auto} lineas={p.lineas} />
      </div>
    </div>
  )
  if (auto.fase === 'fin' && auto.resultado) return <Resultado {...p} auto={auto} r={auto.resultado} />
  if (auto.fase === 'confirmar') return <Plan {...p} auto={auto} />
  return <Trabajando {...p} auto={auto} />
}

/** «Copiar lo ocurrido»: lo que hay que enseñar a un técnico, ya preparado. */
function CopiarOcurrido({ auto, lineas }: { auto: Auto; lineas: string[] }) {
  const [copiado, setCopiado] = useState(false)
  const copiar = async () => {
    const texto = ['Nitrit0 Kit: lo ocurrido', auto.error ?? '', ...auto.pasos.filter((x) => x.estado !== 'espera').map((x) => `- ${x.titulo}: ${x.texto || x.estado}`), '', ...lineas.slice(-15)].filter((x) => x !== undefined).join('\n')
    try { await navigator.clipboard.writeText(texto); setCopiado(true); setTimeout(() => setCopiado(false), 2500) } catch { /* sin portapapeles */ }
  }
  return <button className="boton grande" onClick={() => void copiar()}>{copiado ? 'Copiado' : 'Copiar lo ocurrido'}</button>
}

// ---------------------------------------------------------------- Portada
function Portada({ ocupado, cliente, elementos, alEmpezar, alLanzar, alPedir, ultima, alRepetirRevision, simple, opcionInicial }: Props) {
  const [abierto, setAbierto] = useState<string | null>(opcionInicial ?? null)
  useEffect(() => { if (opcionInicial) setAbierto(opcionInicial) }, [opcionInicial])
  const [nombre, setNombre] = useState(cliente)
  const [actualizar, setActualizar] = useState(false)
  const [antivirus, setAntivirus] = useState(false)
  const [recom, setRecom] = useState<Revision[] | null>(null)
  useEffect(() => {
    // La lectura tarda unos segundos: la portada ya es usable mientras llega
    let vivo = true
    Promise.all([window.kit.resumen() as Promise<Resumen>, window.kit.vivo() as Promise<Vivo>])
      .then(([r, v]) => { if (vivo) setRecom(revisiones({ ...r, discos: r.discos ?? [], volumenes: r.volumenes ?? [] }, v)) })
      .catch(() => { if (vivo) setRecom([]) })
    return () => { vivo = false }
  }, [])
  const elegir = (id: string) => { setAbierto(id); document.getElementById(`opcion-${id}`)?.scrollIntoView({ block: 'nearest', behavior: 'smooth' }) }
  const mirar = MIRAR.map((m) => ({ m, e: elementos.find((x) => x.titulo === m.titulo && x.soportado && x.disponible) })).filter((x): x is { m: typeof MIRAR[number]; e: Elemento } => !!x.e)
  const avisos = (recom ?? []).filter((x) => x.tono !== 'ok')
  // «Repetirla» pasa por el mismo «¿Empezamos?» que la opción original
  const repetirConfirmado = () => { const x = PROBLEMAS.find((q) => q.id === ultima?.enfoque); if (x?.confirmar) alPedir({ titulo: x.titulo, texto: x.confirmar, ok: 'Sí, empezar', no: 'Ahora no', alAceptar: alRepetirRevision }); else alRepetirRevision() }
  useEffect(() => {
    if (!abierto) return
    const b = document.getElementById(`empezar-${abierto}`)
    b?.scrollIntoView({ block: 'nearest', behavior: 'smooth' })
  }, [abierto])

  return (
    <div className="pagina facil">
      <header className="cabecera"><div><h1 tabIndex={-1}>¿Qué le pasa a tu ordenador?</h1><p>Elige lo que más se parezca. Antes de cambiar nada te cuento qué voy a hacer y tú decides.</p></div></header>
      {ultima && (
        <section className="recom" aria-label="Tu última revisión">
          <h2>Tu última revisión</h2>
          <div className="recom-fila"><span className="punto info" aria-hidden="true" /><span className="cuerpo"><b>{ultima.titular}</b><span className="det">Hace {hace(ultima.hora)}.</span></span><button className="boton" disabled={ocupado} onClick={repetirConfirmado}>Repetirla</button></div>
        </section>
      )}
      {avisos.length > 0 && <section className="recom" aria-label="Cómo está tu ordenador">
        <h2>He visto esto en tu ordenador</h2>
        {avisos.slice(0, 3).map((a) => {
          const op = ACCION_A_OPCION[a.accion ?? '']
          return (
            <div className="recom-fila" key={a.titulo}>
              <span className={`punto ${a.tono}`} role="img" aria-label={a.tono === 'error' ? 'Problema' : 'Aviso'} />
              <span className="cuerpo"><b>{a.titulo}</b><span className="det">{a.detalle}</span></span>
              {op && <button className="boton" onClick={() => elegir(op)} aria-label={`Arreglarlo: ${a.titulo}`}>Arreglarlo</button>}
            </div>
          )
        })}
      </section>}
      <div className="problemas" role="group" aria-label="Problemas">
        {PROBLEMAS.map((x) => {
          const es = abierto === x.id
          return (
            <div className={`problema ${es ? 'abierto' : ''}`} key={x.id} id={`opcion-${x.id}`}>
              <button className="problema-btn" aria-expanded={es} aria-controls={es ? `panel-${x.id}` : undefined} onClick={() => setAbierto(es ? null : x.id)}>
                <span className="problema-icono" aria-hidden="true">{x.icono}</span>
                <span className="cuerpo"><b>{x.titulo}</b><span className="det">{x.texto}</span></span>
                <ChevronRight className="chev" size={22} strokeWidth={1.75} aria-hidden="true" />
              </button>
              {es && (
                <div className="problema-panel" id={`panel-${x.id}`}>
                  <p className="panel-tit">Esto es lo que voy a hacer:</p>
                  <ul className="lista-simple">{x.hace.map((h) => <li key={h}>{h}</li>)}</ul>
                  <p className="calma">{x.tiempo}</p>
                  {x.nota && <p className="calma">{x.nota}</p>}
                  <details className="mas"><summary>¿Qué es esto?</summary><p className="calma">{AYUDA[x.id]}</p></details>
                  <div className="acciones">
                    <button id={`empezar-${x.id}`} className="boton principal-b grande" disabled={ocupado} onClick={() => { const ir = () => alEmpezar({ enfoque: x.id, actualizar: x.id === 'todo' && actualizar, antivirus: x.id === 'todo' && antivirus, cliente: nombre }); if (x.confirmar) alPedir({ titulo: x.titulo, texto: x.confirmar, ok: 'Sí, empezar', no: 'Ahora no', alAceptar: ir }); else ir() }}>Empezar</button>
                  </div>
                  {ocupado && <p className="aviso-txt">Hay otra cosa en marcha. Espera a que termine.</p>}
                  {(!simple || x.id === 'todo') && <details className="mas">
                    <summary>Más opciones</summary>
                    {!simple && <label className="campo auto-campo">Nombre del cliente (opcional, sale en el informe)
                      <input value={nombre} maxLength={200} onChange={(e) => setNombre(e.target.value)} autoComplete="off" />
                    </label>}
                    {x.id === 'todo' && (
                      <label className="casilla">
                        <input type="checkbox" checked={antivirus} onChange={(e) => setAntivirus(e.target.checked)} />
                        <span>Hacer también un análisis de virus<span className="sub-linea"> Con el antivirus de Windows. Suma entre 3 y 15 minutos.</span></span>
                      </label>
                    )}
                    {x.id === 'todo' && (
                      <label className="casilla">
                        <input type="checkbox" checked={actualizar} onChange={(e) => setActualizar(e.target.checked)} />
                        <span>Instalar también las actualizaciones de Windows<span className="sub-linea"> Puede tardar más de una hora.</span></span>
                      </label>
                    )}
                  </details>}
                </div>
              )}
            </div>
          )
        })}
      </div>
      {mirar.length > 0 && (
        <details className="mas mirar">
          <summary>Programas para mirarlo tú mismo ({mirar.length})</summary>
          <p className="calma">Se abren en su propia ventana.</p>
          {mirar.map(({ m, e }) => (
            <div className="fila-simple mirar-fila" key={m.titulo}>
              <span className="cuerpo"><b>{m.nombre}</b><span className="det">{m.texto}</span></span>
              <button className="boton" onClick={() => alLanzar(e)} aria-label={`Abrir ${m.nombre}`}>Abrir</button>
            </div>
          ))}
        </details>
      )}
      {recom !== null && avisos.length === 0 && <p className="calma">Por ahora todo parece en orden: hay espacio, memoria libre y los discos están sanos.</p>}
      <p className="calma">No borro documentos ni desinstalo programas. Antes de cambiar nada del sistema guardo una copia de seguridad de la configuración.</p>
    </div>
  )
}

// ---------------------------------------------------------------- Plan (la persona decide)
function Plan({ auto, alConfirmarPlan, alCancelarSinPreguntar }: Props & { auto: Auto }) {
  const [quitados, setQuitados] = useState<string[]>([])
  const elegidos = auto.pasos.filter((x) => x.id === 'restauracion' || !quitados.includes(x.id)).map((x) => x.id)
  const hacen = elegidos.filter((id) => id !== 'restauracion').length
  const minutos = auto.pasos.filter((x) => elegidos.includes(x.id)).reduce((s, x) => s + x.min, 0)
  const alternar = (id: string) => setQuitados((q) => (q.includes(id) ? q.filter((x) => x !== id) : [...q, id]))
  const n = auto.detectados.length
  return (
    <div className="pagina facil">
      <header className="cabecera"><div>
        <h1 tabIndex={-1}>{n === 0 ? 'No he encontrado nada roto' : n === 1 ? 'He encontrado una cosa' : `He encontrado ${n} cosas`}</h1>
        <p>{n === 0 ? 'Si quieres, hago estas tareas de mantenimiento.' : 'Esto es lo que propongo. Tú decides qué se hace.'}</p>
      </div></header>
      {n > 0 && (
        <section className="bloque" aria-label="Lo encontrado">
          <h2>Lo que he visto</h2>
          <ul className="lista-simple">{auto.detectados.map((d) => <li key={d.id}><b>{d.nombre}.</b> {d.llano ?? d.resumen}</li>)}</ul>
        </section>
      )}
      <section className="grupo" aria-label="Lo que voy a hacer">
        <h2>Lo que voy a hacer<span className="num">{auto.pasos.length}</span></h2>
        {auto.pasos.map((x) => (
          <label className="paso-elegible" key={x.id}>
            <input type="checkbox" checked={elegidos.includes(x.id)} disabled={x.id === 'restauracion'} onChange={() => alternar(x.id)} />
            <span className="cuerpo"><b>{x.titulo}</b><span className="det">{x.que}{x.id === 'restauracion' ? ' Siempre se hace antes de cambiar nada.' : ''}</span></span>
            <span className="sub-linea num">~{x.min} min</span>
          </label>
        ))}
      </section>
      <Fases fase="confirmar" />
      {hacen > 0 && <p className="calma">En total, unos {minutos} minutos.{minutos >= 30 ? ' Es bastante: puedes dejar el ordenador trabajando y volver luego.' : ''}</p>}
      <div className="acciones">
        <button className="boton principal-b grande" disabled={hacen === 0} onClick={() => alConfirmarPlan(elegidos)}>{elegidos.length === 1 ? 'Hacerlo' : `Hacer los ${elegidos.length} pasos`}</button>
        <button className="boton grande" onClick={() => alConfirmarPlan([])}>Solo quiero la información</button>
        <button className="boton" onClick={alCancelarSinPreguntar}>No hacer nada</button>
      </div>
      <p className="calma">Lo que cambie queda anotado. Al terminar podrás deshacerlo con un clic si algo no va bien.</p>
    </div>
  )
}

// ---------------------------------------------------------------- Trabajando
function Trabajando({ auto, simple, alDetener, alSaltar, enfoque }: Props & { auto: Auto }) {
  const [ahora, setAhora] = useState(Date.now())
  useEffect(() => { const id = setInterval(() => setAhora(Date.now()), 1000); return () => clearInterval(id) }, [])
  const activo = auto.pasos.find((x) => x.estado === 'activo')
  const hechos = auto.pasos.filter((x) => x.estado !== 'espera' && x.estado !== 'activo').length
  const titulo = auto.combo ? (auto.pasos[0]?.id === 'deshacer' ? 'Estoy deshaciendo los últimos cambios' : 'Estoy aplicando lo que elegiste') : auto.fase === 'analisis' ? 'Estoy revisando tu ordenador' : auto.fase === 'verificando' ? 'Compruebo que ha funcionado' : 'Estoy arreglando lo que he encontrado'
  const frase = auto.fase === 'arreglando'
    ? (activo ? `Paso ${Math.min(hechos + 1, auto.pasos.length)} de ${auto.pasos.length}: ${activo.titulo}.` : 'Un momento…')
    : (auto.actual ? `Mirando: ${auto.actual}.` : 'Un momento…')
  const parado = !!activo && activo.silencio >= 120
  const pendientes = auto.pasos.filter((x) => x.estado === 'espera').reduce((s, x) => s + x.min, 0)
  const quedan = activo ? Math.max(1, Math.round(pendientes + Math.max(activo.min - (activo.desde ? (ahora - activo.desde) / 60000 : 0), 0.5))) : 0
  const llevo = Math.max(0, Math.floor((ahora - auto.t0) / 1000))
  const valor = auto.fase === 'arreglando' ? hechos : auto.hechas
  const max = auto.fase === 'arreglando' ? Math.max(auto.pasos.length, 1) : Math.max(auto.total, 1)
  const sinCuenta = auto.fase === 'arreglando' ? auto.pasos.length === 0 : auto.total === 0

  return (
    <div className="pagina facil">
      <header className="cabecera"><div><h1 tabIndex={-1}>{titulo}</h1><p>{frase}</p></div></header>
      <p className="solo-lector" role="status">{frase}</p>
      {!auto.combo && <Fases fase={auto.fase} />}
      {!auto.combo && enfoque && enfoque !== 'todo' && <p className="calma">Elegiste «{TITULO_ENFOQUE[enfoque] ?? enfoque}».</p>}
      <Medidor rol="progressbar" etiqueta="Avance" valor={valor} max={max} indeterminado={sinCuenta || (activo?.id === 'antivirus')} />
      {activo?.id === 'antivirus' && activo.texto && <p className="calma">{activo.texto}</p>}
      <p className="calma">Llevo {mmss(llevo)}{auto.fase === 'arreglando' && activo ? ` · quedan unos ${quedan} min (aproximado)` : auto.fase === 'analisis' && !auto.combo ? ' · suele tardar menos de un minuto' : ''}. Puedes dejarlo trabajando; no apagues el ordenador.</p>
      {parado && (
        <div className="aviso-banda" role="alert">
          <p style={{ margin: '0 0 8px' }}>Esto está tardando más de lo normal ({mmss(activo.silencio)} sin avances).</p>
          <button className="boton" onClick={alSaltar}>Pasar al siguiente</button>
        </div>
      )}
      <div className="acciones"><button className="boton" onClick={alDetener}>Parar</button></div>
      <details className="mas" open={!simple}>
        <summary>¿Qué está pasando?</summary>
        <p className="calma">{auto.combo ? AYUDA_FASE.arreglando : AYUDA_FASE[auto.fase]}</p>
        <DetalleVivo auto={auto} ahora={ahora} alSaltar={alSaltar} />
      </details>
    </div>
  )
}

function DetalleVivo({ auto, ahora, alSaltar }: { auto: Auto; ahora: number; alSaltar: () => void }) {
  return (
    <div className="detalle-tec">
      {auto.detectados.length > 0 && (
        <section className="grupo" aria-label="Lo que se ha encontrado">
          <h2>Lo que se ha encontrado<span className="num">{auto.detectados.length}</span></h2>
          {auto.detectados.map((d) => (
            <div className="revision" key={d.id}>
              <span className={`punto ${PUNTO_ESTADO[d.estado] ?? 'aviso'}`} role="img" aria-label={d.estado === 'Fallo' ? 'Problema' : 'Aviso'} />
              <div className="cuerpo"><b>{d.nombre}</b><span className="det">{d.resumen}</span></div><span />
            </div>
          ))}
        </section>
      )}
      {auto.pasos.length > 0 && (
        <section className="grupo" aria-label="Pasos">
          <h2>Lo que se va a hacer<span className="num">{auto.pasos.length}</span></h2>
          {auto.pasos.map((x: PasoVivo) => {
            const seg = x.desde ? Math.max(0, Math.floor((ahora - x.desde) / 1000)) : 0
            return (
              <div className="revision auto-paso" key={x.id}>
                <span className={`punto ${PUNTO_PASO[x.estado]}`} role="img" aria-label={ETIQUETA_PASO[x.estado]} />
                <div className="cuerpo">
                  <b>{x.titulo}</b><span className="det">{x.que}</span>
                  {x.estado === 'activo' && <span className="paso-linea num">{x.texto || 'En marcha…'}</span>}
                  {x.estado === 'espera' && x.min > 5 && <span className="sub-linea">Puede tardar unos {x.min} min.</span>}
                </div>
                <div className="paso-lado">
                  {x.estado === 'activo'
                    ? <><span className="num seg">{mmss(seg)}</span><button className="boton" onClick={alSaltar} aria-label={`Saltar el paso ${x.titulo}`}>Saltar este paso</button></>
                    : <span className="sub-linea">{ETIQUETA_PASO[x.estado]}</span>}
                </div>
              </div>
            )
          })}
        </section>
      )}
      {auto.detectados.length === 0 && auto.pasos.length === 0 && <p className="nota-vacia">Todavía no hay nada que contar.</p>}
    </div>
  )
}

// ---------------------------------------------------------------- Resultado
function Resultado({ simple, soluciones, elementos, ocupado, informe, reinicioPedido, puedeRepetir, alRepetir, alDeshacer, alNueva, alLanzar, alReiniciar, alCancelarReinicio, r }: Props & { auto: Auto; r: AutoResultado }) {
  const [verInforme, setVerInforme] = useState(false)
  const solo = (id: string) => (soluciones[id] ?? []).map((t) => elementos.find((e) => e.titulo === t && e.soportado && e.disponible)).filter((e): e is Elemento => !!e).slice(0, 3)

  // Un reinicio pendiente no es un problema de nadie: se resuelve con el botón de reiniciar.
  const problemas = r.detectados.filter((d) => !(d.id === 'sistema' && /reinicio|reiniciarse/i.test(d.resumen)))
  const ayuda = r.atencion.filter((a) => !esReinicio(a.consejo))
  const arreglados = problemas.filter((d) => d.arreglado).length
  const av = r.antivirus
  const amenazas = av?.amenazas ?? 0
  // Un análisis que no se hizo no se cuenta como hecho, y nunca debe acabar en «Tu ordenador está bien»
  const avSinHacer = !!av && !av.analizado
  const avFallo = avSinHacer && !av?.otro && r.pasos.some((x) => x.id === 'antivirus' && (x.estado === 'ok' || x.estado === 'aviso'))
  const restFallo = r.pasos.some((x) => x.id === 'restauracion' && x.estado !== 'ok')
  // La copia de seguridad que no se pudo guardar no se cuenta como «hecho», pero se avisa abajo con calma
  const hechos = r.pasos.filter((x) => (x.estado === 'ok' || x.estado === 'aviso') && !(x.id === 'antivirus' && avSinHacer) && x.id !== 'restauracion')
  const noHechos = r.pasos.filter((x) => (x.estado === 'saltado' || x.estado === 'tiempo' || x.estado === 'nohecho') && !(x.id === 'antivirus' && av?.otro))
  const hechoFrase = (x: PasoVivo) => x.hecho ?? x.titulo

  let tono: 'ok' | 'aviso' = 'ok'; let titulo: string; let sub: string
  const combo = r.modo === 'combo'
  if (combo) { tono = r.pasos.every((x) => x.estado === 'ok') ? 'ok' : 'aviso'; titulo = tono === 'ok' ? 'Listo' : 'Terminado con avisos'; sub = r.titular }
  else if (r.soloMirar) { tono = problemas.length ? 'aviso' : 'ok'; titulo = problemas.length ? 'Esto es lo que he encontrado' : 'Tu ordenador está bien'; sub = 'No he cambiado nada, como pediste.' }
  else if (amenazas > 0) { tono = 'aviso'; titulo = amenazas === 1 ? 'He encontrado una amenaza' : `He encontrado ${amenazas} amenazas`; sub = 'El antivirus de Windows se ha ocupado de ellas. Reinicia el ordenador y, si quieres estar seguro, que lo revise una persona.' }
  else if (avSinHacer) { tono = 'aviso'; if (av?.otro) { titulo = 'Tu equipo usa otro antivirus'; sub = `Ábrelo (${av.otro}) y haz el análisis desde su ventana: yo no puedo manejarlo.` } else { titulo = 'No he podido buscar virus'; sub = 'El antivirus de Windows no ha podido analizar el equipo. Comprueba que la app está abierta como administrador e inténtalo de nuevo.' } }
  else if (problemas.length === 0 && !r.reiniciar) { titulo = 'Tu ordenador está bien'; sub = hechos.length ? 'No había nada roto. He hecho una limpieza por si acaso.' : 'No he encontrado ningún problema.' }
  else if (problemas.length === 0) { titulo = 'Ya está listo'; sub = 'No he encontrado nada roto. Solo falta reiniciar el ordenador para terminar.' }
  else if (ayuda.length === 0) { titulo = 'Ya está arreglado'; sub = `${problemas.length === 1 ? 'Había una cosa y ya está solucionada.' : `Había ${problemas.length} cosas y ya están solucionadas.`}${r.reiniciar ? ' Para terminar, reinicia el ordenador.' : ''}` }
  else if (arreglados > 0) { tono = 'aviso'; titulo = 'He arreglado lo que podía'; sub = `Queda${ayuda.length === 1 ? ' una cosa que necesita' : `n ${ayuda.length} cosas que necesitan`} ayuda de una persona.` }
  else { tono = 'aviso'; titulo = 'Hay algo que no puedo arreglar yo solo'; sub = `${ayuda.length === 1 ? 'Hay una cosa que necesita' : `Hay ${ayuda.length} cosas que necesitan`} ayuda de una persona. Abajo te explico cuál.` }

  return (
    <div className="pagina facil">
      <header className="cabecera">
        <div className={`estado-grande ${tono}`}>
          {tono === 'ok' ? <CircleCheck size={52} strokeWidth={1.5} aria-hidden="true" /> : <TriangleAlert size={52} strokeWidth={1.5} aria-hidden="true" />}
          <div><h1 tabIndex={-1}>{titulo}</h1><p>{sub}</p></div>
        </div>
      </header>

      {r.reiniciar && (
        <section className="reinicio" aria-label="Reiniciar">
          {reinicioPedido
            ? <><b>El ordenador se reiniciará en 30 segundos.</b><span>Guarda lo que tengas abierto.</span><div className="acciones"><button className="boton grande" onClick={alCancelarReinicio}>Cancelar el reinicio</button></div></>
            : <><b>Para terminar, hay que reiniciar el ordenador.</b><span>Guarda lo que tengas abierto antes de reiniciar.</span><div className="acciones"><button className="boton principal-b grande" onClick={alReiniciar}>Reiniciar ahora</button></div></>}
        </section>
      )}

      <section className="bloque" aria-label="Lo que he hecho">
        <h2>Esto es lo que he hecho</h2>
        {!combo && r.enfoque && r.enfoque !== 'todo' && <p className="calma">Elegiste «{TITULO_ENFOQUE[r.enfoque] ?? r.enfoque}».</p>}
        {hechos.length === 0 && noHechos.length === 0 && !avFallo && <p className="calma">No hizo falta cambiar nada.</p>}
        {av?.analizado && amenazas === 0 && <p className="calma">En el análisis de virus no ha salido ninguna amenaza.</p>}
        {av?.otro && <p className="calma">Este equipo usa otro antivirus ({av.otro}). Ábrelo y haz el análisis desde su propia ventana.</p>}
        <ul className="lista-simple">
          {hechos.map((x) => <li key={x.id}>{hechoFrase(x)}</li>)}
          {avFallo && <li>No he podido analizar el equipo con el antivirus de Windows.</li>}
          {noHechos.map((x) => <li key={x.id}>No he podido terminar: {x.titulo.charAt(0).toLowerCase()}{x.titulo.slice(1)}.</li>)}
        </ul>
        {restFallo && hechos.length > 0 && <p className="calma" style={{ marginTop: 12 }}>No pude guardar la copia de seguridad de Windows. Los ajustes que se hayan cambiado se pueden deshacer igualmente; reparar archivos o la red, no.</p>}
      </section>

      {av && amenazas > 0 && (
        <section className="bloque" aria-label="Amenazas">
          <h2>Esto es lo que ha encontrado el antivirus</h2>
          <ul className="lista-simple">{av.lista.map((l) => <li key={l}>{l}</li>)}</ul>
        </section>
      )}

      {ayuda.length > 0 && (
        <section className="bloque" aria-label="Necesita ayuda">
          <h2>Esto necesita ayuda de una persona</h2>
          <ul className="lista-simple">
            {ayuda.map((a) => <li key={a.id}><b>{a.nombre}.</b> {a.llano ? `${a.llano} ` : ''}{a.consejo}</li>)}
          </ul>
          <p className="calma">Puedes enseñarle el informe a quien te ayude.</p>
        </section>
      )}

      <div className="acciones">
        {(avSinHacer || noHechos.length > 0) && puedeRepetir && <button className="boton principal-b grande" onClick={alRepetir}>Volver a intentarlo</button>}
        <button className={`boton grande ${(avSinHacer || noHechos.length > 0) && puedeRepetir ? '' : 'principal-b'}`} onClick={alNueva}>Volver al principio</button>
        {informe && <button className="boton grande" aria-pressed={verInforme} onClick={() => setVerInforme((v) => !v)}>{verInforme ? 'Ocultar el informe' : 'Ver el informe'}</button>}
      </div>
      {!combo && hechos.some((x) => !['limpieza', 'antivirus', 'limpieza_profunda'].includes(x.id)) && <p className="calma">¿Algo no va bien ahora? <button className="enlace" onClick={alDeshacer}>Deshacer los últimos cambios</button></p>}
      {verInforme && informe && <iframe className="hoja" title="Informe de la revisión" sandbox="" srcDoc={informe.html} />}

      <details className="mas" open={!simple}>
        <summary>Detalles técnicos</summary>
        <div className="detalle-tec">
          {r.informe && <p className="sub-linea">Informe guardado en <span className="num">{r.informe}</span> · {r.modo === 'combo' ? `${mmss(r.seg)} en total` : `${r.revisadas} comprobaciones en ${mmss(r.seg)}`}</p>}
          {r.atencion.length > 0 && (
            <section className="grupo" aria-label="Necesita atención">
              <h2>Necesita atención<span className="num">{r.atencion.length}</span></h2>
              {r.atencion.map((a) => {
                const sol = !simple && !esReinicio(a.consejo) ? solo(a.id) : []
                return (
                  <div className="revision auto-atencion" key={a.id}>
                    <span className={`punto ${PUNTO_ESTADO[a.estado] ?? 'aviso'}`} role="img" aria-label={a.estado === 'Fallo' ? 'Problema' : 'Aviso'} />
                    <div className="cuerpo"><b>{a.nombre}</b><span className="det">{a.resumen}</span><span className="det">{a.consejo}</span></div>
                    <div className="siguiente">
                      {sol.map((e) => <button key={e.id} className="boton" disabled={ocupado && usaEjecutor(e)} onClick={() => alLanzar(e)} aria-label={`${verbo(e)} ${e.titulo}`}>{e.titulo}</button>)}
                    </div>
                  </div>
                )
              })}
            </section>
          )}
          <section className="grupo" aria-label="Pasos aplicados">
            <h2>Pasos aplicados<span className="num">{r.pasos.length}</span></h2>
            {r.pasos.length === 0 && <p className="nota-vacia">No hizo falta cambiar nada en el equipo.</p>}
            {r.pasos.map((x) => {
              const res = x.resultado ? RESULTADO[x.resultado] : undefined
              return (
                <details className="prueba" key={x.id}>
                  <summary>
                    <span className={`punto ${res ? (res.tono === 'ok' ? '' : 'aviso') : PUNTO_PASO[x.estado]}`} role="img" aria-label={res?.tono === 'ok' ? 'Correcto' : 'Aviso'} />
                    <span className="cuerpo"><b>{x.titulo}</b><span className="det">{res?.texto ?? ETIQUETA_PASO[x.estado]}</span></span>
                    <span className="num seg">{x.seg ?? 0} s</span>
                  </summary>
                  <div className="prueba-detalle">
                    <p className="siguiente-txt">{x.que}</p>
                    {x.lineas.length > 0 && <pre>{x.lineas.map((l) => l.texto).join('\n')}</pre>}
                  </div>
                </details>
              )
            })}
          </section>
          {r.detectados.length > 0 && (
            <section className="grupo" aria-label="Lo que se encontró">
              <h2>Lo que se encontró<span className="num">{r.detectados.length}</span></h2>
              {r.detectados.map((d) => (
                <div className="revision" key={d.id}>
                  <span className={`punto ${d.arreglado ? '' : PUNTO_ESTADO[d.estado] ?? 'aviso'}`} role="img" aria-label={d.arreglado ? 'Arreglado' : 'Pendiente'} />
                  <div className="cuerpo"><b>{d.nombre}</b><span className="det">{d.resumen}</span></div>
                  <span className="sub-linea">{d.arreglado ? 'Arreglado' : 'Pendiente'}</span>
                </div>
              ))}
            </section>
          )}
        </div>
      </details>
    </div>
  )
}
