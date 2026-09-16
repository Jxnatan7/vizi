import { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator, SafeAreaView, ScrollView, StyleSheet, Text, View, useColorScheme,
} from 'react-native';
import { StatusBar } from 'expo-status-bar';

import { ViziVision, type ModelInfo, type NativeProbe, type Measurement } from '../../modules/vizi-vision';
import { compareWithReference, type Comparison } from '../bench/compareReference';
import { DEFAULT_OPTIONS, runBenchmark } from '../bench/runBenchmark';
import { ms } from '../bench/stats';
import { Button, Card, Row } from './parts';
import { colors } from './theme';

export default function BenchScreen() {
  const dark = useColorScheme() === 'dark';
  const c = dark ? colors.dark : colors.light;

  const [probe, setProbe] = useState<NativeProbe | null>(null);
  const [model, setModel] = useState<ModelInfo | null>(null);
  const [result, setResult] = useState<Measurement | null>(null);
  const [comparison, setComparison] = useState<Comparison | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    try {
      setProbe(ViziVision.probe());
    } catch (e) {
      setError(String(e));
    }
  }, []);

  const load = useCallback(async () => {
    setBusy(true);
    setError(null);
    try {
      setModel(await ViziVision.loadModel());
    } catch (e) {
      // Sem console à mão no aparelho: a mensagem tem de chegar à tela (FR-008).
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }, []);

  const measure = useCallback(async () => {
    setBusy(true);
    setError(null);
    try {
      const measured = await runBenchmark(DEFAULT_OPTIONS);
      setResult(measured);
      setComparison(compareWithReference(measured.instances));
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }, []);

  const gateOk = result ? result.modelMs.median < 30 && result.modelMs.p95 < 40 : null;

  return (
    <SafeAreaView style={[styles.fill, { backgroundColor: c.bg }]}>
      <StatusBar style={dark ? 'light' : 'dark'} />
      <ScrollView contentContainerStyle={styles.content}>
        <Text style={[styles.eyebrow, { color: c.muted }]}>MARCO 1 · MEDIÇÃO</Text>
        <Text style={[styles.title, { color: c.ink }]}>vizi</Text>

        {__DEV__ && (
          <View style={[styles.banner, { borderColor: c.crit, backgroundColor: c.bgAlt }]}>
            <Text style={[styles.bannerText, { color: c.crit }]}>
              Bundle Debug — Swift sem otimização. Números daqui não valem para o portão.
            </Text>
          </View>
        )}

        {error && (
          <Card c={c} border={c.crit} label="ERRO">
            <Text style={[styles.mono, { color: c.ink }]}>{error}</Text>
          </Card>
        )}

        {probe && (
          <Card c={c} border={c.line} label="APARELHO">
            <Row c={c} label="sistema" value={probe.os} />
            <Row c={c} label="núcleos" value={String(probe.processorCount)} />
            <Row c={c} label="memória" value={`${probe.physicalMemoryMB} MB`} />
          </Card>
        )}

        <Button c={c} onPress={load} disabled={busy} title={model ? 'Recarregar modelo' : 'Carregar modelo'} />

        {model && (
          <Card c={c} border={c.line} label="MODELO">
            <Row c={c} label="entrada" value={`${model.inputWidth}×${model.inputHeight}`} />
            <Row c={c} label="classes" value={Object.values(model.classes).join(', ') || '—'} />
            <Row c={c} label="coef. de máscara" value={String(model.maskCoeffCount)} />
            <Row c={c} label="compilado agora" value={model.compiledAtRuntime ? 'sim' : 'não (pré-compilado)'} />
            <Row c={c} label="carga" value={ms(model.loadMs)} />
          </Card>
        )}

        {model && (
          <Button
            c={c}
            onPress={measure}
            disabled={busy}
            title={`Medir — ${DEFAULT_OPTIONS.repetitions} repetições`}
          />
        )}

        {busy && <ActivityIndicator color={c.muted} />}

        {result && (
          <Card c={c} border={gateOk ? c.ok : c.warn} label={gateOk ? 'PORTÃO ATINGIDO' : 'PORTÃO NÃO ATINGIDO'}>
            <Row c={c} label="modelo · mediana" value={ms(result.modelMs.median)} strong />
            <Row c={c} label="modelo · p95" value={ms(result.modelMs.p95)} strong />
            <Row c={c} label="modelo · mínimo" value={ms(result.modelMs.min)} />
            <Row c={c} label="ciclo · mediana" value={ms(result.cycleMs.median)} />
            <Row c={c} label="primeira execução" value={ms(result.firstRunMs)} />
            <Row c={c} label="repetições" value={`${result.repetitions} (${result.discarded} descartadas)`} />
            <Row c={c} label="térmico" value={result.thermalState} />
            <Row c={c} label="unidades" value={result.executionUnit} />
            <Row c={c} label="instâncias" value={String(result.instances.length)} />
          </Card>
        )}

        {comparison && (
          <Card
            c={c}
            border={comparison.pass ? c.ok : c.crit}
            label={comparison.pass ? 'REFERÊNCIA CONFERE' : 'DIVERGE DA REFERÊNCIA'}>
            <Row c={c} label="instâncias" value={`${comparison.actualCount} · esperado ${comparison.expectedCount}`} strong />
            <Row c={c} label="casadas" value={`${comparison.matched} de ${comparison.expectedCount}`} />
            <Row c={c} label="pior IoU" value={comparison.worstIoU.toFixed(4)} />
            <Row c={c} label="desvio máx. do centro" value={`${comparison.maxCenterDeltaPx.toFixed(2)} px`} />
            <Row c={c} label="classes divergentes" value={String(comparison.classMismatches)} />
            <Row
              c={c}
              label="IoU das não casadas"
              value={
                comparison.unmatchedIoUs.length
                  ? comparison.unmatchedIoUs.map((v) => v.toFixed(3)).join(', ')
                  : '—'
              }
            />
          </Card>
        )}

        {result && result.instances.length > 0 && (
          <Card c={c} border={c.line} label={`INSTÂNCIAS · ${result.instances.length}`}>
            <Text style={[styles.mono, { color: c.muted, fontSize: 11 }]}>
              {'  #  conf    x     y     w     h'}
            </Text>
            {result.instances.map((inst, i) => (
              <Text key={i} style={[styles.mono, { color: c.ink, fontSize: 11 }]}>
                {String(i).padStart(3)}
                {inst.score.toFixed(2).padStart(7)}
                {inst.x.toFixed(0).padStart(6)}
                {inst.y.toFixed(0).padStart(6)}
                {inst.width.toFixed(0).padStart(6)}
                {inst.height.toFixed(0).padStart(6)}
              </Text>
            ))}
          </Card>
        )}

        {result && (
          <Card c={c} border={c.line} label="AQUECIMENTO · 20 PRIMEIRAS">
            <Text style={[styles.mono, { color: c.muted }]}>
              {result.warmupCurve.map((v) => v.toFixed(1)).join('  ')}
            </Text>
            <Text style={[styles.hint, { color: c.muted }]}>
              Onde a série estabiliza é o valor certo de warmupDiscard (T029).
            </Text>
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
  banner: { borderWidth: 1, borderLeftWidth: 3, borderRadius: 4, padding: 12 },
  bannerText: { fontSize: 12, lineHeight: 17 },
  mono: { fontFamily: 'Menlo', fontSize: 13 },
  hint: { fontSize: 11, lineHeight: 16 },
});
