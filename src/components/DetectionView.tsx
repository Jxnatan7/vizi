import React, { useEffect, useRef } from 'react';
import * as cocoSsd from '@tensorflow-models/coco-ssd';
import type { FacingMode } from '../hooks/useWebcam';

interface DetectionViewProps {
  model: cocoSsd.ObjectDetection;
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
  const requestRef = useRef<number>(0);
  const lastBookCountRef = useRef<number>(0);

  // Acopla a stream de mídia ao elemento de vídeo local
  useEffect(() => {
    if (videoRef.current && stream) {
      videoRef.current.srcObject = stream;
    }
  }, [stream]);

  const drawBoundingBoxes = (predictions: cocoSsd.DetectedObject[], ctx: CanvasRenderingContext2D) => {
    ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);

    predictions.forEach((prediction) => {
      const [x, y, width, height] = prediction.bbox;
      const scoreText = `Book - ${Math.round(prediction.score * 100)}%`;

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

  const detectFrame = async () => {
    const video = videoRef.current;
    const canvas = canvasRef.current;

    if (!video || !canvas || video.readyState < 2) {
      requestRef.current = requestAnimationFrame(detectFrame);
      return;
    }

    // Sincroniza dimensões
    if (canvas.width !== video.videoWidth || canvas.height !== video.videoHeight) {
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
    }

    const predictions = await model.detect(video);
    const filteredPredictions = predictions.filter(
      (p) => p.class === 'book' && p.score >= 0.5
    );

    // Controle de estado levantado (Lifting State Up) condicional
    if (filteredPredictions.length !== lastBookCountRef.current) {
      lastBookCountRef.current = filteredPredictions.length;
      onBookCountChange(filteredPredictions.length);
    }

    const ctx = canvas.getContext('2d');
    if (ctx) drawBoundingBoxes(filteredPredictions, ctx);

    requestRef.current = requestAnimationFrame(detectFrame);
  };

  const handleVideoLoad = () => {
    // Inicia o loop apenas quando o vídeo está pronto
    detectFrame();
  };

  // Limpa a animação quando desmontar ou a stream mudar
  useEffect(() => {
    return () => {
      if (requestRef.current) cancelAnimationFrame(requestRef.current);
    };
  }, []);

  const mirrorStyle = { transform: facingMode === 'user' ? 'scaleX(-1)' : 'scaleX(1)' };

  return (
    <div className="video-container">
      <video 
        ref={videoRef} 
        onLoadedData={handleVideoLoad}
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