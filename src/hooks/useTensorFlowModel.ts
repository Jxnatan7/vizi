import { useState, useEffect } from 'react';
import * as tf from '@tensorflow/tfjs';
import '@tensorflow/tfjs-backend-webgl';
import * as cocoSsd from '@tensorflow-models/coco-ssd';

export const useTensorFlowModel = () => {
  const [model, setModel] = useState<cocoSsd.ObjectDetection | null>(null);
  const [isModelLoaded, setIsModelLoaded] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let isMounted = true;

    const initModel = async () => {
      try {
        await tf.setBackend('webgl');
        await tf.ready();
        const loadedModel = await cocoSsd.load();
        
        if (isMounted) {
          setModel(loadedModel);
          setIsModelLoaded(true);
        }
      } catch (err) {
        console.error('Falha ao inicializar o TensorFlow:', err);
        if (isMounted) setError('Erro ao carregar o modelo de IA.');
      }
    };

    initModel();

    return () => {
      isMounted = false; // Evita memory leaks se o componente desmontar antes do load
    };
  }, []);

  return { model, isModelLoaded, error };
};