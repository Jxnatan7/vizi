import { useState } from 'react';
import { Alert, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';

import { BACKGROUND_GOAL } from '../collection/policy';
import {
  addShelf, cellsOf, doneCells, removeShelf, renameShelf, setShelfCount, useShelves, type Shelf,
} from '../collection/shelves';
import { Card } from './parts';
import type { Palette } from './theme';

/**
 * As prateleiras da casa e o guia de variações (spec 008, US3): cadastrar com o
 * número do inventário, renomear, corrigir o número, apagar — e, por
 * prateleira, quantas das nove variações já têm foto de dia e de noite.
 */
export function ShelfList({ c }: { c: Palette }) {
  const { store, error, run } = useShelves();
  const [name, setName] = useState('');
  const [count, setCount] = useState('');
  const [editing, setEditing] = useState<{ id: string; name: string } | null>(null);

  const onAdd = async () => {
    const ok = await run(() => addShelf(name, Number.parseInt(count, 10)));
    if (ok) {
      setName('');
      setCount('');
    }
  };

  const onRename = async () => {
    if (!editing) return;
    if (await run(() => renameShelf(editing.id, editing.name))) setEditing(null);
  };

  const onDelete = (shelf: Shelf) => {
    Alert.alert(
      'Apagar a prateleira?',
      `${shelf.name} sai da lista, da câmera e do guia. As sessões já gravadas guardam o nome dela.`,
      [
        { text: 'Cancelar', style: 'cancel' },
        { text: 'Apagar', style: 'destructive', onPress: () => void run(() => removeShelf(shelf.id)) },
      ],
    );
  };

  const background = store ? store.background.day + store.background.night : 0;

  return (
    <Card c={c} border={c.line} label="PRATELEIRAS · INVENTÁRIO E GUIA">
      {error && <Text style={{ color: c.crit, fontSize: 13, lineHeight: 18 }}>{error}</Text>}

      {store?.shelves.length === 0 && (
        <Text style={{ color: c.muted, fontSize: 13, lineHeight: 19 }}>
          Nenhuma prateleira ainda. Cadastre cada uma com o número de livros contado à mão,
          pela regra de contagem: é o gabarito da prova.
        </Text>
      )}

      {store?.shelves.map((shelf) => {
        const day = doneCells(cellsOf(store, shelf.id, 'day'));
        const night = doneCells(cellsOf(store, shelf.id, 'night'));
        return (
          <View key={shelf.id} style={[styles.shelf, { borderColor: c.line }]}>
            {editing?.id === shelf.id ? (
              <View style={styles.actions}>
                <TextInput value={editing.name} autoFocus returnKeyType="done"
                  onChangeText={(text) => setEditing({ id: shelf.id, name: text })}
                  onSubmitEditing={() => void onRename()}
                  style={[styles.input, { color: c.ink, borderColor: c.line, backgroundColor: c.bg }]} />
                <Small c={c} title="Salvar" onPress={() => void onRename()} />
                <Small c={c} title="Cancelar" onPress={() => setEditing(null)} />
              </View>
            ) : (
              <Text style={[styles.name, { color: c.ink }]}>{shelf.name}</Text>
            )}
            <Text style={{ color: c.muted, fontSize: 12 }}>
              guia · dia {day}/9 · noite {night}/9
            </Text>
            <View style={styles.actions}>
              <Small c={c} title="−" disabled={shelf.count === 0}
                onPress={() => void run(() => setShelfCount(shelf.id, shelf.count - 1))} />
              <Text style={[styles.count, { color: c.ink }]}
                accessibilityLabel={`${shelf.count} livros no inventário`}>
                {shelf.count}
              </Text>
              <Small c={c} title="+" onPress={() => void run(() => setShelfCount(shelf.id, shelf.count + 1))} />
              <View style={styles.spacer} />
              <Small c={c} title="Nome" onPress={() => setEditing({ id: shelf.id, name: shelf.name })} />
              <Small c={c} title="Apagar" danger onPress={() => onDelete(shelf)} />
            </View>
          </View>
        );
      })}

      {store && (
        <Text style={{ color: background >= BACKGROUND_GOAL ? c.ok : c.muted, fontSize: 12 }}>
          sem livros · {background} de {BACKGROUND_GOAL} (dia {store.background.day} · noite {store.background.night})
        </Text>
      )}

      <View style={[styles.add, { borderColor: c.line }]}>
        <TextInput value={name} onChangeText={setName} placeholder="sala, estante branca, de cima"
          placeholderTextColor={c.muted} returnKeyType="next"
          style={[styles.input, { color: c.ink, borderColor: c.line, backgroundColor: c.bg }]} />
        <View style={styles.actions}>
          <TextInput value={count} onChangeText={(t) => setCount(t.replace(/\D/g, ''))}
            placeholder="livros" placeholderTextColor={c.muted} keyboardType="number-pad"
            style={[styles.input, styles.number, { color: c.ink, borderColor: c.line, backgroundColor: c.bg }]} />
          <Small c={c} strong title="Cadastrar" disabled={!store || !name.trim() || count === ''}
            onPress={() => void onAdd()} />
        </View>
      </View>
    </Card>
  );
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
  shelf: { borderTopWidth: 1, paddingTop: 10, gap: 6 },
  name: { fontSize: 15, fontWeight: '700' },
  count: { fontFamily: 'Menlo', fontSize: 17, fontWeight: '700', minWidth: 36, textAlign: 'center' },
  actions: { flexDirection: 'row', gap: 8, alignItems: 'center' },
  spacer: { flex: 1 },
  add: { borderTopWidth: 1, paddingTop: 10, gap: 8 },
  small: { borderWidth: 1, borderRadius: 4, paddingHorizontal: 12, paddingVertical: 8 },
  input: { flex: 1, borderWidth: 1, borderRadius: 4, paddingHorizontal: 10, paddingVertical: 8, fontSize: 14 },
  number: { flex: 0, width: 96 },
});
