import React, { useEffect, useRef } from 'react';
import type { YOLO } from '@ultralytics/yolo';
import type { FacingMode } from '../hooks/useWebcam';
import { createTracker, type TrackedBox } from '../lib/tracker';
import { createMaskPainter, drawBoxes, type OverlayOptions } from '../lib/overlay';
import type { Diagnostics } from './DiagnosticsPanel';
import { detectionIntervalMs, motionThreshold } from '../lib/debugFlags';
import { createMotionSampler } from '../lib/motion';

// Quantos frames seguidos a contagem precisa se repetir antes de virar estado.
// Sem isso o número pisca a cada tremida da câmera.
const COUNT_STABILITY_FRAMES = 3;

// De quanto em quanto tempo o detector de movimento reamostra enquanto a cena
// está parada. Define a latência para voltar a inferir quando algo se move:
// 60ms é imperceptível e mantém o custo do polling irrisório. Durante uma cena
// em movimento isso não limita nada — a inferência já demora bem mais que isso.
const MOTION_SAMPLE_INTERVAL_MS = 60;

// Com a cena parada não há inferência, e sem isso o painel congelaria no último
// valor. Reportar 4x/s mantém a leitura de movimento viva para calibrar o
// limiar, sem transformar o gating num gerador de re-render.
const GATED_DIAGNOSTICS_INTERVAL_MS = 250;

// Guarda térmica. O motion gating só poupa o aparelho quando ele está apoiado:
// segurando na mão a leitura de movimento fica sempre acima do limiar (medido:
// 3.0-10.0 contra limiar de 0.5), então o loop infere sem parar e esquenta. O
// throttling é observável — o mesmo modelo mediu 264ms com o aparelho frio e
// 317ms depois de meia hora de uso.
//
// Quando a inferência fica mais lenta que o melhor caso por esta margem,
// assume-se throttling e devolve-se um pedaço do ciclo ao aparelho. É
// auto-corretivo: esfriando, a média volta a cair e a guarda se solta sozinha.
//
// LIMITAÇÃO CONHECIDA: "melhor caso" é o melhor **desta sessão**. Abrindo o app
// com o aparelho já quente, a referência nasce quente e a guarda nunca dispara —
// observado em 14/09/2026, com infer em 306ms contra 264ms medidos a frio, e
// nenhuma guarda ativa. O painel mostra `min` ao lado de `infer` justamente para
// esse caso ficar visível. Uma referência absoluta exigiria persistir o melhor
// tempo entre sessões, o que traz o problema oposto: um recorde tirado num dia
// frio deixaria a guarda ligada para sempre.
const THERMAL_SLOWDOWN_RATIO = 1.25;

// Fração do tempo de inferência devolvida como ociosidade enquanto a guarda
// está ativa. Sair de 100% para 80% de ocupação custa pouco fps e é o bastante
// para o SoC recuperar clock.
const THERMAL_IDLE_FRACTION = 0.25;

// Quantas inferências observar antes de confiar no "melhor caso". Sem isso uma
// única leitura atipicamente rápida no começo viraria a referência e deixaria a
// guarda permanentemente ativa.
const THERMAL_WARMUP_SAMPLES = 5;

interface DetectionViewProps extends OverlayOptions {
  model: YOLO;
  stream: MediaStream;
  facingMode: FacingMode;
  /** Limiar de confiança. 0.25 é o padrão do Ultralytics, e é permissivo. */
  confidence: number;
  onBookCountChange: (count: number) => void;
  /** Quando ausente, nada é medido nem reportado: o loop não paga por isso. */
  onDiagnostics?: (diagnostics: Diagnostics) => void;
}

