import { useCallback, useState } from 'react';

import {
  ViziVision, type CaptureResult, type CollectionTags, type HistoryEntry,
} from '../../modules/vizi-vision';
import { FAST_CAPTURE } from '../collection/policy';
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

  /**
   * `tags` é a escolha da câmera, que a coleta grava com o item (spec 008).
   *
   * `fast` é o modo rápido do treino (R48): sem aproximação, sem
   * endireitamento e sem diagnóstico, e a câmera volta assim que o resultado
   * chega — ele nunca vira o estado `'result'`. A captura roda inteira e é
   * gravada igual. Resolve com o resultado, para quem chamou anotar o item; com
   * `null` quando a captura falhou.
   */
  const capture = useCallback(async (
    { tags = null, fast = false }: { tags?: CollectionTags | null; fast?: boolean } = {},
  ): Promise<CaptureResult | null> => {
    setError(null);
    setSaved(null);
    setSaveError(null);
    // 'capturing' aparece imediatamente: a troca de formato da câmera leva
    // alguns décimos de segundo e a tela não pode ficar sem resposta.
    setState('capturing');
    try {
      const options = fast
        ? { ...DEFAULT_CAPTURE, ...FAST_CAPTURE, diagnostics: false }
        : { ...DEFAULT_CAPTURE, diagnostics };
      const r = await ViziVision.capture(options, tags);
      if (fast) {
        await ViziVision.dismissResult();
        setState('live');
        return r;
      }
      setResult(r);
      setCapturedAt(Date.now());
      setState('result');
      return r;
    } catch (e) {
      setError(String(e));
      setState('live');
      return null;
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
