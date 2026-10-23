import { StyleSheet, Text, View } from 'react-native';

import type { CollectionLight, CollectionPurpose } from '../../modules/vizi-vision';
import { Button, Card } from './parts';
import type { Palette } from './theme';

export type CollectionKind = { purpose: CollectionPurpose; light: CollectionLight | null };

/**
 * Ligar o modo coleta passa por aqui (spec 008, FR-001): treino de dia, treino
 * de noite ou prova, um toque cada. A luz é da sessão: mudou a luz, desliga e
 * liga de novo.
 */
export function CollectionStart({ c, busy, onChoose, onCancel }: {
  c: Palette;
  busy: boolean;
  onChoose: (kind: CollectionKind) => void;
  onCancel: () => void;
}) {
  return (
    <Card c={c} border={c.crit} label="MODO COLETA · QUE SESSÃO É ESTA?">
      <Text style={[styles.text, { color: c.muted }]}>
        Treino: fotos para o Roboflow. Cada captura é gravada e a câmera volta
        direto, sem resultado e sem pergunta.
      </Text>
      <View style={styles.row}>
        <View style={styles.cell}>
          <Button c={c} disabled={busy} title="Treino · dia"
            onPress={() => onChoose({ purpose: 'training', light: 'day' })} />
        </View>
        <View style={styles.cell}>
          <Button c={c} disabled={busy} title="Treino · noite"
            onPress={() => onChoose({ purpose: 'training', light: 'night' })} />
        </View>
      </View>
      <Text style={[styles.text, { color: c.muted }]}>
        Prova: mede o app contra o inventário, com o resultado e a pergunta de
        sempre. Nunca vai para o treino.
      </Text>
      <Button c={c} disabled={busy} title="Prova"
        onPress={() => onChoose({ purpose: 'exam', light: null })} />
      <Button c={c} disabled={busy} title="Cancelar" onPress={onCancel} />
    </Card>
  );
}

const styles = StyleSheet.create({
  text: { fontSize: 13, lineHeight: 18 },
  row: { flexDirection: 'row', gap: 10 },
  cell: { flex: 1 },
});
