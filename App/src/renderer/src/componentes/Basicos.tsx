import { Component, useEffect, useRef, useState, type ReactNode } from 'react'
import type { Tono } from '../tipos'

export function PageHeader({ titulo, subtitulo, acciones, comoUsar }: { titulo: string; subtitulo?: string; acciones?: ReactNode; comoUsar?: string[] }) {
  return (
    <header className="cabecera">
      <div><h1 tabIndex={-1}>{titulo}</h1>{subtitulo && <p>{subtitulo}</p>}{comoUsar && <p className="como-usar"><b>Cómo usar:</b> {comoUsar.map((x, i) => `${i + 1}) ${x}`).join('  ')}</p>}</div>
      {acciones && <div className="acciones">{acciones}</div>}
    </header>
  )
}

export function Medidor({ valor, max = 100, tono, etiqueta, rol = 'meter', indeterminado = false }: { valor: number; max?: number; tono?: Tono; etiqueta: string; rol?: 'meter' | 'progressbar'; indeterminado?: boolean }) {
  // Sin cuenta real todavía: barra que se mueve y sin valor (los lectores de pantalla no anuncian un falso 0 %)
  if (indeterminado) return <div className="medidor indet" role="progressbar" aria-label={etiqueta}><i /></div>
  const pct = Math.max(0, Math.min(100, (valor / max) * 100))
  return <div className={`medidor ${tono ?? ''}`} role={rol} aria-label={etiqueta} aria-valuenow={Math.round(valor)} aria-valuemin={0} aria-valuemax={Math.round(max)}><i style={{ transform: `scaleX(${pct / 100})` }} /></div>
}

/** Veredicto de una pantalla: una frase clara arriba, con el color de cómo está todo. */
export function Veredicto({ tono, titulo, children }: { tono: Tono; titulo: string; children?: ReactNode }) {
  return <section className={`veredicto ${tono}`} aria-label="Veredicto"><h2>{titulo}</h2>{children && <p>{children}</p>}</section>
}

/** Tarjeta con título y una tabla de datos (clave-valor). Los datos que faltan no se pintan. */
export function Tarjeta({ titulo, datos, children }: { titulo: string; datos?: [string, ReactNode][]; children?: ReactNode }) {
  const filas = (datos ?? []).filter(([, v]) => v !== undefined && v !== null && v !== '' && v !== false)
  return (
    <section className="caja-datos" aria-label={titulo}>
      <h2>{titulo}</h2>
      {filas.length > 0 && <dl className="ficha">{filas.map(([k, v]) => <div className="par" key={k}><dt>{k}</dt><dd>{v}</dd></div>)}</dl>}
      {children}
    </section>
  )
}

/** Etiqueta corta de riesgo o estado (Recomendado, Reversible, Avanzado). Siempre con texto, nunca solo color. */
export function Sello({ tipo, children, ayuda }: { tipo: 'ok' | 'acento' | 'aviso' | 'error'; children: ReactNode; ayuda?: string }) {
  return <span className={`sello ${tipo}`} title={ayuda}>{children}</span>
}

/** Nota de salud 0-100: cada fallo resta 15 y cada aviso 5; la información no resta. Es un resumen, no una medida: el detalle está debajo. */
export const notaSalud = (fallos: number, avisos: number) => Math.max(0, 100 - fallos * 15 - avisos * 5)

export function NotaSalud({ nota }: { nota: number }) {
  const tono: Tono = nota >= 85 ? 'ok' : nota >= 60 ? 'aviso' : 'error'
  const r = 52, c = 2 * Math.PI * r
  return (
    <div className={`nota-salud ${tono}`} role="img" aria-label={`Salud del equipo: ${nota} sobre 100`} title="Cada fallo resta 15 puntos y cada aviso 5. La información no resta.">
      <svg viewBox="0 0 120 120" aria-hidden="true">
        <circle className="pista" cx="60" cy="60" r={r} />
        <circle className="valor" cx="60" cy="60" r={r} strokeDasharray={`${(c * nota) / 100} ${c}`} transform="rotate(-90 60 60)" />
      </svg>
      <div><b className="num">{nota}</b><span>salud del equipo</span></div>
    </div>
  )
}

