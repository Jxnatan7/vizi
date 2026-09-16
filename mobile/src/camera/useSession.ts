import { useCallback, useEffect, useRef, useState } from 'react';

import {
  ViziVision,
  type SessionInfo,
  type SessionSummary,
  type TelemetrySample,
} from '../../modules/vizi-vision';

/** Política da sessão. Vive em TypeScript — princípio IV. */
export const SAMPLE_INTERVAL_MS = 500;

export function useSession() {
  const [info, setInfo] = useState<SessionInfo | null>(null);
  const [sample, setSample] = useState<TelemetrySample | null>(null);
  const [summary, setSummary] = useState<SessionSummary | null>(null);
  const [error, setError] = useState<string | null>(null);
  const running = useRef(false);

  useEffect(() => {
    // Uma assinatura para a vida da tela. O nativo já agrega a ~2 Hz, então
    // este setState acontece duas vezes por segundo — não sessenta.
    const sub = ViziVision.addListener('onTelemetry', setSample);
    return () => sub.remove();
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
      setSummary(null);
      setInfo(await ViziVision.startSession({ sampleIntervalMs: SAMPLE_INTERVAL_MS }));
      running.current = true;
    } catch (e) {
      setError(String(e));
    }
  }, []);

  const stop = useCallback(async () => {
    if (!running.current) return;
    try {
      setSummary(await ViziVision.stopSession());
    } catch (e) {
      setError(String(e));
    } finally {
      running.current = false;
      setInfo(null);
      setSample(null);
    }
  }, []);

  // A câmera não pode sobreviver à tela: continuaria gastando bateria e
  // aquecendo o aparelho, que é exatamente o que este marco mede.
  useEffect(() => () => void stop(), [stop]);

  return { info, sample, summary, error, start, stop, isRunning: running.current };
}
