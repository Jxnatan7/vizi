import React, { useEffect, useRef } from 'react';
import type { YOLO } from '@ultralytics/yolo';
import type { FacingMode } from '../hooks/useWebcam';
import { createTracker, type TrackedBox } from '../lib/tracker';
import { drawOverlay, type OverlayOptions } from '../lib/overlay';
import type { Diagnostics } from './DiagnosticsPanel';

// Intervalo alvo entre inferências. O vídeo continua a 60fps; só a detecção
// é limitada, senão o wasm monopoliza a thread e a UI trava.
const DETECTION_INTERVAL_MS = 100;

// Quantos frames seguidos a contagem precisa se repetir antes de virar estado.
// Sem isso o número pisca a cada tremida da câmera.
const COUNT_STABILITY_FRAMES = 3;

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
  const canvasRef = useRef<HTMLCanvasElement>(null);

  // Canvas auxiliar da máscara. Fica num ref para ser criado uma vez só: alocar
  // um canvas do tamanho do frame a cada inferência derrubaria o desempenho.
  const offscreenRef = useRef<HTMLCanvasElement | null>(null);
  if (offscreenRef.current === null) {
    offscreenRef.current = document.createElement('canvas');
  }

  // As opções de exibição vivem num ref, não nas dependências do loop: trocar
  // um checkbox não pode recriar o tracker e reiniciar a numeração dos livros.
  const optionsRef = useRef<OverlayOptions>({ showBoxes, showMasks, maskOpacity });

  // Mesmo motivo do optionsRef: mudar o limiar não pode recriar o tracker.
  const confidenceRef = useRef(confidence);
  useEffect(() => {
    confidenceRef.current = confidence;
  }, [confidence]);

  // Último resultado desenhado, para refletir o clique na hora em vez de
  // esperar até DETECTION_INTERVAL_MS pela próxima inferência.
  const lastFrameRef = useRef<{ tracked: TrackedBox[]; masks: Uint8Array } | null>(null);

  // Acopla a stream de mídia ao elemento de vídeo local
  useEffect(() => {
    if (videoRef.current && stream) {
      videoRef.current.srcObject = stream;
    }
  }, [stream]);

  // Redesenha imediatamente quando a exibição muda, sobre o resultado que já
  // está em mãos. Sem isso a máscara some com um atraso perceptível.
  useEffect(() => {
    optionsRef.current = { showBoxes, showMasks, maskOpacity };

    const canvas = canvasRef.current;
    const offscreen = offscreenRef.current;
    const last = lastFrameRef.current;
    if (!canvas || !offscreen || !last) return;

    const ctx = canvas.getContext('2d');
    if (ctx) drawOverlay(ctx, offscreen, last.tracked, last.masks, optionsRef.current);
  }, [showBoxes, showMasks, maskOpacity]);

  // Loop de detecção. Vive inteiro dentro do efeito: o rAF só roda depois da
  // montagem, e todo o estado do loop é local, morrendo junto com o cleanup.
  useEffect(() => {
    let isActive = true;
    let frameId = 0;
    let isInferring = false;
    let lastDetectionAt = 0;

    // Contagem estabilizada: valor publicado + candidato em observação
    let publishedCount = 0;
    let candidateCount = 0;
    let candidateStreak = 0;

    // Identidade das entidades. Nasce e morre com o loop: trocar de lente
    // remonta o componente com outra stream, o que reinicia a numeração.
    const tracker = createTracker();

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
      const canvas = canvasRef.current;
      const offscreen = offscreenRef.current;

      if (!video || !canvas || !offscreen || video.readyState < 2) {
        scheduleNext();
        return;
      }

      // Throttle + guarda de reentrância: a inferência wasm leva dezenas de ms
      // e não pode ter duas chamadas concorrentes na mesma instância do modelo.
      if (isInferring || performance.now() - lastDetectionAt < DETECTION_INTERVAL_MS) {
        scheduleNext();
        return;
      }

      // Sincroniza dimensões
      if (canvas.width !== video.videoWidth || canvas.height !== video.videoHeight) {
        canvas.width = video.videoWidth;
        canvas.height = video.videoHeight;
      }

      isInferring = true;
      try {
        // O elemento de vídeo entra no fast path da lib (pixels crus, sem
        // re-encode). O modelo tem classe única, então results.boxes já é só
        // o que interessa — sem filtro por classe. Sendo de segmentação, o
        // mesmo results traz a máscara junto, numa inferência só.
        const results = await model.predict(video, { conf: confidenceRef.current });

        if (!isActive) return;

        lastDetectionAt = performance.now();

        const tracked = tracker.update(results.boxes);
        publishStableCount(tracked.length);

        // A inferência segue rodando mesmo com os dois modos desmarcados: é o
        // que mantém a contagem do topo viva enquanto o vídeo fica limpo.
        lastFrameRef.current = { tracked, masks: results.masks };

        const ctx = canvas.getContext('2d');
        if (ctx) drawOverlay(ctx, offscreen, tracked, results.masks, optionsRef.current);

        onDiagnostics?.({
          frame: `${canvas.width}x${canvas.height}`,
          boxes: results.boxes.length,
          maskBytes: results.masks.length,
          expectedMaskBytes: canvas.width * canvas.height * 4,
          inferenceMs: results.speed.inference,
          error: null
        });
      } catch (err) {
        console.error('Falha na inferência:', err);

        // No iOS a única forma de ver isto é na tela, então o erro sobe.
        onDiagnostics?.({
          frame: `${canvas.width}x${canvas.height}`,
          boxes: 0,
          maskBytes: 0,
          expectedMaskBytes: canvas.width * canvas.height * 4,
          inferenceMs: 0,
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
      <canvas
        ref={canvasRef}
        className="canvas"
        style={mirrorStyle}
      />
    </div>
  );
};
