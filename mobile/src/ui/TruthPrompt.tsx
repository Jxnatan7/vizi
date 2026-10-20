import { useEffect, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { Button, Card } from './parts';
import type { Palette } from './theme';

/**
 * O pedido da contagem real (spec 007, FR-007 e FR-009): o número dos livros
 * que aparecem na tela, preenchido com o do app, para a pessoa só corrigir.
 *
 * Serve à captura e à marca. Some quando quem o mostra recebe a resposta.
 */
export function TruthPrompt({ c, prefill, question, onAnswer }: {
  c: Palette;
  /** O que o pedido mostra ao abrir — a contagem do app. */
  prefill: number;
  question: string;
  /** `null` = pulou. */
  onAnswer: (count: number | null) => Promise<void>;
}) {
  const [count, setCount] = useState(prefill);
  const [sending, setSending] = useState(false);

  useEffect(() => setCount(prefill), [prefill]);

  const send = async (value: number | null) => {
    if (sending) return;
    setSending(true);
    try {
      await onAnswer(value);
    } finally {
      setSending(false);
    }
  };

  return (
    <Card c={c} border={c.warn} label="CONTAGEM REAL">
      <Text style={{ color: c.ink, fontSize: 14, lineHeight: 20 }}>{question}</Text>
      <View style={styles.stepper}>
        <Step c={c} label="−" accessibilityLabel="Um livro a menos"
          disabled={sending || count === 0} onPress={() => setCount((n) => Math.max(0, n - 1))} />
        <Text style={[styles.value, { color: c.ink }]} accessibilityLabel={`${count} livros`}>
          {count}
        </Text>
        <Step c={c} label="+" accessibilityLabel="Um livro a mais"
          disabled={sending} onPress={() => setCount((n) => n + 1)} />
      </View>
      <Text style={{ color: c.muted, fontSize: 12 }}>
        {count === prefill ? `O app contou ${prefill}.` : `O app contou ${prefill} — diferença de ${count - prefill}.`}
      </Text>
      <View style={styles.actions}>
        <View style={styles.action}>
          <Button c={c} onPress={() => void send(null)} disabled={sending} title="Pular" />
        </View>
        <View style={styles.action}>
          <Button c={c} onPress={() => void send(count)} disabled={sending}
            title={sending ? 'Gravando…' : 'Confirmar'} />
        </View>
      </View>
    </Card>
  );
}

function Step({ c, label, accessibilityLabel, disabled, onPress }: {
  c: Palette; label: string; accessibilityLabel: string; disabled: boolean; onPress: () => void;
}) {
  return (
    <Pressable onPress={onPress} disabled={disabled} accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      style={({ pressed }) => [
        styles.step,
        { borderColor: c.line, backgroundColor: c.bg, opacity: disabled ? 0.4 : pressed ? 0.7 : 1 },
      ]}>
      <Text style={[styles.stepText, { color: c.ink }]}>{label}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  stepper: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 24 },
  // 56 pt: um alvo folgado para tocar várias vezes seguidas, olhando a estante.
  step: { width: 56, height: 56, borderWidth: 1, borderRadius: 28, alignItems: 'center', justifyContent: 'center' },
  stepText: { fontSize: 28, fontWeight: '600', marginTop: -2 },
  value: { fontFamily: 'Menlo', fontSize: 40, fontWeight: '700', minWidth: 72, textAlign: 'center' },
  actions: { flexDirection: 'row', gap: 10 },
  action: { flex: 1 },
});
