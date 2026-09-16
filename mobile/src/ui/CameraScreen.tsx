import { SafeAreaView, ScrollView, StyleSheet, Text, useColorScheme } from 'react-native';
import { StatusBar } from 'expo-status-bar';

import { useSession } from '../camera/useSession';
import { Button, Card, Row } from './parts';
import { colors } from './theme';

/**
 * Marco 2 — fase 2: prova de que os frames chegam.
 *
 * Preview, transformação e inferência entram na fase 3 (T008–T014). Aqui só
 * interessa a contagem subir.
 */
export default function CameraScreen() {
  const dark = useColorScheme() === 'dark';
  const c = dark ? colors.dark : colors.light;
  const { info, sample, summary, error, start, stop } = useSession();

  return (
    <SafeAreaView style={[styles.fill, { backgroundColor: c.bg }]}>
      <StatusBar style={dark ? 'light' : 'dark'} />
      <ScrollView contentContainerStyle={styles.content}>
        <Text style={[styles.eyebrow, { color: c.muted }]}>MARCO 2 · CÂMERA</Text>
        <Text style={[styles.title, { color: c.ink }]}>vizi</Text>

        {error && (
          <Card c={c} border={c.crit} label="ERRO">
            <Text style={{ color: c.ink, fontFamily: 'Menlo', fontSize: 13 }}>{error}</Text>
          </Card>
        )}

        <Button c={c} onPress={info ? stop : start} disabled={false}
          title={info ? 'Parar sessão' : 'Iniciar sessão'} />

        {info && (
          <Card c={c} border={c.line} label="CAPTURA">
            <Row c={c} label="formato" value={`${info.captureWidth}×${info.captureHeight}`} />
            <Row c={c} label="taxa máxima" value={`${info.maxFrameRate.toFixed(0)} fps`} />
          </Card>
        )}

        {sample && (
          <Card c={c} border={c.ok} label="TELEMETRIA · JANELA">
            <Row c={c} label="frames capturados" value={`${sample.fpsCaptured.toFixed(1)} /s`} strong />
            <Row c={c} label="frames processados" value={`${sample.fpsInferred.toFixed(1)} /s`} strong />
            <Row c={c} label="fila" value={String(sample.queueDepth)} />
            <Row c={c} label="descartados" value={String(sample.dropped)} />
            <Row c={c} label="térmico" value={sample.thermalState} />
            <Row c={c} label="bateria" value={sample.batteryLevel < 0 ? '—' : `${(sample.batteryLevel * 100).toFixed(0)}%`} />
            <Row c={c} label="tempo" value={`${(sample.t / 1000).toFixed(0)} s`} />
          </Card>
        )}

        {summary && (
          <Card c={c} border={c.line} label="SESSÃO ENCERRADA">
            <Row c={c} label="duração" value={`${(summary.durationMs / 1000).toFixed(1)} s`} />
            <Row c={c} label="recebidos" value={String(summary.received)} />
            <Row c={c} label="processados" value={String(summary.processed)} />
            <Row c={c} label="descartados" value={String(summary.dropped)} />
          </Card>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1 },
  content: { padding: 24, gap: 14 },
  eyebrow: { fontSize: 11, letterSpacing: 1.4, fontWeight: '600' },
  title: { fontSize: 34, fontWeight: '700', letterSpacing: -0.5, marginTop: -8 },
});
