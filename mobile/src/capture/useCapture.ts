import { useCallback, useState } from 'react';

import { ViziVision, type CaptureResult } from '../../modules/vizi-vision';

import { DEFAULT_CAPTURE } from './options';

export type CaptureState = 'live' | 'capturing' | 'result';

export function useCapture() {
  const [state, setState] = useState<CaptureState>('live');
  const [diagnostics, setDiagnostics] = useState(false);
  const [result, setResult] = useState<CaptureResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  const capture = useCallback(async () => {
    setError(null);
    // 'capturing' aparece imediatamente: a troca de formato da câmera leva
    // alguns décimos de segundo e a tela não pode ficar sem resposta.
    setState('capturing');
    try {
      const r = await ViziVision.capture({ ...DEFAULT_CAPTURE, diagnostics });
      setResult(r);
      setState('result');
    } catch (e) {
      setError(String(e));
      setState('live');
    }
  }, [diagnostics]);

  const dismiss = useCallback(async () => {
    await ViziVision.dismissResult();
    setResult(null);
    setState('live');
  }, []);

  return { state, result, error, capture, dismiss, diagnostics, setDiagnostics };
}
