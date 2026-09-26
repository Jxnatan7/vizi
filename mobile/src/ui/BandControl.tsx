import { useEffect, useRef, useState } from 'react';
import { Animated, Pressable, StyleSheet, Text, View, type LayoutChangeEvent } from 'react-native';

import type { BandMode } from '../../modules/vizi-vision';
import { DEFAULT_BAND } from '../band/policy';
import type { Palette } from './theme';

/** Na ordem da cápsula. */
const OPTIONS: { mode: BandMode; label: string; a11yLabel: string; a11yHint: string }[] = [
  {
    mode: 'off', label: 'Imagem toda', a11yLabel: 'Imagem toda',
    a11yHint: 'Desliga a faixa e conta a imagem inteira.',
  },
  {
    mode: 'horizontal', label: 'Horizontal', a11yLabel: 'Faixa horizontal',
    a11yHint: 'Conta só uma prateleira.',
  },
  {
    mode: 'vertical', label: 'Vertical', a11yLabel: 'Faixa vertical',
    a11yHint: 'Conta só uma coluna.',
  },
];

/**
 * A mola da faixa, convertida de `springResponse` e `springDamping` como no
 * nativo: o destaque e a faixa chegam juntos.
 */
const SPRING = {
  mass: 1,
  stiffness: (2 * Math.PI / DEFAULT_BAND.springResponse) ** 2,
  damping: (4 * Math.PI * DEFAULT_BAND.springDamping) / DEFAULT_BAND.springResponse,
  useNativeDriver: true,
};

const PAD = 3;

/**
 * A cápsula de três estados da faixa: imagem toda · horizontal · vertical
 * (spec 005, FR-011).
 *
 * É o caminho sem gesto para tudo o que muda o modo, e o do leitor de tela
 * (FR-021). O destaque desliza com driver nativo: nenhum quadro da animação
 * passa pelo JavaScript.
 */
export function BandControl({ c, mode, visible, onChange }: {
  c: Palette;
  /** `undefined` até o nativo avisar o primeiro estado. */
  mode: BandMode | undefined;
  /** Some durante a captura e o resultado, sem mexer no layout de baixo. */
  visible: boolean;
  onChange: (mode: BandMode) => void;
}) {
  const index = OPTIONS.findIndex((o) => o.mode === mode);
  const [segment, setSegment] = useState(0);
  const position = useRef(new Animated.Value(Math.max(index, 0))).current;
  const shown = useRef(new Animated.Value(visible ? 1 : 0)).current;
  const placed = useRef(false);

  useEffect(() => {
    if (index < 0) return;
    // A primeira posição não desliza: a cápsula nasce no estado da faixa.
    if (!placed.current) {
      placed.current = true;
      position.setValue(index);
      return;
    }
    Animated.spring(position, { toValue: index, ...SPRING }).start();
  }, [index, position]);

  useEffect(() => {
    Animated.timing(shown, {
      toValue: visible ? 1 : 0,
      duration: DEFAULT_BAND.springResponse * 1000,
      useNativeDriver: true,
    }).start();
  }, [visible, shown]);

  const onLayout = (e: LayoutChangeEvent) => setSegment(e.nativeEvent.layout.width / OPTIONS.length);

  return (
    <Animated.View
      pointerEvents={visible ? 'auto' : 'none'}
      accessibilityElementsHidden={!visible}
      style={[styles.capsule, { borderColor: c.line, backgroundColor: c.bgAlt, opacity: shown }]}>
      <View style={styles.track} onLayout={onLayout}>
        <Animated.View
          pointerEvents="none"
          style={[styles.thumb, {
            width: segment,
            backgroundColor: c.line,
            opacity: index < 0 || segment === 0 ? 0 : 1,
            transform: [{
              translateX: position.interpolate({
                inputRange: [0, OPTIONS.length - 1],
                outputRange: [0, segment * (OPTIONS.length - 1)],
              }),
            }],
          }]} />
        {OPTIONS.map((o) => {
          const selected = o.mode === mode;
          const color = selected ? c.ink : c.muted;
          return (
            <Pressable
              key={o.mode}
              disabled={mode === undefined}
              onPress={() => { if (!selected) onChange(o.mode); }}
              accessibilityRole="button"
              accessibilityLabel={o.a11yLabel}
              accessibilityHint={o.a11yHint}
              accessibilityState={{ selected, disabled: mode === undefined }}
              style={({ pressed }) => [styles.option, { opacity: pressed ? 0.6 : 1 }]}>
              <Glyph mode={o.mode} color={color} />
              <Text style={[styles.label, { color, fontWeight: selected ? '700' : '600' }]}>
                {o.label}
              </Text>
            </Pressable>
          );
        })}
      </View>
    </Animated.View>
  );
}

/** A imagem, com o que conta preenchido: tudo, uma linha ou uma coluna. */
function Glyph({ mode, color }: { mode: BandMode; color: string }) {
  const fill = mode === 'off' ? styles.fillAll : mode === 'horizontal' ? styles.fillRow : styles.fillColumn;
  return (
    <View style={[styles.glyph, { borderColor: color }]}>
      <View style={[styles.fill, fill, { backgroundColor: color }]} />
    </View>
  );
}

const styles = StyleSheet.create({
  capsule: { borderWidth: 1, borderRadius: 999, padding: PAD },
  track: { flexDirection: 'row' },
  thumb: { position: 'absolute', top: 0, bottom: 0, left: 0, borderRadius: 999 },
  option: {
    flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
    gap: 6, paddingVertical: 9,
  },
  label: { fontSize: 12 },
  glyph: { width: 14, height: 14, borderWidth: 1.5, borderRadius: 3, overflow: 'hidden' },
  fill: { position: 'absolute' },
  fillAll: { top: 1.5, bottom: 1.5, left: 1.5, right: 1.5, borderRadius: 1 },
  fillRow: { left: 0, right: 0, top: '30%', height: '40%' },
  fillColumn: { top: 0, bottom: 0, left: '30%', width: '40%' },
});
