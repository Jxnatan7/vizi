import { useState, useEffect } from 'react';
import { YOLO } from '@ultralytics/yolo';
import { modelUrl } from '../lib/debugFlags';

/**
 * Backends aceitos pela lib. 'auto' escolhe WebGPU quando existe adapter, o que
 * na prática divide desktop (WebGPU) de iOS Safari (CPU/wasm) — daí a
 * possibilidade de forçar um deles para reproduzir o caminho do celular.
 */
export type ModelDevice = 'auto' | 'webgpu' | 'cpu';

export const useYoloModel = (deviceOverride: ModelDevice = 'auto') => {
  const [model, setModel] = useState<YOLO | null>(null);
  const [isModelLoaded, setIsModelLoaded] = useState(false);
  const [device, setDevice] = useState<string | null>(null);
  const [task, setTask] = useState<string | null>(null);
  const [names, setNames] = useState<Record<number, string>>({});
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let isMounted = true;
    let loaded: YOLO | null = null;

    const initModel = async () => {
      try {
        // 'auto' usa WebGPU quando o browser tem adapter e cai para CPU/wasm
        // (caso do Safari).
        //
        // Os .wasm do LiteRT vêm de /litert/, copiados de node_modules por
        // `npm run vendor`, em vez do CDN padrão (jsDelivr). Isso nasceu como
        // pré-requisito do COOP/COEP — que acabou revertido, ver
        // docs/PERFORMANCE.md § E1 — mas ficou por mérito próprio: tira um
        // terceiro do caminho crítico do load, fixa a versão junto com o
        // package.json e é o que permite cachear os binários offline.
        loaded = await YOLO.load(modelUrl, {
          device: deviceOverride,
          litertWasmUrl: new URL('/litert/', location.origin).href
        });

        if (isMounted) {
          setModel(loaded);
          setDevice(loaded.device);
          setTask(loaded.task);
          setNames(loaded.names);
          setIsModelLoaded(true);
        } else {
          loaded.free(); // Desmontou durante o load: libera o wasm imediatamente
        }
      } catch (err) {
        console.error('Falha ao carregar o modelo YOLO:', err);
        // A mensagem do erro entra no texto: no iOS não há devtools à mão, e
        // essa string é a única pista que chega ao usuário.
        if (isMounted) setError(`Erro ao carregar o modelo de IA: ${String(err)}`);
      }
    };

    initModel();

    return () => {
      isMounted = false; // Evita memory leaks se o componente desmontar antes do load
      loaded?.free(); // Diferente do TFJS, o backend wasm exige liberação explícita
    };
  }, [deviceOverride]);

  return { model, isModelLoaded, device, task, names, error };
};
