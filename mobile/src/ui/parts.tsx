import { Pressable, StyleSheet, Text, View } from 'react-native';

import type { Palette } from './theme';

export function Card({ c, border, label, children }: {
  c: Palette; border: string; label: string; children: React.ReactNode;
}) {
  return (
    <View style={[styles.card, { borderColor: border, backgroundColor: c.bgAlt }]}>
      <Text style={[styles.cardLabel, { color: border }]}>{label}</Text>
      {children}
    </View>
  );
}

export function Row({ c, label, value, strong }: {
  c: Palette; label: string; value: string; strong?: boolean;
}) {
  return (
    <View style={styles.row}>
      <Text style={[styles.rowLabel, { color: c.muted }]}>{label}</Text>
      <Text style={[styles.mono, { color: c.ink, fontSize: strong ? 17 : 13 }]}>{value}</Text>
    </View>
  );
}

export function Button({ c, onPress, disabled, title }: {
  c: Palette; onPress: () => void; disabled: boolean; title: string;
}) {
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      style={({ pressed }) => [
        styles.button,
        { borderColor: c.line, backgroundColor: c.bgAlt, opacity: disabled ? 0.4 : pressed ? 0.7 : 1 },
      ]}>
      <Text style={[styles.buttonText, { color: c.ink }]}>{title}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  card: { borderWidth: 1, borderRadius: 4, padding: 16, gap: 10 },
  cardLabel: { fontSize: 10, letterSpacing: 1.2, fontWeight: '700' },
  row: { gap: 2 },
  rowLabel: { fontSize: 11, letterSpacing: 0.6 },
  mono: { fontFamily: 'Menlo', fontSize: 13 },
  button: { borderWidth: 1, borderRadius: 4, paddingVertical: 14, alignItems: 'center' },
  buttonText: { fontSize: 15, fontWeight: '600' },
});
