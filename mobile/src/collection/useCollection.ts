import { useCallback, useEffect, useState } from 'react';

import {
  ViziVision,
  type CollectionState,
  type CollectionSummary,
  type ExportOutcome,
  type MarkReceipt,
} from '../../modules/vizi-vision';
import { DEFAULT_BAND } from '../band/policy';
import { DEFAULT_SESSION } from '../camera/useSession';
import { DEFAULT_CAPTURE } from '../capture/options';
import { DEFAULT_OVERLAY } from '../overlay/style';
import { DEFAULT_COLLECTION } from './policy';

/**
 * As recusas do nativo chegam como "código: frase" (contrato da 007). A tela
 * mostra o que fazer, não o código.
 */
const MESSAGES: Record<string, string> = {
  closed: 'O modo coleta está desligado.',
  camera: 'Inicie a câmera para marcar.',
  busy: 'Espere a captura terminar, ou volte à câmera, antes de marcar.',
  space: 'Pouco espaço livre no aparelho: a coleta não grava mais.',
  stale: 'Este item não espera mais resposta.',
  open: 'Desligue o modo coleta antes.',
  missing: 'A sessão não existe mais.',
};

export function collectionMessage(e: unknown): string {
  const text = e instanceof Error ? e.message : String(e);
  // O Expo embrulha a mensagem ("Calling the 'markFrame' function has failed
  // → Caused by: busy: …"): o código pode estar no meio.
  const match = /\b(closed|camera|busy|space|stale|open|missing|invalid|export): (.*)/.exec(text);
  if (!match) return text;
  return MESSAGES[match[1]] ?? match[2];
}

/**
 * Espelha a coleta do nativo, que é o dono (spec 007, R36).
 *
 * O estado de React muda só em mudança discreta — abrir, fechar, item
 * gravado, resposta gravada —, porque é só aí que o nativo avisa.
 */
export function useCollection() {
  const [state, setState] = useState<CollectionState>(() => ViziVision.getCollectionState());

  useEffect(() => {
    const sub = ViziVision.addListener('onCollectionChange', setState);
    // Algo pode ter mudado entre o primeiro desenho e a assinatura.
    setState(ViziVision.getCollectionState());
    return () => sub.remove();
  }, []);

  /** Abre a sessão com as políticas em vigor, que vão para o registro como estão. */
  const start = useCallback(async () => {
    setState(await ViziVision.startCollection({
      ...DEFAULT_COLLECTION,
      policies: {
        session: DEFAULT_SESSION,
        capture: DEFAULT_CAPTURE,
        band: DEFAULT_BAND,
        overlay: DEFAULT_OVERLAY,
        collection: DEFAULT_COLLECTION,
      },
    }));
  }, []);

  const stop = useCallback(async () => {
    setState(await ViziVision.stopCollection());
  }, []);

  /** A contagem real do item que espera resposta; `null` = pulou. */
  const answer = useCallback(
    (itemId: string, count: number | null) => ViziVision.answerItem(itemId, count),
    [],
  );

  /** Resolve com o quadro já parado na tela. */
  const mark = useCallback((): Promise<MarkReceipt> => ViziVision.markFrame(), []);

  const resume = useCallback(() => ViziVision.resumeLive(), []);

  return { state, start, stop, answer, mark, resume };
}

/** As sessões no aparelho, para a Medição. Recarrega a cada mudança da coleta. */
export function useCollectionSessions() {
  const [sessions, setSessions] = useState<CollectionSummary[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const reload = useCallback(async () => {
    try {
      setSessions(await ViziVision.listCollections());
      setError(null);
    } catch (e) {
      setError(collectionMessage(e));
      setSessions([]);
    }
  }, []);

  useEffect(() => {
    void reload();
    const sub = ViziVision.addListener('onCollectionChange', () => void reload());
    return () => sub.remove();
  }, [reload]);

  /** Gera o zip e abre o menu de compartilhar; resolve quando ele fecha. */
  const exportSession = useCallback(async (id: string): Promise<ExportOutcome> => {
    const outcome = await ViziVision.exportCollection(id);
    await reload();
    return outcome;
  }, [reload]);

  const rename = useCallback(async (id: string, name: string) => {
    await ViziVision.renameCollection(id, name);
    await reload();
  }, [reload]);

  const remove = useCallback(async (id: string) => {
    await ViziVision.deleteCollection(id);
    await reload();
  }, [reload]);

  return { sessions, error, reload, exportSession, rename, remove };
}
