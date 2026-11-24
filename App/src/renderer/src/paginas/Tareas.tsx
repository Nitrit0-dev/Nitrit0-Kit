import type { ReactNode } from 'react'
import { ChevronRight, FileText, HardDrive, ListChecks, Package, SlidersHorizontal, Stethoscope, Wrench } from 'lucide-react'
import { PageHeader } from '../componentes/Basicos'
import { PerfilTarjetas } from '../componentes/PerfilUso'
import { usaEjecutor, verbo, type Elemento, type IdPerfil } from '../tipos'

interface Tarjeta { id: string; titulo: string; texto: string; icono: ReactNode; alPulsar: () => void; apagada?: boolean }


/**
 * Portada del modo técnico: lo que se hace a diario, con una frase cada cosa, sin guía paso a paso (el «Arreglar mi equipo» guiado es del modo sencillo).
 * Las tarjetas llevan a herramientas y pantallas que ya existen. Solo aparece lo que se puede usar.
 */
export default function Tareas({ instalada, hayInstalacion, puedeInstalar, memoriaAuto, alInstalar, alQuitarInstalacion, alMemoria, alMemoriaAuto, perfil, arranque, alPerfil, alArranque, elementos, favoritas, ocupado, totalHerramientas, alLanzar, alDiagnostico, alCombos, alAjustes, alHerramientas, alEntrega }: {
  instalada: boolean; hayInstalacion: boolean; puedeInstalar: boolean; memoriaAuto: boolean; alInstalar: () => void; alQuitarInstalacion: () => void; alMemoria: () => void; alMemoriaAuto: (on: boolean) => void
  perfil: IdPerfil | null; arranque: boolean; alPerfil: (id: IdPerfil) => void; alArranque: (on: boolean) => void
  elementos: Elemento[]; favoritas: string[]; ocupado: boolean; totalHerramientas: number
  alLanzar: (e: Elemento) => void; alDiagnostico: () => void; alCombos: () => void; alAjustes: () => void; alHerramientas: () => void; alEntrega: () => void
}) {
  const porId = (id: string) => elementos.find((e) => e.id === id && e.soportado && e.disponible)
  const quitar = porId('Desinstalar_Bloatware_Win11.ps1'), espacio = porId('Analizar_Espacio_Disco.ps1'), entrega = porId('Informe_Entrega.ps1')
  const favs = favoritas.map((t) => elementos.find((e) => e.titulo === t)).filter((e): e is Elemento => !!e && e.soportado && e.disponible)

  const pequenas: Tarjeta[] = [
    { id: 'diagnostico', titulo: 'Diagnóstico', texto: 'Las pruebas del equipo una a una, con resultado y qué hacer.', icono: <Stethoscope size={20} strokeWidth={1.75} />, alPulsar: alDiagnostico },
    ...(quitar ? [{ id: 'quitar', titulo: 'Quitar programas de fábrica', texto: 'Lo que viene con Windows y no se usa. Antes de quitar nada se crea un punto de restauración.', icono: <Package size={20} strokeWidth={1.75} />, alPulsar: () => alLanzar(quitar), apagada: ocupado && usaEjecutor(quitar) }] : []),
    ...(espacio ? [{ id: 'espacio', titulo: 'Espacio en disco', texto: 'Qué ocupa más y qué se puede borrar sin riesgo.', icono: <HardDrive size={20} strokeWidth={1.75} />, alPulsar: () => alLanzar(espacio), apagada: ocupado && usaEjecutor(espacio) }] : []),
    ...(entrega ? [{ id: 'entrega', titulo: 'Informe para el cliente', texto: 'Lo que se ha hecho y cómo ha quedado, listo para imprimir.', icono: <FileText size={20} strokeWidth={1.75} />, alPulsar: alEntrega, apagada: ocupado }] : []),
    { id: 'ajustes', titulo: 'Ajustes de Windows', texto: 'Cómo está cada ajuste ahora y cuál recomendamos. Todo se puede deshacer.', icono: <SlidersHorizontal size={20} strokeWidth={1.75} />, alPulsar: alAjustes },
    { id: 'combos', titulo: 'Combos de mantenimiento', texto: 'Varios pasos seguidos con una sola confirmación previa.', icono: <ListChecks size={20} strokeWidth={1.75} />, alPulsar: alCombos },
    { id: 'herramientas', titulo: 'Todas las herramientas', texto: `${totalHerramientas} herramientas con buscador, filtros y favoritas.`, icono: <Wrench size={20} strokeWidth={1.75} />, alPulsar: alHerramientas }
  ]
  const tarjeta = (t: Tarjeta) => (
    <button key={t.id} className="tarjeta" disabled={t.apagada} onClick={t.alPulsar}>
      <span className="tarjeta-ficha" aria-hidden="true">{t.icono}</span>
      <b>{t.titulo}</b>
      <span className="tarjeta-texto">{t.texto}</span>
      <ChevronRight className="tarjeta-flecha" size={18} strokeWidth={1.75} aria-hidden="true" />
    </button>
  )

  return (
    <div className="pagina">
      <PageHeader titulo="¿Qué quieres hacer hoy?" subtitulo="Lo que se usa a diario, con una frase cada cosa." />
      {ocupado && <p className="aviso-txt">Hay otra cosa en marcha: lo que usa el ejecutor espera a que termine.</p>}
      <section className="bloque" aria-label="Modo del equipo">
        <h2>Modo del equipo</h2>
        <PerfilTarjetas actual={perfil} ocupado={ocupado} alElegir={alPerfil} />
        <div className="arranque-fila">
          <span className="sub-linea"><b>En este equipo</b> · {instalada ? 'Instalada en Archivos de programa (icono junto al reloj)' : hayInstalacion ? 'Copia instalada en Archivos de programa' : 'Instalar copia ligera (menú Inicio e icono junto al reloj)'}</span>
          <div className="arranque-controles">
            <button className="interruptor" role="switch" aria-label="Arrancar con Windows" aria-checked={arranque} disabled={!instalada && !arranque} title={!instalada && !arranque ? 'Primero pulsa «Instalar en este equipo»' : undefined} onClick={() => alArranque(!arranque)}><span className="texto">Arrancar con Windows</span><span className="pista" /></button>
            {(puedeInstalar || hayInstalacion) && <button className="boton" disabled={ocupado} onClick={hayInstalacion ? alQuitarInstalacion : alInstalar}>{hayInstalacion ? 'Quitar instalación' : 'Instalar en este equipo'}</button>}
          </div>
        </div>
        <div className="arranque-fila">
          <span className="sub-linea"><b>Memoria RAM</b> · Libera procesos inactivos (alivio momentáneo)</span>
          <div className="arranque-controles">
            <button className="interruptor" role="switch" aria-label="Liberar memoria sola cuando la RAM pase del 90 %" aria-checked={memoriaAuto} onClick={() => alMemoriaAuto(!memoriaAuto)}><span className="texto">Sola al 90 %</span><span className="pista" /></button>
            <button className="boton" onClick={alMemoria}>Liberar memoria ahora</button>
          </div>
        </div>
      </section>
      <div className="tarjetas" role="group" aria-label="Más tareas">{pequenas.map(tarjeta)}</div>
      <section className="bloque" aria-label="Favoritas">
        <h2>Tus favoritas</h2>
        {favs.length === 0 && <p className="nota-vacia">Marca la estrella de una herramienta y aparecerá aquí.</p>}
        {favs.map((e) => (
          <div className="fila-simple" key={e.id}>
            <span>{e.titulo}</span>
            <button className="boton" disabled={ocupado && usaEjecutor(e)} onClick={() => alLanzar(e)} aria-label={`${verbo(e)} ${e.titulo}`}>{verbo(e)}</button>
          </div>
        ))}
      </section>
    </div>
  )
}