/** Pestañas (solapas) de un espacio de trabajo: un grupo de opciones relacionadas en vez de una lista larga en el menú. Flechas izquierda/derecha para moverse. */
export function Solapas({ items, activo, alCambiar, etiqueta }: { items: { id: string; texto: string; cuenta?: number }[]; activo: string; alCambiar: (id: string) => void; etiqueta: string }) {
  return (
    <nav className="solapas-fila" aria-label={etiqueta}>
      <div className="solapas">
        {items.map((s) => (
          <button key={s.id} id={`solapa-${s.id}`} aria-current={activo === s.id ? 'page' : undefined} onClick={() => alCambiar(s.id)}>
            {s.texto}{s.cuenta !== undefined && <span className="cuenta num">{s.cuenta}</span>}
          </button>
        ))}
      </div>
    </nav>
  )
}

export function Vacio({ children }: { children: ReactNode }) {
  return <div className="vacio">{children}</div>
}

/** Confirmación con <dialog> nativo: atrapa el foco y se cierra con Escape. El foco inicial va a «Cancelar», como en el lanzador. */
export function Confirmar({ abierto, titulo, texto, detalle, textoOk, textoNo, alAceptar, alCancelar }: {
  abierto: boolean; titulo: string; texto: string; detalle?: string | null; textoOk: string; textoNo?: string; alAceptar: () => void; alCancelar: () => void
}) {
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => {
    const d = ref.current
    if (!d) return
    if (abierto && !d.open) d.showModal()
    if (!abierto && d.open) d.close()
  }, [abierto])
  return (
    <dialog ref={ref} onCancel={(e) => { e.preventDefault(); alCancelar() }} aria-labelledby="dlg-titulo">
      <h2 id="dlg-titulo">{titulo}</h2>
      <p>{texto}</p>
      {detalle && <p>{detalle}</p>}
      <div className="pie-dialogo">
        <button className="boton" autoFocus onClick={alCancelar}>{textoNo ?? 'Cancelar'}</button>
        <button className="boton principal-b" onClick={alAceptar}>{textoOk}</button>
      </div>
    </dialog>
  )
}

/** Ayuda general: preguntas de siempre en lenguaje llano y, en modo técnico, los atajos. Se abre con F1 o desde el pie. */
export function AyudaDialogo({ abierto, tecnico, alCerrar }: { abierto: boolean; tecnico: boolean; alCerrar: () => void }) {
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => {
    const d = ref.current
    if (!d) return
    if (abierto && !d.open) d.showModal()
    if (!abierto && d.open) d.close()
  }, [abierto])
  const preguntas: [string, string][] = [
    ['¿Se borrará algo mío?', 'No. Solo se borran archivos temporales (restos que dejan los programas). Tus fotos, documentos y descargas no se tocan.'],
    ['¿Puedo parar?', 'Sí, en cualquier momento con «Parar». Lo que ya se haya cambiado queda anotado y se puede deshacer con «Deshacer los últimos cambios».'],
    ['¿Cuánto tarda?', 'Cada opción lo dice. Revisar suele llevar menos de un minuto; reparar Windows puede llegar a una hora. Mientras tanto puedes dejar el ordenador trabajando.'],
    ['¿Qué es la copia de seguridad de la configuración?', 'Es un punto de restauración de Windows: una foto de los ajustes antes de cambiar nada, por si hay que volver atrás.'],
    ['¿Y si no se arregla?', 'Te lo digo con claridad y te propongo qué hacer. Puedes enseñar el informe a un técnico o pulsar «Volver a intentarlo».']
  ]
  return (
    <dialog ref={ref} className="ancho" onCancel={(e) => { e.preventDefault(); alCerrar() }} aria-labelledby="ayuda-titulo">
      <h2 id="ayuda-titulo">Ayuda</h2>
      {preguntas.map(([p, r]) => <details className="mas" key={p}><summary>{p}</summary><p>{r}</p></details>)}
      {tecnico && <details className="mas"><summary>Atajos del teclado</summary><p>Ctrl+1 a Ctrl+4: Inicio, Estado, Diagnóstico y Herramientas. Ctrl+F: buscar en el kit. F1: esta ayuda.</p></details>}
      <div className="pie-dialogo"><button className="boton principal-b" autoFocus onClick={alCerrar}>Cerrar</button></div>
    </dialog>
  )
}

