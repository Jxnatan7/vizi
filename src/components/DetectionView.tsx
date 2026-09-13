import React, { useEffect, useRef } from 'react';
import type { Box, YOLO } from '@ultralytics/yolo';
import type { FacingMode } from '../hooks/useWebcam';

// Padrão do Ultralytics — mesmo comportamento da validação em Python.
const CONFIDENCE_THRESHOLD = 0.25;

// Intervalo alvo entre inferências. O vídeo continua a 60fps; só a detecção
// é limitada, senão o wasm monopoliza a thread e a UI trava.
const DETECTION_INTERVAL_MS = 100;

// Quantos frames seguidos a contagem precisa se repetir antes de virar estado.
// Sem isso o número pisca a cada tremida da câmera.
const COUNT_STABILITY_FRAMES = 3;

// Nomes de exibição por classe do modelo. A chave vem do metadata do .tflite.
const DISPLAY_NAMES: Record<string, string> = {
  'Bookshelf-counter': 'Estante',
};

const drawBoundingBoxes = (boxes: Box[], ctx: CanvasRenderingContext2D) => {
  ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);

  boxes.forEach((box) => {
    // A lib devolve xyxy em pixels; o canvas desenha a partir de x/y + tamanho.
    const x = box.x1;
    const y = box.y1;
    const width = box.x2 - box.x1;
    const height = box.y2 - box.y1;
    const label = DISPLAY_NAMES[box.name] ?? box.name;
    const scoreText = `${label} - ${Math.round(box.conf * 100)}%`;

    ctx.strokeStyle = '#00FF00';
    ctx.lineWidth = 4;
    ctx.strokeRect(x, y, width, height);

    ctx.font = '16px Arial';
    const textWidth = ctx.measureText(scoreText).width;
    const textHeight = 24;

    ctx.fillStyle = '#00FF00';
    ctx.fillRect(x, y - textHeight, textWidth + 10, textHeight);

    ctx.fillStyle = '#000000';
    ctx.fillText(scoreText, x + 5, y - 6);
  });
};

interface DetectionViewProps {
  model: YOLO;
  stream: MediaStream;
  facingMode: FacingMode;
  onBookCountChange: (count: number) => void;
}

export const DetectionView: React.FC<DetectionViewProps> = ({
  model,
  stream,
  facingMode,
  onBookCountChange
}) => {
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);

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

    // Contagem estabilizada: valor publicado + candidato em observação
    let publishedCount = 0;
    let candidateCount = 0;
    let candidateStreak = 0;

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

      if (!video || !canvas || video.readyState < 2) {
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
        // o que interessa — sem filtro por classe.
        const results = await model.predict(video, { conf: CONFIDENCE_THRESHOLD });

        if (!isActive) return;

        lastDetectionAt = performance.now();
        publishStableCount(results.boxes.length);

        const ctx = canvas.getContext('2d');
        if (ctx) drawBoundingBoxes(results.boxes, ctx);
      } catch (err) {
        console.error('Falha na inferência:', err);
      } finally {
        isInferring = false;
      }

      scheduleNext();
    };

    detectFrame();

    return () => {
      isActive = false;
      if (frameId) cancelAnimationFrame(frameId);
    };
  }, [model, onBookCountChange]);

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
