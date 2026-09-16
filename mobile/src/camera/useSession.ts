import { useCallback, useEffect, useRef, useState } from 'react';
import { AppState } from 'react-native';

import {
  ViziVision,
  type SessionInfo,
  type SessionOptions,
  type Session,
  type TelemetrySample,
  type TransformMode,
} from '../../modules/vizi-vision';

/** Política da sessão. Vive em TypeScript — princípio IV. */
export const DEFAULT_SESSION: SessionOptions = {
  sampleIntervalMs: 500,
  // 'stretch' é o padrão do Roboflow. Ainda NÃO confirmado — ver US3.
  transform: 'stretch',
  confidenceThreshold: 0.25,
  iouThreshold: 0.7,
};

export function useSession() {
  const [info, setInfo] = useState<SessionInfo | null>(null);
  const [sample, setSample] = useState<TelemetrySample | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [error, setError] = useState<string | null>(null);
  const running = useRef(false);

  useEffect(() => {
    // Uma assinatura para a vida da tela. O nativo já agrega a ~2 Hz, então
    // este setState acontece duas vezes por segundo — não sessenta.
    const sub = ViziVision.addListener('onTelemetry', setSample);
    return () => sub.remove();
  }, []);

  const [transform, setTransformState] = useState<TransformMode>(DEFAULT_SESSION.transform);

  const setTransform = useCallback(async (next: TransformMode) => {
    setTransformState(next);
    if (running.current) await ViziVision.setTransform(next);
  }, []);

  const start = useCallback(async () => {
    setError(null);
    try {
      if (!(await ViziVision.hasCameraPermission())) {
        if (!(await ViziVision.requestCameraPermission())) {
          setError('Permissão de câmera negada. Conceda em Ajustes → vizi → Câmera.');
          return;
        }
      }
      setSession(null);
      setInfo(await ViziVision.startSession({ ...DEFAULT_SESSION, transform }));
      running.current = true;
    } catch (e) {
      setError(String(e));
    }
  }, [transform]);

  const stop = useCallback(async () => {
    if (!running.current) return;
    try {
      setSession(await ViziVision.stopSession());
    } catch (e) {
      setError(String(e));
    } finally {
      running.current = false;
      setInfo(null);
      setSample(null);
    }
  }, []);

  // A câmera não pode sobreviver à tela nem ao segundo plano: continuaria
  // gastando bateria e aquecendo o aparelho, que é exatamente o que este marco
  // mede. FR-010.
  useEffect(() => {
    const sub = AppState.addEventListener('change', (state) => {
      if (state !== 'active' && running.current) void stop();
    });
    return () => sub.remove();
  }, [stop]);

  useEffect(() => () => void stop(), [stop]);

  return {
    info, sample, session, error, transform,
    start, stop, setTransform, isRunning: running.current,
  };
}
