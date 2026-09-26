import { useCallback, useEffect, useState } from 'react';
import { Image, Pressable, SafeAreaView, ScrollView, StyleSheet, Text, View, useColorScheme } from 'react-native';

import type { HistoryEntry } from '../../modules/vizi-vision';
import { imageUri, listEntries } from '../history/store';
import { Button, Card, Row } from './parts';
import { colors, type Palette } from './theme';

/**
 * Marco 4 · US4 — o que foi contado, guardado.
 *
 * A imagem vai do arquivo para o `<Image>` pelo nativo. O JavaScript só conhece
 * o caminho (princípio II).
 */
export default function HistoryScreen() {
  const dark = useColorScheme() === 'dark';
  const c = dark ? colors.dark : colors.light;
  const [entries, setEntries] = useState<HistoryEntry[] | null>(null);
  const [open, setOpen] = useState<HistoryEntry | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      setEntries(await listEntries());
    } catch (e) {
      setError(String(e));
      setEntries([]);
    }
  }, []);

  // A aba remonta a cada visita, então o que foi salvo na câmera já aparece.
  useEffect(() => {
    void load();
  }, [load]);

  if (open) return <Entry c={c} entry={open} onBack={() => setOpen(null)} />;

  return (
    <SafeAreaView style={[styles.fill, { backgroundColor: c.bg }]}>
      <ScrollView contentContainerStyle={styles.content}>
        <Text style={[styles.eyebrow, { color: c.muted }]}>MARCO 4 · HISTÓRICO</Text>
        <Text style={[styles.title, { color: c.ink }]}>Capturas</Text>

        {error && (
          <Card c={c} border={c.crit} label="ERRO">
            <Text style={[styles.mono, { color: c.ink }]}>{error}</Text>
          </Card>
        )}

        {entries?.length === 0 && !error && (
          <Text style={{ color: c.muted, fontSize: 14, lineHeight: 20 }}>
            Nada salvo ainda. Capture uma estante e toque em “Salvar no histórico”.
          </Text>
        )}

        {entries?.map((entry) => (
          <Pressable key={entry.id} onPress={() => setOpen(entry)}
            style={({ pressed }) => [
              styles.item,
              { borderColor: c.line, backgroundColor: c.bgAlt, opacity: pressed ? 0.7 : 1 },
            ]}>
            <Image source={{ uri: imageUri(entry) }} resizeMode="cover" style={styles.thumb} />
            <View style={styles.itemText}>
              <Text style={[styles.count, { color: c.ink }]}>{entry.count} livros</Text>
              <Text style={{ color: c.muted, fontSize: 12 }}>
                {formatDate(entry.capturedAt)} · {entry.straightened ? 'endireitado' : 'não endireitado'}
              </Text>
            </View>
          </Pressable>
        ))}
      </ScrollView>
    </SafeAreaView>
  );
}

/** Uma captura aberta: a mesma imagem e a mesma contagem de quando foi salva (SC-007). */
function Entry({ c, entry, onBack }: { c: Palette; entry: HistoryEntry; onBack: () => void }) {
  return (
    <SafeAreaView style={[styles.fill, { backgroundColor: c.bg }]}>
      <ScrollView contentContainerStyle={styles.content}>
        <Text style={[styles.eyebrow, { color: c.muted }]}>CAPTURA</Text>
        <Text style={[styles.title, { color: c.ink }]}>{entry.count} livros</Text>

        {/* Na proporção gravada: uma faixa larga fica larga, sem recorte. */}
        <Image source={{ uri: imageUri(entry) }} resizeMode="contain"
          style={[styles.full, {
            aspectRatio: entry.width > 0 && entry.height > 0 ? entry.width / entry.height : 1,
            borderColor: c.line,
          }]} />

        <Card c={c} border={c.line} label="RESULTADO">
          <Row c={c} label="livros" value={String(entry.count)} strong />
          <Row c={c} label="capturado em" value={formatDate(entry.capturedAt)} />
          <Row c={c} label="endireitado" value={entry.straightened ? 'sim' : 'não'} />
          <Row c={c} label="imagem" value={`${entry.width}×${entry.height}`} />
        </Card>

        <Button c={c} onPress={onBack} disabled={false} title="Voltar à lista" />
      </ScrollView>
    </SafeAreaView>
  );
}

/**
 * dd/mm/aaaa hh:mm, montado à mão: o `toLocaleString` depende do suporte a
 * Intl do motor JavaScript, e errar a data de uma captura é pior que formatar
 * sem biblioteca.
 */
function formatDate(ms: number): string {
  const d = new Date(ms);
  const p = (n: number) => String(n).padStart(2, '0');
  return `${p(d.getDate())}/${p(d.getMonth() + 1)}/${d.getFullYear()} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

const styles = StyleSheet.create({
  fill: { flex: 1 },
  content: { padding: 24, gap: 14 },
  eyebrow: { fontSize: 11, letterSpacing: 1.4, fontWeight: '600' },
  title: { fontSize: 34, fontWeight: '700', letterSpacing: -0.5, marginTop: -8 },
  mono: { fontFamily: 'Menlo', fontSize: 13 },
  item: { borderWidth: 1, borderRadius: 4, overflow: 'hidden' },
  thumb: { width: '100%', height: 96, backgroundColor: '#000' },
  itemText: { padding: 12, gap: 2 },
  count: { fontSize: 17, fontWeight: '700' },
  full: { width: '100%', borderWidth: 1, borderRadius: 4, backgroundColor: '#000' },
});
