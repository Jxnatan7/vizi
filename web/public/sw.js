/**
 * Service Worker do vizi. Existe por um motivo só: o modelo tem 13 MB e hoje é
 * baixado inteiro a cada abertura, antes da primeira detecção.
 *
 * Estratégia cache-first para os artefatos grandes e imutáveis (modelo e wasm
 * do LiteRT). O resto passa direto — o bundle já é versionado pelo Vite e não
 * vale o risco de servir HTML velho.
 *
 * ⚠️ ARMADILHA DO MODELO: cache-first serve o arquivo cacheado para sempre. Ao
 * exportar um modelo novo, **mude o nome do arquivo** (ex.: `yolo-seg-320.tflite`)
 * e o `MODEL_URL` em src/hooks/useYoloModel.ts. URL nova = entrada nova. Trocar
 * o conteúdo mantendo o nome faz todo usuário que já abriu o app continuar com o
 * modelo antigo, sem nenhum sintoma visível.
 *
 * Alternativa se algum dia isso escapar: subir CACHE_VERSION, que descarta tudo.
 */

const CACHE_VERSION = 'v1';
const CACHE_NAME = `vizi-assets-${CACHE_VERSION}`;

/** Prefixos servidos do cache quando disponíveis. */
const CACHEABLE_PREFIXES = ['/models/', '/litert/'];

const isCacheable = (url) =>
  url.origin === self.location.origin &&
  CACHEABLE_PREFIXES.some((prefix) => url.pathname.startsWith(prefix));

// Assume o controle assim que instalado, em vez de esperar a próxima abertura:
// o ganho é justamente na primeira visita seguinte.
self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const names = await caches.keys();
      await Promise.all(
        names.filter((name) => name !== CACHE_NAME).map((name) => caches.delete(name))
      );
      await self.clients.claim();
    })()
  );
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (!isCacheable(url)) return;

  event.respondWith(
    (async () => {
      const cache = await caches.open(CACHE_NAME);
      const cached = await cache.match(request);
      if (cached) return cached;

      const response = await fetch(request);

      // Só guarda resposta completa e boa. Um 206/opaque no cache quebraria o
      // .tflite, cujo metadata vive num ZIP anexado ao fim do arquivo: servir
      // um arquivo truncado derruba model.names sem erro visível.
      if (response.ok && response.status === 200) {
        cache.put(request, response.clone());
      }

      return response;
    })()
  );
});
