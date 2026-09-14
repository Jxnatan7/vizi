import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)

/**
 * Registra o Service Worker que cacheia o modelo (13 MB) e o wasm do LiteRT.
 *
 * Depois do `load` de propósito: registrar cedo compete por banda justamente com
 * o download que se quer acelerar na primeira visita. Em dev fica de fora — um
 * SW cacheando durante o desenvolvimento só produz confusão.
 *
 * Falha em silêncio: sem HTTPS, sem suporte ou com registro negado, o app
 * funciona igual, só sem cache.
 */
if ('serviceWorker' in navigator && import.meta.env.PROD) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch((error) => {
      console.warn('Service Worker não registrado; o app segue sem cache:', error)
    })
  })
}
