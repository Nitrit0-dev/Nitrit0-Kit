import { createRoot } from 'react-dom/client'
import '../../renderer/src/diseno/tokens.css'
import '../../renderer/src/diseno/componentes.css'
import './limpieza.css'
import App from './App'

createRoot(document.getElementById('raiz')!).render(<App />)
