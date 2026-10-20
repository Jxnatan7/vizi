import { useEffect, useMemo, useState } from 'react';
import { Pressable, SafeAreaView, ScrollView, StyleSheet, Text, View, useColorScheme } from 'react-native';
import { StatusBar } from 'expo-status-bar';

import { PreviewView, type MarkReceipt, type TransformMode } from '../../modules/vizi-vision';
import { useBand } from '../band/useBand';
import { useCapture } from '../capture/useCapture';
import { useSession } from '../camera/useSession';
import { collectionMessage, useCollection } from '../collection/useCollection';
import { copySessionToClipboard, evaluateGate } from '../telemetry/exportSession';
import { BandControl } from './BandControl';
import { CollectionIndicator } from './CollectionIndicator';
import { Button, Card, Row } from './parts';
import { colors } from './theme';
import { TruthPrompt } from './TruthPrompt';

/**
 * Marco 2 — fase 2: prova de que os frames chegam.
 *
 * Preview, transformação e inferência entram na fase 3 (T008–T014). Aqui só
 * interessa a contagem subir.
 */
export default function CameraScreen() {
  const dark = useColorScheme() === 'dark';
  const c = dark ? colors.dark : colors.light;
  const { info, sample, session, error, transform, overlay, start, stop, setTransform, setOverlay } = useSession();
  const [copied, setCopied] = useState(false);
  const {
    state, result, error: captureError, capture, dismiss, diagnostics, setDiagnostics,
    save, saving, saved, saveError, reset,
  } = useCapture();
  const { band, setMode: setBandMode } = useBand();
  const verdicts = useMemo(() => (session ? evaluateGate(session) : []), [session]);

  // O modo coleta (spec 007). `marked` é o quadro parado de uma marca, à
  // espera da contagem real; `answered`, a resposta já dada à captura na tela.
  const collection = useCollection();
  const [marked, setMarked] = useState<MarkReceipt | null>(null);
  const [marking, setMarking] = useState(false);
  const [answered, setAnswered] = useState<{ itemId: string; count: number | null } | null>(null);
  const [collectionError, setCollectionError] = useState<string | null>(null);

  // A sessão parou com o resultado na tela: o nativo já o desfez. Um quadro de
  // marca parado também: o item dele fica sem resposta.
  useEffect(() => {
    if (!info) {
      reset();
      setMarked(null);
    }
  }, [info, reset]);

  const toggleCollection = async () => {
    setCollectionError(null);
    try {
      if (collection.state.open) await collection.stop();
      else await collection.start();
    } catch (e) {
      setCollectionError(collectionMessage(e));
    }
  };

  const markFrame = async () => {
    setCollectionError(null);
    setMarking(true);
    try {
      setMarked(await collection.mark());
    } catch (e) {
      setCollectionError(collectionMessage(e));
    } finally {
      setMarking(false);
    }
  };

  /** Responde ou pula, e a câmera volta (FR-009). Uma resposta recusada não prende a tela. */
  const answerMark = async (count: number | null) => {
    if (!marked) return;
    try {
      await collection.answer(marked.itemId, count);
    } catch (e) {
      setCollectionError(collectionMessage(e));
    }
    try {
      await collection.resume();
    } finally {
      setMarked(null);
    }
  };

  /** A captura na tela gravada na coleta, e se a contagem real dela já veio. */
  const captureItem = state === 'result' ? result?.collectionItemId ?? null : null;
  const captureAnswered = captureItem !== null && answered?.itemId === captureItem;

  const answerCapture = async (itemId: string, count: number | null) => {
    try {
      await collection.answer(itemId, count);
      setAnswered({ itemId, count });
    } catch (e) {
      setCollectionError(collectionMessage(e));
      setAnswered({ itemId, count: null });
    }
  };

  return (
    <SafeAreaView style={[styles.fill, { backgroundColor: c.bg }]}>
      <StatusBar style={dark ? 'light' : 'dark'} />
      {info && (
        // Fixo, fora da ScrollView: arrastar a faixa nunca rola a tela (spec
        // 005, FR-018) — e um visor que rola para fora nunca foi o que uma
        // câmera faz.
        <View style={styles.stage}>
          {/* O que o modelo recebe, não a câmera crua. Imagem deitada ou
              objetos distorcidos aparecem aqui antes de virar meia tarde de
              investigação. */}
          <View style={[styles.preview, { borderColor: c.line }]}>
            <PreviewView style={StyleSheet.absoluteFill} />
          </View>
          <Text style={[styles.caption, { color: c.muted }]}>
            Entrada do modelo · {transform}
          </Text>
          {/* A faixa sai de cena na captura e no resultado (FR-020); a
              cápsula some junto, mas guarda o lugar: os cartões não pulam.
              Com o quadro de uma marca parado, também: mexer na faixa mudaria
              o que foi gravado (spec 007). */}
          <BandControl c={c} mode={band?.mode} visible={state === 'live' && !marked}
            onChange={setBandMode} />
          {/* Fixo como o visor: gravando é algo que se vê enquanto se aponta. */}
          {collection.state.open && <CollectionIndicator c={c} state={collection.state} />}
        </View>
      )}
      <ScrollView contentContainerStyle={styles.content}>
        <Text style={[styles.eyebrow, { color: c.muted }]}>MARCO 2 · CÂMERA</Text>
        <Text style={[styles.title, { color: c.ink }]}>vizi</Text>

        {!info && collection.state.open && <CollectionIndicator c={c} state={collection.state} />}

        {collectionError && (
          <Card c={c} border={c.crit} label="MODO COLETA">
            <Text style={{ color: c.ink, fontSize: 13, lineHeight: 18 }}>{collectionError}</Text>
          </Card>
        )}

        {/* O quadro marcado está parado na tela, como estava (R37). */}
        {marked && (
          <TruthPrompt c={c}
            prefill={marked.displayedCount ?? marked.frameCount}
            question={band?.mode === 'off'
              ? 'Quantos livros aparecem no quadro parado?'
              : 'Quantos livros aparecem dentro da faixa, no quadro parado?'}
            onAnswer={answerMark} />
        )}

        {__DEV__ && (
          <View style={[styles.banner, { borderColor: c.crit, backgroundColor: c.bgAlt }]}>
            <Text style={[styles.bannerText, { color: c.crit }]}>
              Bundle Debug — a decodificação custa ~35× o normal. Não julgue fluidez nem
              tempos aqui: o overlay pode derrubar frames que em Release não derrubaria.
            </Text>
          </View>
        )}

        {error && (
          <Card c={c} border={c.crit} label="ERRO">
            <Text style={{ color: c.ink, fontFamily: 'Menlo', fontSize: 13 }}>{error}</Text>
          </Card>
        )}

        {info && (
          <View style={styles.modes}>
            {TOGGLES
              // As divisões só existem sobre o resultado endireitado.
              .filter(([key]) => key !== 'showDividers' || state === 'result')
              .map(([key, label]) => (
              <Pressable
                key={key}
                onPress={() => setOverlay({ [key]: !overlay[key] })}
                style={[styles.mode, {
                  borderColor: overlay[key] ? c.ok : c.line,
                  backgroundColor: c.bgAlt,
                }]}>
                <Text style={{ color: overlay[key] ? c.ok : c.muted, fontSize: 12, fontWeight: '600' }}>
                  {label}
                </Text>
              </Pressable>
            ))}
          </View>
        )}

        <View style={styles.modes}>
          {(['stretch', 'centerCrop', 'letterbox'] as TransformMode[]).map((m) => (
            <Pressable
              key={m}
              onPress={() => setTransform(m)}
              style={[styles.mode, {
                borderColor: transform === m ? c.ok : c.line,
                backgroundColor: c.bgAlt,
              }]}>
              <Text style={{ color: transform === m ? c.ok : c.muted, fontSize: 12, fontWeight: '600' }}>
                {m}
              </Text>
            </Pressable>
          ))}
        </View>

        {info && state !== 'result' && !marked && (
          <>
            <Button c={c} onPress={capture} disabled={state === 'capturing' || marking}
              title={state === 'capturing' ? 'Capturando…' : 'Capturar'} />
            {/* Só ao vivo (FR-010): na captura e no resultado, não há quadro a marcar. */}
            {collection.state.open && (
              <Button c={c} onPress={() => void markFrame()}
                disabled={state !== 'live' || marking}
                title={marking ? 'Marcando…' : 'Marcar este quadro'} />
            )}
            <Pressable
              onPress={() => setDiagnostics(!diagnostics)}
              style={[styles.mode, {
                borderColor: diagnostics ? c.warn : c.line,
                backgroundColor: c.bgAlt,
              }]}>
              <Text style={{ color: diagnostics ? c.warn : c.muted, fontSize: 12, fontWeight: '600' }}>
                {diagnostics ? 'diagnóstico LIGADO' : 'diagnóstico'}
              </Text>
            </Pressable>
          </>
        )}

        {/* O modo coleta (spec 007). Liga com ou sem câmera; some enquanto um
            pedido de contagem real está aberto, que a sessão precisa receber. */}
        {!marked && state !== 'capturing' && !(captureItem && !captureAnswered) && (
          <Pressable
            onPress={() => void toggleCollection()}
            accessibilityRole="switch"
            accessibilityState={{ checked: collection.state.open }}
            style={[styles.mode, {
              borderColor: collection.state.open ? c.crit : c.line,
              backgroundColor: c.bgAlt,
            }]}>
            <Text style={{ color: collection.state.open ? c.crit : c.muted, fontSize: 12, fontWeight: '600' }}>
              {collection.state.open ? 'modo coleta LIGADO — tocar para desligar' : 'modo coleta'}
            </Text>
          </Pressable>
        )}

        {/* A contagem real da captura, antes do cartão: é o que a coleta pede
            agora (FR-007). */}
        {captureItem && !captureAnswered && result && (
          <TruthPrompt c={c} prefill={result.count}
            question="Quantos livros aparecem no resultado?"
            onAnswer={(count) => answerCapture(captureItem, count)} />
        )}
        {captureItem && captureAnswered && answered && (
          <Text style={{ color: c.ok, fontSize: 13 }}>
            {answered.count === null ? 'Contagem real pulada.' : `Contagem real registrada: ${answered.count}.`}
          </Text>
        )}
        {state === 'result' && result?.collectionSkipped === 'space' && (
          <Text style={{ color: c.warn, fontSize: 13, lineHeight: 18 }}>
            Captura não gravada na coleta: pouco espaço livre no aparelho.
          </Text>
        )}

        {state === 'result' && result && (
          <Card c={c} border={c.ok} label="RESULTADO">
            <Row c={c} label="livros" value={String(result.count)} strong />
            {/* Vazia é a faixa, não a cena: dizer "nenhum livro" mandaria a
                pessoa procurar o problema no lugar errado (spec 005, US1).
                Só vale para a foto: com recorte, a faixa tinha livros. */}
            {result.count === 0 && result.countSource === 'photo' && result.outsideBandCount > 0 && (
              <Text style={{ color: c.warn, fontSize: 13, lineHeight: 18 }}>
                Nenhum livro na faixa — {result.outsideBandCount} fora dela.
              </Text>
            )}
            {/* A foto achou livros, ou não haveria recorte: quem não achou foi
                a releitura (spec 006, R34). */}
            {result.count === 0 && result.countSource === 'reread' && (
              <Text style={{ color: c.warn, fontSize: 13, lineHeight: 18 }}>
                A releitura não encontrou livros no recorte.
              </Text>
            )}
            <Row c={c} label="leitura"
              value={result.countSource === 'reread' ? 'recorte na tela' : 'foto'} />
            {result.countSource === 'reread' && (
              <Row c={c} label="releitura" value={`${result.rereadMs.toFixed(0)} ms`} />
            )}
            <Row c={c} label="fora da faixa" value={String(result.outsideBandCount)} />
            <Row c={c} label="foto" value={`${result.photoWidth}×${result.photoHeight}`} />
            <Row c={c} label="tempo" value={`${result.elapsedMs.toFixed(0)} ms`} strong />
            <Row c={c} label="toque → pronto" value={`${result.readyMs.toFixed(0)} ms`} strong />
            <Row c={c} label="endireitado" value={result.straightened ? 'sim' : `não — ${result.declineReason}`} />
            <Row c={c} label="geometria · confiança" value={result.geometryConfidence.toFixed(3)} />
            <Row c={c} label="azimute · confiança" value={result.azimuthConfidence.toFixed(3)} />
            <Row c={c} label="vertical" value={result.usedGravity ? 'gravidade' : 'lombadas (recuo)'} />
            <Row c={c} label="deitados" value={String(result.lyingCount)} />
            <Row c={c} label="prateleiras" value={String(result.shelfCount)} strong />
            {result.shelves.map((sh, i) => (
              <Row key={i} c={c}
                label={`fileira ${i + 1} · banda ${(sh.top * 100).toFixed(0)}–${(sh.bottom * 100).toFixed(0)}%`}
                value={`${sh.count} livros · ${sh.dividers.length} divisões`} />
            ))}
          </Card>
        )}

        {state === 'result' && (
          <>
            <Button c={c} onPress={save} disabled={saving || saved !== null}
              title={saved ? 'Salvo no histórico ✓' : saving ? 'Salvando…' : 'Salvar no histórico'} />
            <Button c={c} onPress={dismiss} disabled={false} title="Voltar à câmera" />
          </>
        )}

        {saveError && (
          <Card c={c} border={c.crit} label="ERRO AO SALVAR">
            <Text style={{ color: c.ink, fontFamily: 'Menlo', fontSize: 13 }}>{saveError}</Text>
          </Card>
        )}

        {captureError && (
          <Card c={c} border={c.crit} label="ERRO NA CAPTURA">
            <Text style={{ color: c.ink, fontFamily: 'Menlo', fontSize: 13 }}>{captureError}</Text>
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
            <Row c={c} label="objetos" value={String(sample.instanceCount)} strong />
            <Row c={c} label="transformação" value={`${sample.transformMs.toFixed(2)} ms`} />
            <Row c={c} label="inferência" value={`${sample.inferMs.toFixed(2)} ms`} />
            <Row c={c} label="decodificação" value={`${sample.decodeMs.toFixed(2)} ms`} />
            <Row c={c} label="ponta-a-ponta" value={`${sample.e2eMs.toFixed(1)} ms`} strong />
            <Row c={c} label="overlay" value={sample.overlayAttached ? 'ligado' : 'DESLIGADO'} />
            <Row c={c} label="desenhadas" value={String(sample.overlayDrawnCount)} />
            <Row c={c} label="desenho" value={`${sample.drawMs.toFixed(2)} ms`} />
            <Row c={c} label="fila" value={String(sample.queueDepth)} />
            <Row c={c} label="descartados" value={String(sample.dropped)} />
            <Row c={c} label="térmico" value={sample.thermalState} />
            <Row c={c} label="bateria" value={sample.batteryLevel < 0 ? '—' : `${(sample.batteryLevel * 100).toFixed(0)}%`} />
            <Row c={c} label="tempo" value={`${(sample.t / 1000).toFixed(0)} s`} />
          </Card>
        )}

        {session && (
          <>
            <Card c={c} border={verdicts.every((v) => v.pass) ? c.ok : c.crit}
              label={verdicts.every((v) => v.pass) ? 'PORTÃO ATINGIDO' : 'PORTÃO NÃO ATINGIDO'}>
              {verdicts.map((v) => (
                <Row key={v.label} c={c} label={`${v.pass ? '✓' : '✗'} ${v.label}`} value={v.detail} />
              ))}
            </Card>

            <Card c={c} border={c.line} label="SESSÃO">
              <Row c={c} label="duração" value={`${(session.durationMs / 1000 / 60).toFixed(1)} min`} />
              <Row c={c} label="transformação" value={session.transform} />
              <Row c={c} label="frames" value={`${session.processed} de ${session.received}`} />
              <Row c={c} label="térmico" value={`${session.thermalAtStart} → ${session.thermalAtEnd}`} />
              <Row c={c} label="amostras" value={`${session.samples.length}${session.truncated ? ' (truncado)' : ''}`} />
            </Card>

            {session.thermalTransitions.length > 0 && (
              <Card c={c} border={c.warn} label="TRANSIÇÕES TÉRMICAS">
                {session.thermalTransitions.map((tr, i) => (
                  <Row key={i} c={c} label={`${(tr.t / 1000 / 60).toFixed(1)} min`}
                    value={`${tr.from} → ${tr.to}`} />
                ))}
              </Card>
            )}

            <Button c={c} disabled={false} title={copied ? 'Copiado ✓' : 'Copiar sessão (JSON)'}
              onPress={async () => {
                await copySessionToClipboard(session, result);
                setCopied(true);
              }} />
          </>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

/** Camadas desenhadas sobre a imagem. O estilo de cada uma é do `OverlayStyle`. */
const TOGGLES = [
  ['showBoxes', 'caixas'],
  ['showMasks', 'máscaras'],
  ['showDividers', 'divisões'],
] as const;

const styles = StyleSheet.create({
  fill: { flex: 1 },
  content: { padding: 24, gap: 14 },
  stage: { paddingHorizontal: 24, paddingTop: 12, gap: 14 },
  eyebrow: { fontSize: 11, letterSpacing: 1.4, fontWeight: '600' },
  title: { fontSize: 34, fontWeight: '700', letterSpacing: -0.5, marginTop: -8 },
  banner: { borderWidth: 1, borderLeftWidth: 3, borderRadius: 4, padding: 12 },
  bannerText: { fontSize: 12, lineHeight: 17 },
  preview: { aspectRatio: 1, borderWidth: 1, borderRadius: 4, overflow: 'hidden' },
  caption: { fontSize: 11, letterSpacing: 0.6, marginTop: -8 },
  modes: { flexDirection: 'row', gap: 8 },
  mode: { flex: 1, borderWidth: 1, borderRadius: 4, paddingVertical: 10, alignItems: 'center' },
});
