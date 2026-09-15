import react from '@vitejs/plugin-react'
import { defineConfig, type Plugin } from 'vite'

/**
 * NÃO habilite COOP/COEP aqui sem ler docs/PERFORMANCE.md § Fase 1.
 *
 * Resumo: cross-origin isolation liga o SharedArrayBuffer, que era o
 * pré-requisito do build wasm multi-thread do LiteRT. O isolamento funcionou
 * (`crossOriginIsolated === true`) e o app quebrou no load, porque o WebKit do
 * iPhone não tem relaxed SIMD e o LiteRT exige isso para o build threaded. Sem
 * relaxed SIMD o iOS já cai no build `compat` — o isolamento não dava ganho
 * nenhum lá, só o erro. Revisitar se Android/Chrome virar alvo.
 */

/**
 * Torna o `@litertjs/core` resolvível dentro de um Web Worker.
 *
 * O @ultralytics/yolo importa o backend LiteRT por especificador indireto
 * (`const pkg = "@litertjs/core"; await import(/* @vite-ignore *\/ pkg)`), de
 * propósito: assim o peer dep opcional fica fora do grafo de build. Na página
 * isso funciona porque o index.html traz um import map.
 *
 * **Workers não suportam import map.** Um especificador cru lá falha na
 * resolução, antes de virar request — não há URL para redirecionar nem
 * middleware que intercepte. Como mover a inferência para um worker é o que
 * permite cortar o throttle sem travar a UI (docs/PERFORMANCE.md § E7), este
 * plugin reescreve aquela única linha para um import literal, que o Vite então
 * resolve e empacota normalmente — na página e no worker.
 *
 * Falha o build se o trecho mudar, em vez de degradar silenciosamente: uma
 * atualização do @ultralytics/yolo que reescreva essa função precisa ser vista.
 */
const NEEDLE = 'return (await import(/* @vite-ignore */ pkg));'
const REPLACEMENT = "return (await import('@litertjs/core'));"

const resolveLiteRtInWorkers = (): Plugin => ({
  name: 'vizi:resolve-litert-in-workers',
  enforce: 'pre',
  transform(code, id) {
    if (!id.includes('@ultralytics/yolo')) return null
    if (!code.includes('importLiteRt')) return null

    if (!code.includes(NEEDLE)) {
      this.error(
        'vizi:resolve-litert-in-workers não encontrou o import indireto do ' +
          '@litertjs/core em @ultralytics/yolo. A lib provavelmente mudou; ' +
          'reveja importLiteRt() no dist dela e ajuste NEEDLE no vite.config.ts.'
      )
    }

    return { code: code.replace(NEEDLE, REPLACEMENT), map: null }
  },
})

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), resolveLiteRtInWorkers()],
  // O plugin acima precisa ver o fonte da lib. Sem isto o Vite serve em dev uma
  // versão pré-empacotada por esbuild, na qual hooks de transform não rodam.
  optimizeDeps: { exclude: ['@ultralytics/yolo'] },
  server: {
    host: true,
    allowedHosts: ["0eaa-2804-7f5-f216-29f-9b94-5abd-669a-45b1.ngrok-free.app"],
  },
})
