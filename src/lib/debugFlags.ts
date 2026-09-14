import type { ModelDevice } from '../hooks/useYoloModel';
import { prefersCpuBackend } from './platform';
import { DEFAULT_MOTION_THRESHOLD } from './motion';

/**
 * Flags de diagnóstico lidas da query string, para investigar no celular, onde
 * não há devtools à mão:
 *
 *   ?debug=1        mostra o painel com os números de cada inferência
 *   ?device=cpu     força o caminho CPU/wasm
 *   ?device=webgpu  força o caminho GPU, inclusive onde ele é evitado por padrão
 *   ?model=low      modelo exportado a 320 (?model=high para 640, ?model=v1 para o antigo)
 *   ?interval=N     intervalo mínimo entre inferências em ms (padrão 0)
 *   ?motion=N       limiar de movimento; ?motion=off desliga o gating
 *
 * Lidas uma vez na carga: mudar a URL exige recarregar, que é o que se quer
 * mesmo — trocar de backend recompila o modelo.
 */
const params = new URLSearchParams(window.location.search);

const requestedDevice = params.get('device');

export const debugEnabled = params.get('debug') === '1';

/**
 * A query string manda; sem ela, o WebKit vai para CPU porque o delegate
 * WebGPU devolve resultado vazio na segmentação (ver prefersCpuBackend).
 */
export const deviceOverride: ModelDevice =
  requestedDevice === 'cpu' || requestedDevice === 'webgpu'
    ? requestedDevice
    : prefersCpuBackend
      ? 'cpu'
      : 'auto';

/**
 * Sem throttle, por medição.
 *
 * O loop nasceu com 100ms de respiro entre inferências, para a main thread não
 * ficar monopolizada pelo wasm. Isso custava ~106ms de ociosidade num ciclo de
 * ~400ms — 26%. Testado no aparelho com `?interval=0`, a UI continuou
 * respondendo bem (slider e botões), então o respiro saiu.
 *
 * O que protege o aparelho agora não é ociosidade cega, é o motion gating
 * (ver `motionThreshold`): parado não se infere, e movendo-se usa-se tudo.
 */
const DEFAULT_DETECTION_INTERVAL_MS = 0;

/**
 * Intervalo mínimo entre inferências, em ms, sobrescrevível por `?interval=N`.
 * Mantido depois da medição para poder reintroduzir respiro num aparelho mais
 * fraco sem recompilar.
 *
 * Valor inválido cai no padrão: um typo na URL não pode virar um loop sem
 * throttle sem que ninguém perceba.
 */
export const detectionIntervalMs: number = (() => {
  const raw = params.get('interval');
  if (raw === null) return DEFAULT_DETECTION_INTERVAL_MS;

  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : DEFAULT_DETECTION_INTERVAL_MS;
})();

/**
 * Limiar do motion gating, em diferença média por pixel (0-255).
 * `?motion=N` calibra, `?motion=off` desliga o gating por completo — útil para
 * comparar contra o comportamento antigo ou investigar uma detecção que sumiu.
 */
export const motionThreshold: number = (() => {
  const raw = params.get('motion');
  if (raw === null) return DEFAULT_MOTION_THRESHOLD;
  if (raw === 'off') return 0; // 0 nunca bloqueia: toda leitura é >= 0.

  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : DEFAULT_MOTION_THRESHOLD;
})();

/**
 * Modelos disponíveis em public/models.
 *
 * `high` e `low` saíram do mesmo treino e diferem só no `imgsz` do export:
 * 640x640 contra 320x320. Como o custo da inferência é quadrático na resolução
 * de entrada, `low` deve rodar perto de 4x mais rápido — é a maior alavanca
 * isolada que sobrou depois que todas as otimizações de app foram aplicadas
 * (ver docs/PERFORMANCE.md). O que ele custa em precisão só a comparação lado a
 * lado responde.
 *
 * `v1` é o modelo original, treinado com menos imagens, mantido para separar
 * "o que mudou por causa do dataset" de "o que mudou por causa do imgsz".
 *
 * ⚠️ O `<link rel="preload">` do index.html deriva a URL da mesma forma. Mexer
 * nos nomes aqui exige mexer lá, senão o preload baixa 13 MB do arquivo errado.
 */
const MODEL_URLS = {
  high: '/models/best-high.tflite',
  low: '/models/best-low.tflite',
  v1: '/models/yolo-seg.tflite'
} as const;

export type ModelVariant = keyof typeof MODEL_URLS;

/**
 * Qual modelo carregar. O padrão é `high`: mesmo `imgsz` do modelo que o app já
 * usava, então trocar de padrão não muda o desempenho sem aviso — só a
 * qualidade, que vem do dataset maior.
 */
export const modelVariant: ModelVariant = (() => {
  const raw = params.get('model');
  return raw !== null && raw in MODEL_URLS ? (raw as ModelVariant) : 'high';
})();

export const modelUrl: string = MODEL_URLS[modelVariant];
