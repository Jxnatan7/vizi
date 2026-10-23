import { Pressable, StyleSheet, Text, View } from 'react-native';

import type { CollectionLight, CollectionPurpose } from '../../modules/vizi-vision';
import { ANGLES, BACKGROUND_GOAL, DISTANCES, LIGHTS } from '../collection/policy';
import type { TagSelection } from '../collection/selection';
import { cellOf, cellsOf, type ShelfStore } from '../collection/shelves';
import { Card } from './parts';
import type { Palette } from './theme';

/**
 * A escolha da câmera numa sessão de treino ou de prova (spec 008, FR-002,
 * FR-007, FR-011): a prateleira e, no treino, "sem livros" e o guia 3×3.
 *
 * O guia é o próprio seletor: tocar numa célula escolhe a distância e o ângulo.
 * Cada célula mostra quantas capturas de treino ela já tem na luz da sessão.
 */
export function CollectionTagsBar({ c, purpose, light, store, storeError, selection, onChange }: {
  c: Palette;
  purpose: CollectionPurpose;
  light: CollectionLight | null;
  store: ShelfStore | null;
  storeError: string | null;
  selection: TagSelection;
  onChange: (next: TagSelection) => void;
}) {
  const training = purpose === 'training';
  const shelves = store?.shelves ?? [];
  const lightLabel = LIGHTS.find((l) => l.key === light)?.label;
  const background = training && light && store ? store.background[light] : 0;
  const counts = training && light && store && selection.shelfId
    ? cellsOf(store, selection.shelfId, light) : {};
  const showGuide = training && !selection.background
    && shelves.some((s) => s.id === selection.shelfId);
  const distance = DISTANCES.find((d) => d.key === selection.distance);
  const angle = ANGLES.find((a) => a.key === selection.angle);

  return (
    <Card c={c} border={c.crit} label={training ? `TREINO · ${lightLabel?.toUpperCase() ?? ''}` : 'PROVA'}>
      {storeError && <Text style={[styles.note, { color: c.crit }]}>{storeError}</Text>}

      <View style={styles.chips}>
        {shelves.map((shelf) => (
          <Chip key={shelf.id} c={c}
            label={training ? shelf.name : `${shelf.name} · ${shelf.count}`}
            selected={!selection.background && selection.shelfId === shelf.id}
            // Trocar de prateleira mantém a célula: varrer as prateleiras na mesma
            // variação é um toque por prateleira.
            onPress={() => onChange({ ...selection, shelfId: shelf.id, background: false })} />
        ))}
        {training && (
          <Chip c={c} label={`sem livros · ${background}/${BACKGROUND_GOAL}`}
            selected={selection.background}
            onPress={() => onChange({ shelfId: null, background: true, distance: null, angle: null })} />
        )}
      </View>

      {shelves.length === 0 && (
        <Text style={[styles.note, { color: c.warn }]}>
          {training
            ? 'Nenhuma prateleira cadastrada: só "sem livros" está disponível. Cadastre as prateleiras na Medição.'
            : 'Nenhuma prateleira cadastrada. Cadastre as prateleiras na Medição antes da prova.'}
        </Text>
      )}

      {showGuide && (
        <View style={styles.guide}>
          <View style={styles.guideRow}>
            <View style={styles.side} />
            {ANGLES.map((a) => (
              <Text key={a.key} style={[styles.head, { color: c.muted }]}>{a.label}</Text>
            ))}
          </View>
          {DISTANCES.map((d) => (
            <View key={d.key} style={styles.guideRow}>
              <Text style={[styles.side, { color: c.muted }]}>{d.label}</Text>
              {ANGLES.map((a) => {
                const n = counts[cellOf(d.key, a.key)] ?? 0;
                const selected = selection.distance === d.key && selection.angle === a.key;
                return (
                  <Pressable key={a.key}
                    onPress={() => onChange({ ...selection, distance: d.key, angle: a.key })}
                    accessibilityRole="button"
                    accessibilityState={{ selected }}
                    accessibilityLabel={`${d.label}, ${a.label}, ${n} ${n === 1 ? 'captura' : 'capturas'}`}
                    style={({ pressed }) => [styles.cell, {
                      borderColor: selected ? c.crit : n > 0 ? c.ok : c.line,
                      borderWidth: selected ? 2 : 1,
                      backgroundColor: c.bg,
                      opacity: pressed ? 0.7 : 1,
                    }]}>
                    <Text style={[styles.cellText, { color: n > 0 ? c.ok : c.muted }]}>
                      {n > 0 ? `✓ ${n}` : '·'}
                    </Text>
                  </Pressable>
                );
              })}
            </View>
          ))}
          {(distance || angle) && (
            <Text style={[styles.note, { color: c.muted }]}>
              {[distance && `${distance.label}: ${distance.description}`,
                angle && `${angle.label}: ${angle.description}`].filter(Boolean).join('\n')}
            </Text>
          )}
        </View>
      )}
    </Card>
  );
}

function Chip({ c, label, selected, onPress }: {
  c: Palette; label: string; selected: boolean; onPress: () => void;
}) {
  return (
    <Pressable onPress={onPress} accessibilityRole="button" accessibilityState={{ selected }}
      style={({ pressed }) => [styles.chip, {
        borderColor: selected ? c.crit : c.line,
        backgroundColor: c.bg,
        opacity: pressed ? 0.7 : 1,
      }]}>
      <Text style={{ color: selected ? c.crit : c.ink, fontSize: 13, fontWeight: selected ? '700' : '500' }}>
        {label}
      </Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  chip: { borderWidth: 1, borderRadius: 16, paddingHorizontal: 12, paddingVertical: 7 },
  note: { fontSize: 12, lineHeight: 17 },
  guide: { gap: 6 },
  guideRow: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  side: { width: 52, fontSize: 11, letterSpacing: 0.4 },
  head: { flex: 1, fontSize: 11, textAlign: 'center', letterSpacing: 0.4 },
  // 44 pt: tocar várias vezes seguidas, com a outra mão segurando o aparelho.
  cell: { flex: 1, height: 44, borderRadius: 4, alignItems: 'center', justifyContent: 'center' },
  cellText: { fontSize: 13, fontWeight: '600' },
});
