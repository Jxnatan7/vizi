import { useEffect, useState } from 'react';
import { SafeAreaView, ScrollView, StyleSheet, Text, View, useColorScheme } from 'react-native';
import { StatusBar } from 'expo-status-bar';

import { ViziVision, type NativeProbe } from './modules/vizi-vision';

/**
 * Marco 1 — US1: prova de que código Swift próprio foi compilado, assinado e
 * instalado. Se esta tela mostrar os dados abaixo, a cadeia de entrega inteira
 * funciona, do Linux ao aparelho.
 *
 * Vira a tela de medição na US2 (T028).
 */
export default function App() {
  const dark = useColorScheme() === 'dark';
  const c = dark ? colors.dark : colors.light;

  const [probe, setProbe] = useState<NativeProbe | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    try {
      setProbe(ViziVision.probe());
    } catch (e) {
      // No aparelho não há console à mão: a mensagem precisa chegar à tela.
      // Falha aqui quase sempre significa Expo Go, que não carrega módulo
      // nativo próprio — é preciso um development build.
      setError(String(e));
    }
  }, []);

  return (
    <SafeAreaView style={[styles.fill, { backgroundColor: c.bg }]}>
      <StatusBar style={dark ? 'light' : 'dark'} />
      <ScrollView contentContainerStyle={styles.content}>
        <Text style={[styles.eyebrow, { color: c.muted }]}>MARCO 1 · PROVA DE VIDA</Text>
        <Text style={[styles.title, { color: c.ink }]}>vizi</Text>

        {error && (
          <View style={[styles.card, { borderColor: c.crit, backgroundColor: c.bgAlt }]}>
            <Text style={[styles.cardLabel, { color: c.crit }]}>MÓDULO NATIVO INDISPONÍVEL</Text>
            <Text style={[styles.mono, { color: c.ink }]}>{error}</Text>
          </View>
        )}

        {probe && (
          <View style={[styles.card, { borderColor: c.line, backgroundColor: c.bgAlt }]}>
            <Text style={[styles.cardLabel, { color: c.ok }]}>NATIVO RESPONDEU</Text>
            <Row label="módulo" value={probe.module} c={c} />
            <Row label="sistema" value={probe.os} c={c} />
            <Row label="núcleos" value={String(probe.processorCount)} c={c} />
            <Row label="memória" value={`${probe.physicalMemoryMB} MB`} c={c} />
            <Row label="baixo consumo" value={probe.lowPowerMode ? 'sim' : 'não'} c={c} />
          </View>
        )}

        {!probe && !error && <Text style={{ color: c.muted }}>consultando…</Text>}

        <Text style={[styles.footer, { color: c.muted }]}>
          Medição de inferência entra na US2 — ver specs/001-coreml-proof/tasks.md
        </Text>
      </ScrollView>
    </SafeAreaView>
  );
}

function Row({ label, value, c }: { label: string; value: string; c: Palette }) {
  return (
    <View style={styles.row}>
      <Text style={[styles.rowLabel, { color: c.muted }]}>{label}</Text>
      <Text style={[styles.mono, { color: c.ink }]} numberOfLines={2}>
        {value}
      </Text>
    </View>
  );
}

type Palette = typeof colors.light;

const colors = {
  light: { bg: '#F1F3F5', bgAlt: '#FFFFFF', ink: '#14171C', muted: '#5C6573', line: '#D6DAE0', ok: '#176B4C', crit: '#A4232C' },
  dark: { bg: '#0E1116', bgAlt: '#161B22', ink: '#E4E8EE', muted: '#8A95A3', line: '#2A333D', ok: '#48C99B', crit: '#F1767F' },
};

const styles = StyleSheet.create({
  fill: { flex: 1 },
  content: { padding: 24, gap: 16 },
  eyebrow: { fontSize: 11, letterSpacing: 1.4, fontWeight: '600' },
  title: { fontSize: 34, fontWeight: '700', letterSpacing: -0.5, marginTop: -8 },
  card: { borderWidth: 1, borderRadius: 4, padding: 16, gap: 10 },
  cardLabel: { fontSize: 10, letterSpacing: 1.2, fontWeight: '700' },
  row: { gap: 2 },
  rowLabel: { fontSize: 11, letterSpacing: 0.6 },
  mono: { fontFamily: 'Menlo', fontSize: 13 },
  footer: { fontSize: 12, lineHeight: 18, marginTop: 8 },
});
