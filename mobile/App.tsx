import { useState } from 'react';
import { Pressable, SafeAreaView, StyleSheet, Text, View, useColorScheme } from 'react-native';

import BenchScreen from './src/ui/BenchScreen';
import CameraScreen from './src/ui/CameraScreen';
import { colors } from './src/ui/theme';

/**
 * As duas telas convivem: a do marco 1 continua útil como medição controlada
 * sobre entrada fixa, que é justamente o que a câmera não oferece.
 */
export default function App() {
  const dark = useColorScheme() === 'dark';
  const c = dark ? colors.dark : colors.light;
  const [tab, setTab] = useState<'camera' | 'bench'>('camera');

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: c.bg }}>
      <View style={[styles.tabs, { borderColor: c.line }]}>
        {(['camera', 'bench'] as const).map((id) => (
          <Pressable key={id} onPress={() => setTab(id)} style={styles.tab}>
            <Text style={{ color: tab === id ? c.ink : c.muted, fontWeight: tab === id ? '700' : '500' }}>
              {id === 'camera' ? 'Câmera' : 'Medição'}
            </Text>
          </Pressable>
        ))}
      </View>
      <View style={{ flex: 1 }}>{tab === 'camera' ? <CameraScreen /> : <BenchScreen />}</View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  tabs: { flexDirection: 'row', borderBottomWidth: 1 },
  tab: { flex: 1, paddingVertical: 12, alignItems: 'center' },
});
