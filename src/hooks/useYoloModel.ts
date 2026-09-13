import { useState, useEffect } from 'react';
import { YOLO } from '@ultralytics/yolo';

// O modelo vive em public/models, então é servido a partir da raiz.
const MODEL_URL = '/models/yolo.tflite';

export const useYoloModel = () => {
  const [model, setModel] = useState<YOLO | null>(null);
  const [isModelLoaded, setIsModelLoaded] = useState(false);
  const [device, setDevice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let isMounted = true;
    let loaded: YOLO | null = null;

    const initModel = async () => {
      try {
        // 'auto' usa WebGPU quando o browser tem adapter e cai para CPU/wasm
        // (caso do Safari). Os .wasm do LiteRT vêm do CDN padrão.
        loaded = await YOLO.load(MODEL_URL, { device: 'auto' });

        if (isMounted) {
          setModel(loaded);
          setDevice(loaded.device);
          setIsModelLoaded(true);
        } else {
          loaded.free(); // Desmontou durante o load: libera o wasm imediatamente
        }
      } catch (err) {
        console.error('Falha ao carregar o modelo YOLO:', err);
        if (isMounted) setError('Erro ao carregar o modelo de IA.');
      }
    };

    initModel();

    return () => {
      isMounted = false; // Evita memory leaks se o componente desmontar antes do load
      loaded?.free(); // Diferente do TFJS, o backend wasm exige liberação explícita
    };
  }, []);

  return { model, isModelLoaded, device, error };
};
