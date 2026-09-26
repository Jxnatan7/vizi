import { useCallback, useEffect, useRef, useState } from 'react';

import { ViziVision, type BandMode, type BandState } from '../../modules/vizi-vision';

/**
 * Espelha a faixa do nativo, que é a fonte da verdade (spec 005, R26).
 *
 * O estado de React muda só em mudança discreta — começo de sessão, fim de
 * gesto, troca de modo —, porque é só aí que o nativo avisa. Durante o
 * arrasto, nada atravessa (princípio III).
 */
export function useBand() {
  const [band, setBand] = useState<BandState | null>(null);
  /** O último estado que o nativo confirmou. É para onde volta um toque que falhou. */
  const confirmed = useRef<BandState | null>(null);

  useEffect(() => {
    const sub = ViziVision.addListener('onBandChange', (state) => {
      confirmed.current = state;
      setBand(state);
    });
    return () => sub.remove();
  }, []);

  /**
   * A cápsula. O modo muda aqui na hora, para o destaque deslizar junto com a
   * mola da faixa; o nativo só avisa quando ela chega, e é esse aviso que traz
   * centro e espessura.
   */
  const setMode = useCallback(async (mode: BandMode) => {
    setBand((prev) => (prev && prev.mode !== mode ? { ...prev, mode } : prev));
    try {
      await ViziVision.setBandMode(mode);
    } catch {
      setBand(confirmed.current);
    }
  }, []);

  return { band, setMode };
}
