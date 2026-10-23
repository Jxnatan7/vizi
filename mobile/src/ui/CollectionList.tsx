import { useState } from 'react';
import { Alert, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';

import type { CollectionSummary } from '../../modules/vizi-vision';
import { LIGHTS } from '../collection/policy';
import { collectionMessage, useCollectionSessions } from '../collection/useCollection';
import { formatDate, formatMegabytes } from './format';
import { Card } from './parts';
import type { Palette } from './theme';

/**
 * As sessões do modo coleta no aparelho (spec 007, US1 e US3): exportar pelo
 * menu de compartilhar, dar nome, apagar.
 *
 * A aberta aparece em andamento e não exporta: o zip de uma sessão que ainda
 * grava não seria o da sessão (FR-015).
 */
export function CollectionList({ c }: { c: Palette }) {
  const { sessions, error, exportSession, rename, remove } = useCollectionSessions();
  const [exporting, setExporting] = useState<string | null>(null);
  const [editing, setEditing] = useState<{ id: string; name: string } | null>(null);
  const [message, setMessage] = useState<{ text: string; bad: boolean } | null>(null);

  const onExport = async (session: CollectionSummary) => {
    setMessage(null);
    setExporting(session.id);
    try {
      const outcome = await exportSession(session.id);
      setMessage({
        text: outcome.shared
          ? `Zip compartilhado — ${formatMegabytes(outcome.bytes)}.`
          : `Zip gerado (${formatMegabytes(outcome.bytes)}) e guardado em ${outcome.file}.`,
        bad: false,
      });
    } catch (e) {
      setMessage({ text: collectionMessage(e), bad: true });
    } finally {
      setExporting(null);
    }
  };

  const onSaveName = async () => {
    if (!editing) return;
    try {
      await rename(editing.id, editing.name);
      setEditing(null);
    } catch (e) {
      setMessage({ text: collectionMessage(e), bad: true });
    }
  };

  const onDelete = (session: CollectionSummary) => {
    Alert.alert(
      'Apagar a sessão?',
      `${title(session)} — ${session.marks} marcas e ${session.captures} capturas saem do aparelho, com o zip.`,
      [
        { text: 'Cancelar', style: 'cancel' },
        {
          text: 'Apagar',
          style: 'destructive',
          onPress: async () => {
            try {
              await remove(session.id);
            } catch (e) {
              setMessage({ text: collectionMessage(e), bad: true });
            }
          },
        },
      ],
    );
  };

  return (
    <Card c={c} border={c.line} label="MODO COLETA · SESSÕES">
      {error && <Text style={{ color: c.crit, fontSize: 13 }}>{error}</Text>}

      {sessions?.length === 0 && !error && (
        <Text style={{ color: c.muted, fontSize: 13, lineHeight: 19 }}>
          Nenhuma sessão ainda. Ligue o modo coleta na câmera, marque e capture, e desligue.
        </Text>
      )}

      {sessions?.map((session) => (
        <View key={session.id} style={[styles.session, { borderColor: c.line }]}>
          <Text style={[styles.name, { color: c.ink }]}>{title(session)}</Text>
          <Text style={{ color: c.muted, fontSize: 12, lineHeight: 17 }}>
            {kind(session)}{' · '}{formatDate(session.startedAt)}
            {' · '}{session.marks} marcas · {session.captures} capturas
            {' · '}{session.answered} respondidas · {formatMegabytes(session.bytes)}
            {session.endReason === 'background' ? ' · fechada no segundo plano' : ''}
            {session.endReason === 'recovered' ? ' · recuperada' : ''}
          </Text>

          {session.open ? (
            <Text style={{ color: c.warn, fontSize: 12 }}>
              Em andamento — desligue o modo coleta para exportar.
            </Text>
          ) : editing?.id === session.id ? (
            <View style={styles.actions}>
              <TextInput
                value={editing.name}
                onChangeText={(name) => setEditing({ id: session.id, name })}
                onSubmitEditing={() => void onSaveName()}
                placeholder="sala, luz da noite"
                placeholderTextColor={c.muted}
                autoFocus
                returnKeyType="done"
                style={[styles.input, { color: c.ink, borderColor: c.line, backgroundColor: c.bg }]}
              />
              <Small c={c} title="Salvar" onPress={() => void onSaveName()} />
              <Small c={c} title="Cancelar" onPress={() => setEditing(null)} />
            </View>
          ) : (
            <View style={styles.actions}>
              <Small c={c} strong
                title={exporting === session.id
                  ? 'Gerando zip…'
                  : session.exportedAt ? 'Exportar de novo' : 'Exportar'}
                disabled={exporting !== null}
                onPress={() => void onExport(session)} />
              <Small c={c} title="Nome" disabled={exporting !== null}
                onPress={() => setEditing({ id: session.id, name: session.name ?? '' })} />
              <Small c={c} title="Apagar" danger disabled={exporting !== null}
                onPress={() => onDelete(session)} />
            </View>
          )}
        </View>
      ))}

      {message && (
        <Text style={{ color: message.bad ? c.crit : c.ok, fontSize: 13, lineHeight: 18 }}>
          {message.text}
        </Text>
      )}
    </Card>
  );
}

/** Treino ou prova (spec 008). As sessões anteriores não têm tipo. */
function kind(session: CollectionSummary): string {
  if (session.purpose === 'exam') return 'prova';
  if (session.purpose === 'training') {
    return `treino · ${LIGHTS.find((l) => l.key === session.light)?.label ?? '?'}`;
  }
  return 'sem tipo';
}

function title(session: CollectionSummary): string {
  return session.name ?? `Sessão de ${formatDate(session.startedAt)}`;
}

function Small({ c, title, onPress, disabled, strong, danger }: {
  c: Palette; title: string; onPress: () => void; disabled?: boolean; strong?: boolean; danger?: boolean;
}) {
  return (
    <Pressable onPress={onPress} disabled={disabled} accessibilityRole="button"
      style={({ pressed }) => [
        styles.small,
        { borderColor: danger ? c.crit : c.line, opacity: disabled ? 0.4 : pressed ? 0.7 : 1 },
      ]}>
      <Text style={{ color: danger ? c.crit : c.ink, fontSize: 13, fontWeight: strong ? '700' : '500' }}>
        {title}
      </Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  session: { borderTopWidth: 1, paddingTop: 10, gap: 6 },
  name: { fontSize: 15, fontWeight: '700' },
  actions: { flexDirection: 'row', gap: 8, alignItems: 'center' },
  small: { borderWidth: 1, borderRadius: 4, paddingHorizontal: 12, paddingVertical: 8 },
  input: { flex: 1, borderWidth: 1, borderRadius: 4, paddingHorizontal: 10, paddingVertical: 8, fontSize: 14 },
});
