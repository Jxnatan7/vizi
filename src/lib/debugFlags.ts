import type { ModelDevice } from '../hooks/useYoloModel';
import { prefersCpuBackend } from './platform';

/**
 * Flags de diagnóstico lidas da query string, para investigar no celular, onde
 * não há devtools à mão:
 *
 *   ?debug=1        mostra o painel com os números de cada inferência
 *   ?device=cpu     força o caminho CPU/wasm
 *   ?device=webgpu  força o caminho GPU, inclusive onde ele é evitado por padrão
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
