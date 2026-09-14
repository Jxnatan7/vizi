const ua = navigator.userAgent;

// Todo browser no iOS é obrigado a usar o WebKit do sistema, então Chrome e
// Firefox de iPhone caem aqui junto com o Safari. O iPadOS se declara Mac, daí
// o desempate por maxTouchPoints.
const isIOS =
  /iP(hone|ad|od)/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

const isDesktopSafari = /^((?!chrome|chromium|android|crios|fxios|edgios).)*safari/i.test(ua);

/**
 * O delegate WebGPU do LiteRT no WebKit compila o modelo de segmentação, roda
 * em poucos milissegundos e devolve tudo zerado — nenhuma caixa e nenhuma
 * máscara — sem lançar erro. O caminho CPU/wasm produz o resultado correto.
 *
 * É o mesmo tipo de contorno que a própria lib aplica a modelos NMS-free e ao
 * RT-DETR, onde o delegate também não dá conta do grafo. Use ?device=webgpu
 * para reavaliar quando o WebKit melhorar.
 */
export const prefersCpuBackend = isIOS || isDesktopSafari;
