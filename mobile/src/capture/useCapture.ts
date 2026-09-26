import { useCallback, useState } from 'react';

import { ViziVision, type CaptureResult, type HistoryEntry } from '../../modules/vizi-vision';
import { saveResult } from '../history/store';

import { DEFAULT_CAPTURE } from './options';

export type CaptureState = 'live' | 'capturing' | 'result';

export function useCapture() {
  const [state, setState] = useState<CaptureState>('live');
  const [diagnostics, setDiagnostics] = useState(false);
  const [result, setResult] = useState<CaptureResult | null>(null);
  const [capturedAt, setCapturedAt] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState<HistoryEntry | null>(null);
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  const capture = useCallback(async () => {
    setError(null);
    setSaved(null);
    setSaveError(null);
    // 'capturing' aparece imediatamente: a troca de formato da câmera leva
    // alguns décimos de segundo e a tela não pode ficar sem resposta.
    setState('capturing');
    try {
      const r = await ViziVision.capture({ ...DEFAULT_CAPTURE, diagnostics });
      setResult(r);
      setCapturedAt(Date.now());
      setState('result');
    } catch (e) {
      setError(String(e));
      setState('live');
    }
  }, [diagnostics]);

  const dismiss = useCallback(async () => {
    await ViziVision.dismissResult();
    setResult(null);
    setSaved(null);
    setSaveError(null);
    setState('live');
  }, []);

  /** Uma vez por resultado: o botão some depois de salvar. */
  const save = useCallback(async () => {
    if (!result || saving || saved) return;
    setSaving(true);
    setSaveError(null);
    try {
      setSaved(await saveResult(result, capturedAt));
    } catch (e) {
      setSaveError(String(e));
    } finally {
      setSaving(false);
    }
  }, [result, capturedAt, saving, saved]);

  /**
   * A sessão parou com o resultado na tela — segundo plano, por exemplo. O
   * nativo já desfez o resultado; sem isto a tela continuaria oferecendo
   * salvar uma imagem que não existe mais.
   */
  const reset = useCallback(() => {
    setResult(null);
    setSaved(null);
    setSaveError(null);
    setState('live');
  }, []);

  return {
    state, result, error, capture, dismiss, diagnostics, setDiagnostics,
    save, saving, saved, saveError, reset,
  };
}