export const DetectionView: React.FC<DetectionViewProps> = ({
  model,
  stream,
  facingMode,
  showBoxes,
  showMasks,
  maskOpacity,
  confidence,
  onBookCountChange,
  onDiagnostics
}) => {
  const videoRef = useRef<HTMLVideoElement>(null);

  // Duas camadas em vez de um canvas só. A máscara é reescrita uma vez por
  // inferência (~3x/s) e as caixas a cada frame (60x/s); num canvas único,
  // desenhar a 60 FPS significaria refazer um putImageData de ~1.2 MB sessenta
  // vezes por segundo para uma imagem que quase nunca muda.
  const maskCanvasRef = useRef<HTMLCanvasElement>(null);
  const boxCanvasRef = useRef<HTMLCanvasElement>(null);

  // Último resultado de inferência, lido pelo loop de desenho a cada frame.
  const lastFrameRef = useRef<{ tracked: TrackedBox[] } | null>(null);

  // Os loops pulam o trabalho quando a camada correspondente está escondida.
  // Vivem em refs, e não nas dependências dos efeitos, porque marcar um
  // checkbox não pode recriar o loop — isso zeraria o tracker e reiniciaria a
  // numeração dos livros.
  const showBoxesRef = useRef(showBoxes);
  useEffect(() => {
    showBoxesRef.current = showBoxes;
  }, [showBoxes]);

  const showMasksRef = useRef(showMasks);
  useEffect(() => {
    showMasksRef.current = showMasks;
  }, [showMasks]);

  // Mesmo motivo: mudar o limiar não pode recriar o tracker.
  const confidenceRef = useRef(confidence);
  useEffect(() => {
    confidenceRef.current = confidence;
  }, [confidence]);

  // Acopla a stream de mídia ao elemento de vídeo local
  useEffect(() => {
    if (videoRef.current && stream) {
      videoRef.current.srcObject = stream;
    }
  }, [stream]);

  // Loop de detecção. Vive inteiro dentro do efeito: o rAF só roda depois da
  // montagem, e todo o estado do loop é local, morrendo junto com o cleanup.
  useEffect(() => {
    let isActive = true;
    let frameId = 0;
    let isInferring = false;
    let lastDetectionAt = 0;

    // Instante em que a inferência anterior começou, e a média móvel do
    // intervalo entre elas. Medir o começo — e não o fim — é o que dá o ciclo
    // completo: inclui o tempo em que o loop ficou esperando.
    let lastInferenceStartedAt = 0;
    let emaIntervalMs = 0;

    // Gating de movimento: enquanto a cena não muda, não se infere.
    const motion = createMotionSampler();
    let lastMotionSampleAt = 0;
    let lastMotionValue = Infinity;
    let lastGatedReportAt = 0;

    // Guarda térmica: melhor caso observado (proxy do aparelho frio) contra a
    // média móvel atual.
    let fastestInferenceMs = Infinity;
    let emaInferenceMs = 0;
    let inferenceSamples = 0;

    /** Ociosidade a intercalar por causa de calor, em ms. 0 = aparelho saudável. */
    const thermalIdleMs = () => {
      if (inferenceSamples < THERMAL_WARMUP_SAMPLES) return 0;
      if (emaInferenceMs <= fastestInferenceMs * THERMAL_SLOWDOWN_RATIO) return 0;

      return emaInferenceMs * THERMAL_IDLE_FRACTION;
    };

    // Contagem estabilizada: valor publicado + candidato em observação
    let publishedCount = 0;
    let candidateCount = 0;
    let candidateStreak = 0;

    // Identidade das entidades. Nasce e morre com o loop: trocar de lente
    // remonta o componente com outra stream, o que reinicia a numeração.
    const tracker = createTracker();
    const paintMask = createMaskPainter();

    // Só promove a contagem depois de COUNT_STABILITY_FRAMES leituras iguais
    const publishStableCount = (count: number) => {
      if (count === candidateCount) {
        candidateStreak += 1;
      } else {
        candidateCount = count;
        candidateStreak = 1;
      }

      if (candidateStreak >= COUNT_STABILITY_FRAMES && count !== publishedCount) {
        publishedCount = count;
        onBookCountChange(count);
      }
    };

    const scheduleNext = () => {
      if (isActive) frameId = requestAnimationFrame(detectFrame);
    };

    const detectFrame = async () => {
      if (!isActive) return;

      const video = videoRef.current;
      const maskCanvas = maskCanvasRef.current;
      const boxCanvas = boxCanvasRef.current;

      if (!video || !maskCanvas || !boxCanvas || video.readyState < 2) {
        scheduleNext();
        return;
      }

      // Throttle + guarda de reentrância: a inferência wasm leva centenas de ms
      // e não pode ter duas chamadas concorrentes na mesma instância do modelo.
      const minIntervalMs = Math.max(detectionIntervalMs, thermalIdleMs());
      if (isInferring || performance.now() - lastDetectionAt < minIntervalMs) {
        scheduleNext();
        return;
      }

      // Gating de movimento. A leitura é reaproveitada por
      // MOTION_SAMPLE_INTERVAL_MS: parado, isso vira o único trabalho do loop;
      // em movimento, a inferência já é mais lenta que o intervalo e cada
      // inferência tem sua própria amostra fresca.
      const nowBeforeMotion = performance.now();
      if (nowBeforeMotion - lastMotionSampleAt >= MOTION_SAMPLE_INTERVAL_MS) {
        lastMotionValue = motion.sample(video);
        lastMotionSampleAt = nowBeforeMotion;
      }

      if (lastMotionValue < motionThreshold) {
        // Cena parada: a máscara na tela continua válida e as caixas seguem
        // sendo redesenhadas pelo loop de desenho, com velocidade ~zero.
        if (onDiagnostics && nowBeforeMotion - lastGatedReportAt >= GATED_DIAGNOSTICS_INTERVAL_MS) {
          lastGatedReportAt = nowBeforeMotion;
          onDiagnostics({
            frame: `${maskCanvas.width}x${maskCanvas.height}`,
            boxes: lastFrameRef.current?.tracked.length ?? 0,
            maskBytes: 0,
            expectedMaskBytes: maskCanvas.width * maskCanvas.height * 4,
            preprocessMs: 0,
            inferenceMs: 0,
            postprocessMs: 0,
            drawMs: 0,
            predictMs: 0,
            intervalMs: emaIntervalMs,
            motion: lastMotionValue,
            gated: true,
            thermalIdleMs: thermalIdleMs(),
            fastestInferenceMs,
            error: null
          });
        }

        scheduleNext();
        return;
      }

      // Sincroniza dimensões das duas camadas com o frame de vídeo.
      if (maskCanvas.width !== video.videoWidth || maskCanvas.height !== video.videoHeight) {
        maskCanvas.width = video.videoWidth;
        maskCanvas.height = video.videoHeight;
        boxCanvas.width = video.videoWidth;
        boxCanvas.height = video.videoHeight;
      }

      // Fecha o ciclo anterior antes de abrir o próximo. Sem onDiagnostics o
      // intervalo não é acompanhado: o loop não paga nem por isso.
      if (onDiagnostics) {
        const startedAt = performance.now();

        if (lastInferenceStartedAt > 0) {
          const intervalMs = startedAt - lastInferenceStartedAt;
          emaIntervalMs = emaIntervalMs > 0 ? emaIntervalMs * 0.8 + intervalMs * 0.2 : intervalMs;
        }

        lastInferenceStartedAt = startedAt;
      }

      isInferring = true;
      try {
        // O elemento de vídeo entra no fast path da lib (pixels crus, sem
        // re-encode). O modelo tem classe única, então results.boxes já é só
        // o que interessa — sem filtro por classe. Sendo de segmentação, o
        // mesmo results traz a máscara junto, numa inferência só.
        //
        // Relógio por fora: o `speed` do engine não cobre a leitura de pixels
        // nem a cópia dos resultados para fora do wasm, que acontecem no
        // wrapper (`toImageData`, antes de entrar no engine).
        const predictStartedAt = onDiagnostics ? performance.now() : 0;
        const results = await model.predict(video, { conf: confidenceRef.current });
        const predictMs = onDiagnostics ? performance.now() - predictStartedAt : 0;

        if (!isActive) return;

        const finishedAt = performance.now();
        lastDetectionAt = finishedAt;

        // A referência de movimento passa a ser o frame que gerou o resultado
        // agora na tela: comparar sempre contra ele é o que faz uma deriva
        // lenta acabar acumulando diferença suficiente para disparar.
        motion.commit();

        // Alimenta a guarda térmica com o custo observado desta inferência.
        inferenceSamples += 1;
        emaInferenceMs =
          emaInferenceMs > 0
            ? emaInferenceMs * 0.8 + results.speed.inference * 0.2
            : results.speed.inference;
        fastestInferenceMs = Math.min(fastestInferenceMs, results.speed.inference);

        // O instante do resultado é o que o loop de desenho usa como origem da
        // extrapolação, então precisa ser o mesmo para tracker e projeção.
        const tracked = tracker.update(results.boxes, finishedAt);
        publishStableCount(tracked.length);

        // A inferência segue rodando mesmo com os dois modos desmarcados: é o
        // que mantém a contagem do topo viva enquanto o vídeo fica limpo.
        lastFrameRef.current = { tracked };

        // A máscara é escrita só aqui; as caixas ficam por conta do loop de
        // desenho. Escondida, nem isso: putImageData de ~1.2 MB é o trabalho
        // mais caro do ciclo depois da inferência.
        const drawStartedAt = onDiagnostics ? performance.now() : 0;
        if (showMasksRef.current) {
          const maskCtx = maskCanvas.getContext('2d');
          if (maskCtx) paintMask(maskCtx, results.masks);
        }
        const drawMs = onDiagnostics ? performance.now() - drawStartedAt : 0;

        onDiagnostics?.({
          frame: `${maskCanvas.width}x${maskCanvas.height}`,
          boxes: results.boxes.length,
          maskBytes: results.masks.length,
          expectedMaskBytes: maskCanvas.width * maskCanvas.height * 4,
          preprocessMs: results.speed.preprocess,
          inferenceMs: results.speed.inference,
          postprocessMs: results.speed.postprocess,
          drawMs,
          predictMs,
          intervalMs: emaIntervalMs,
          motion: lastMotionValue,
          gated: false,
          thermalIdleMs: thermalIdleMs(),
          fastestInferenceMs,
          error: null
        });
      } catch (err) {
        console.error('Falha na inferência:', err);

        // No iOS a única forma de ver isto é na tela, então o erro sobe.
        onDiagnostics?.({
          frame: `${maskCanvas.width}x${maskCanvas.height}`,
          boxes: 0,
          maskBytes: 0,
          expectedMaskBytes: maskCanvas.width * maskCanvas.height * 4,
          preprocessMs: 0,
          inferenceMs: 0,
          postprocessMs: 0,
          drawMs: 0,
          predictMs: 0,
          // O intervalo continua válido: o ciclo aconteceu, só falhou no meio.
          intervalMs: emaIntervalMs,
          motion: lastMotionValue,
          gated: false,
          thermalIdleMs: thermalIdleMs(),
          fastestInferenceMs,
          error: String(err)
        });
      } finally {
        isInferring = false;
      }

      scheduleNext();
    };

    detectFrame();

    return () => {
      isActive = false;
      lastFrameRef.current = null;
      if (frameId) cancelAnimationFrame(frameId);
    };
  }, [model, stream, onBookCountChange, onDiagnostics]);

  // Loop de desenho das caixas, independente da inferência. Redesenha a cada
  // frame projetando cada caixa para o instante atual pela velocidade estimada:
  // é o que faz o overlay parecer contínuo sobre ~3 inferências por segundo, em
  // vez de congelar por 300ms e saltar.
  useEffect(() => {
    let isActive = true;
    let frameId = 0;

    const drawFrame = () => {
      if (!isActive) return;

      const canvas = boxCanvasRef.current;
      const last = lastFrameRef.current;

      if (canvas && showBoxesRef.current) {
        const ctx = canvas.getContext('2d');
        if (ctx) drawBoxes(ctx, last?.tracked ?? [], performance.now());
      }

      frameId = requestAnimationFrame(drawFrame);
    };

    frameId = requestAnimationFrame(drawFrame);

    return () => {
      isActive = false;
      cancelAnimationFrame(frameId);
    };
  }, []);

  const mirrorStyle = { transform: facingMode === 'user' ? 'scaleX(-1)' : 'scaleX(1)' };

  return (
    <div className="video-container">
      <video
        ref={videoRef}
        autoPlay
        playsInline
        muted
        className="video"
        style={mirrorStyle}
      />
      {/* A opacidade desce como custom property: mexer no slider é trabalho de
          compositor, sem repintura e sem esperar a próxima inferência. */}
      <canvas
        ref={maskCanvasRef}
        className={`canvas mask-layer${showMasks ? '' : ' layer-hidden'}`}
        style={{ ...mirrorStyle, '--mask-opacity': maskOpacity } as React.CSSProperties}
      />
      <canvas
        ref={boxCanvasRef}
        className={`canvas box-layer${showBoxes ? '' : ' layer-hidden'}`}
        style={mirrorStyle}
      />
    </div>
  );
};
