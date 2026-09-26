import { useState } from 'react';
import { Pressable, SafeAreaView, StyleSheet, Text, View, useColorScheme } from 'react-native';

import BenchScreen from './src/ui/BenchScreen';
import CameraScreen from './src/ui/CameraScreen';
import HistoryScreen from './src/ui/HistoryScreen';
import { colors } from './src/ui/theme';

const TABS = { camera: 'Câmera', history: 'Histórico', bench: 'Medição' } as const;
type Tab = keyof typeof TABS;

/**
 * As telas convivem: a do marco 1 continua útil como medição controlada sobre
 * entrada fixa, que é justamente o que a câmera não oferece.
 *
 * Trocar de aba desmonta a tela anterior — e a câmera para junto, que é o que
 * a bateria pede.
 */
export default function App() {
  const dark = useColorScheme() === 'dark';
  const c = dark ? colors.dark : colors.light;
  const [tab, setTab] = useState<Tab>('camera');

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: c.bg }}>
      <View style={[styles.tabs, { borderColor: c.line }]}>
        {(Object.keys(TABS) as Tab[]).map((id) => (
          <Pressable key={id} onPress={() => setTab(id)} style={styles.tab}>
            <Text style={{ color: tab === id ? c.ink : c.muted, fontWeight: tab === id ? '700' : '500' }}>
              {TABS[id]}
            </Text>
          </Pressable>
        ))}
      </View>
      <View style={{ flex: 1 }}>
        {tab === 'camera' ? <CameraScreen /> : tab === 'history' ? <HistoryScreen /> : <BenchScreen />}
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  tabs: { flexDirection: 'row', borderBottomWidth: 1 },
  tab: { flex: 1, paddingVertical: 12, alignItems: 'center' },
});
