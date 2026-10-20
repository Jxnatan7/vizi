import { useEffect, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import type { CollectionState } from '../../modules/vizi-vision';
import { formatElapsed, formatMegabytes } from './format';
import type { Palette } from './theme';

/**
 * O modo coleta gravando (spec 007, FR-002): ponto, tempo, marcas, capturas e
 * espaço.
 *
 * O tempo é calculado aqui, a partir do início, e redesenhado uma vez por
 * segundo (R46). O princípio III proíbe estado de React por quadro; um segundo
 * é cromo. O resto chega pelo `onCollectionChange`, a cada item.
 */
export function CollectionIndicator({ c, state }: { c: Palette; state: CollectionState }) {
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);

  const elapsed = state.startedAt ? Math.max(0, now - state.startedAt) : 0;
  const summary = `${state.marks} ${state.marks === 1 ? 'marca' : 'marcas'} · `
    + `${state.captures} ${state.captures === 1 ? 'captura' : 'capturas'} · `
    + formatMegabytes(state.bytes);

  return (
    <View style={styles.wrap}>
      <View style={[styles.bar, { borderColor: c.crit, backgroundColor: c.bgAlt }]}
        accessible accessibilityLabel={`Modo coleta gravando, ${formatElapsed(elapsed)}, ${summary}`}>
        <View style={[styles.dot, { backgroundColor: c.crit }]} />
        <Text style={[styles.time, { color: c.ink }]}>{formatElapsed(elapsed)}</Text>
        <Text style={[styles.summary, { color: c.muted }]} numberOfLines={1}>{summary}</Text>
      </View>
      {/* FR-020: dizer por que não grava, em vez de deixar a pessoa descobrir no zip. */}
      {state.lowSpace && (
        <Text style={[styles.note, { color: c.warn }]}>
          Pouco espaço livre: marcar está recusado e as capturas não são gravadas.
        </Text>
      )}
      {state.lastError && (
        <Text style={[styles.note, { color: c.crit }]}>Não gravou — {state.lastError}</Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { gap: 6 },
  bar: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    borderWidth: 1, borderRadius: 4, paddingHorizontal: 12, paddingVertical: 8,
  },
  dot: { width: 10, height: 10, borderRadius: 5 },
  time: { fontFamily: 'Menlo', fontSize: 13, fontWeight: '700' },
  summary: { fontSize: 12, flexShrink: 1 },
  note: { fontSize: 12, lineHeight: 17 },
});