/** Datos del informe de entrega: se piden aquí para que el script no abra cuadros de Windows. */
export function EntregaDialogo({ abierto, clienteInicial, alGenerar, alCancelar }: {
  abierto: boolean; clienteInicial: string; alGenerar: (d: { cliente: string; notas: string }) => void; alCancelar: () => void
}) {
  const ref = useRef<HTMLDialogElement>(null)
  const [cliente, setCliente] = useState('')
  const [notas, setNotas] = useState('')
  useEffect(() => {
    const d = ref.current
    if (!d) return
    if (abierto && !d.open) { setCliente(clienteInicial); setNotas(''); d.showModal() }
    if (!abierto && d.open) d.close()
  }, [abierto, clienteInicial])
  return (
    <dialog ref={ref} className="ancho" onCancel={(e) => { e.preventDefault(); alCancelar() }} aria-labelledby="entrega-titulo">
      <h2 id="entrega-titulo">Informe de entrega</h2>
      <p>Reúne el primer y el último diagnóstico guardados, los trabajos hechos y tus notas, listo para imprimir o guardar como PDF.</p>
      <label className="campo">Nombre del cliente (sale en el informe)<input maxLength={200} value={cliente} onChange={(e) => setCliente(e.target.value)} /></label>
      <label className="campo">Recomendaciones para el cliente (opcional)<textarea rows={3} maxLength={500} value={notas} onChange={(e) => setNotas(e.target.value)} /></label>
      <div className="pie-dialogo">
        <button className="boton" onClick={alCancelar}>Cancelar</button>
        <button className="boton principal-b" onClick={() => alGenerar({ cliente: cliente.trim(), notas: notas.trim() })}>Generar informe</button>
      </div>
    </dialog>
  )
}

/** Ficha de recepción del Modo taller. Los datos viven solo en memoria mientras la app está abierta y van al historial del diagnóstico. */
export function FichaDialogo({ abierto, ficha, alGuardar, alCancelar }: {
  abierto: boolean; ficha: { Cliente: string; Telefono: string; Motivo: string; Notas: string }
  alGuardar: (f: { Cliente: string; Telefono: string; Motivo: string; Notas: string }) => void; alCancelar: () => void
}) {
  const ref = useRef<HTMLDialogElement>(null)
  const [f, setF] = useState(ficha)
  useEffect(() => {
    const d = ref.current
    if (!d) return
    if (abierto && !d.open) { setF(ficha); d.showModal() }
    if (!abierto && d.open) d.close()
  }, [abierto, ficha])
  const campo = (k: keyof typeof f, et: string, largo = false) => (
    <label className="campo">{et}
      {largo
        ? <textarea rows={3} maxLength={500} value={f[k]} onChange={(e) => setF({ ...f, [k]: e.target.value })} />
        : <input maxLength={200} value={f[k]} onChange={(e) => setF({ ...f, [k]: e.target.value })} />}
    </label>
  )
  return (
    <dialog ref={ref} className="ancho" onCancel={(e) => { e.preventDefault(); alCancelar() }} aria-labelledby="ficha-titulo">
      <h2 id="ficha-titulo">Ficha de recepción</h2>
      <p>Se guarda con el diagnóstico en el historial de este equipo y sale en el informe de entrega.</p>
      {campo('Cliente', 'Cliente o empresa')}
      {campo('Telefono', 'Teléfono, contacto o nº de orden')}
      {campo('Motivo', 'Qué le pasa al equipo, según el cliente', true)}
      {campo('Notas', 'Observaciones del técnico (golpes, cargador, contraseña)', true)}
      <div className="pie-dialogo">
        <button className="boton" onClick={alCancelar}>Cancelar</button>
        <button className="boton principal-b" onClick={() => alGuardar({ Cliente: f.Cliente.trim(), Telefono: f.Telefono.trim(), Motivo: f.Motivo.trim(), Notas: f.Notas.trim() })}>Guardar ficha</button>
      </div>
    </dialog>
  )
}

/** Si una pantalla falla al pintarse, el resto de la app sigue viva y se puede reintentar. */
export class ErrorBoundary extends Component<{ children: ReactNode }, { fallo: string | null }> {
  state = { fallo: null as string | null }
  static getDerivedStateFromError(e: unknown) { return { fallo: e instanceof Error ? e.message : String(e) } }
  render() {
    if (this.state.fallo === null) return this.props.children
    return (
      <div className="pagina" role="alert">
        <h1 tabIndex={-1}>Esta pantalla ha fallado</h1>
        <p className="vacio">{this.state.fallo}</p>
        <div><button className="boton" onClick={() => this.setState({ fallo: null })}>Volver a intentarlo</button></div>
      </div>
    )
  }
}
