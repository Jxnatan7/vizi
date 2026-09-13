import React, { useState, useEffect, useRef } from 'react';
import * as tf from '@tensorflow/tfjs';
import '@tensorflow/tfjs-backend-webgl';
import * as cocoSsd from '@tensorflow-models/coco-ssd';
import './App.css';

const App: React.FC = () => {
  // --- 2. State Structure ---
  const [isModelLoaded, setIsModelLoaded] = useState<boolean>(false);
  const [isCameraActive, setIsCameraActive] = useState<boolean>(false);
  const [bookCount, setBookCount] = useState<number>(0);
  const [cameraError, setCameraError] = useState<string | null>(null);
  
  // Novo estado para controlar qual câmera está ativa (traseira ou frontal)
  const [facingMode, setFacingMode] = useState<'environment' | 'user'>('environment');

  // --- 2. References ---
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const modelRef = useRef<cocoSsd.ObjectDetection | null>(null);
  const requestRef = useRef<number>(0);
  const lastBookCountRef = useRef<number>(0);
  const isDetectingRef = useRef<boolean>(false); // Evita múltiplos loops de detecção

  // --- 3. Initialization & Lifecycle ---
  useEffect(() => {
    const initApp = async () => {
      try {
        await tf.setBackend('webgl');
        await tf.ready();
        
        const loadedModel = await cocoSsd.load();
        modelRef.current = loadedModel;
        setIsModelLoaded(true);
      } catch (error) {
        console.error('Falha ao inicializar o TensorFlow ou carregar o modelo:', error);
      }
    };

    initApp();

    return () => {
      isDetectingRef.current = false;
      if (requestRef.current) {
        cancelAnimationFrame(requestRef.current);
      }
      if (videoRef.current && videoRef.current.srcObject) {
        const stream = videoRef.current.srcObject as MediaStream;
        stream.getTracks().forEach((track) => track.stop());
      }
    };
  }, []);

  // --- 5. Native Canvas Drawing (DOM Bypass) ---
  const drawBoundingBoxes = (predictions: cocoSsd.DetectedObject[]) => {
    if (!canvasRef.current) return;
    
    const ctx = canvasRef.current.getContext('2d');
    if (!ctx) return;

    ctx.clearRect(0, 0, canvasRef.current.width, canvasRef.current.height);

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

  // --- 4. The Detection Loop ---
  const detectFrame = async () => {
    if (!isDetectingRef.current) return;

    const video = videoRef.current;
    const canvas = canvasRef.current;
    const model = modelRef.current;

    if (!video || !canvas || !model || video.readyState < 2) {
      requestRef.current = requestAnimationFrame(detectFrame);
      return;
    }

    if (canvas.width !== video.videoWidth || canvas.height !== video.videoHeight) {
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
    }

    const predictions = await model.detect(video);

    const filteredPredictions = predictions.filter(
      (prediction) => prediction.class === 'book' && prediction.score >= 0.5
    );

    if (filteredPredictions.length !== lastBookCountRef.current) {
      setBookCount(filteredPredictions.length);
      lastBookCountRef.current = filteredPredictions.length;
    }

    drawBoundingBoxes(filteredPredictions);
    requestRef.current = requestAnimationFrame(detectFrame);
  };

  // --- 3. Start Camera (Atualizado para receber o modo da câmera) ---
  const startCamera = async (mode: 'environment' | 'user') => {
    setCameraError(null);
    
    // Para a câmera atual (se houver) antes de iniciar a nova
    if (videoRef.current && videoRef.current.srcObject) {
      const stream = videoRef.current.srcObject as MediaStream;
      stream.getTracks().forEach((track) => track.stop());
    }
    
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ 
        video: { facingMode: mode } // Define traseira ou frontal
      });
      
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        videoRef.current.onloadeddata = () => {
          setIsCameraActive(true);
          
          // Garante que o loop de detecção só seja iniciado uma vez
          if (!isDetectingRef.current) {
            isDetectingRef.current = true;
            detectFrame();
          }
        };
      }
    } catch (error: any) {
      console.error('Erro ao acessar a câmera:', error);
      if (error.name === 'NotAllowedError' || error.name === 'PermissionDeniedError') {
        setCameraError('Permissão da câmera negada. Por favor, permita o acesso nas configurações do navegador.');
      } else if (error.name === 'NotFoundError' || error.name === 'DevicesNotFoundError') {
        setCameraError('Nenhuma câmera foi encontrada no seu dispositivo.');
      } else {
        setCameraError('Ocorreu um erro inesperado ao tentar acessar a câmera.');
      }
    }
  };

  // --- Botão de Trocar Câmera ---
  const toggleCamera = () => {
    // Inverte o estado atual
    const newMode = facingMode === 'environment' ? 'user' : 'environment';
    setFacingMode(newMode);
    startCamera(newMode); // Reinicia a câmera com o novo modo
  };

  // --- 6. JSX Structure ---
  return (
    <div className="container">
      <header className="header">
        <h1>Book Detector AI</h1>
        <div className="tag">Books detected: {bookCount}</div>
      </header>

      {cameraError && (
        <div style={{ color: '#ff4d4d', marginBottom: '1rem', textAlign: 'center', maxWidth: '600px' }}>
          <strong>Atenção:</strong> {cameraError}
        </div>
      )}

      {!isModelLoaded ? (
        <p className="status-text">Loading model...</p>
      ) : !isCameraActive ? (
        <button className="start-btn" onClick={() => startCamera(facingMode)}>
          Start Camera
        </button>
      ) : (
        // Exibe o botão de alternar câmera apenas quando ela já estiver ativa
        <div className="controls">
          <button className="switch-btn" onClick={toggleCamera}>
            Trocar Câmera
          </button>
        </div>
      )}

      <div 
        className="video-container" 
        style={{ display: isCameraActive ? 'block' : 'none' }}
      >
        <video 
          ref={videoRef} 
          autoPlay 
          playsInline 
          muted 
          className="video"
          // Espelha o vídeo se for a câmera frontal para não ficar invertido pro usuário
          style={{ transform: facingMode === 'user' ? 'scaleX(-1)' : 'scaleX(1)' }}
        />
        <canvas 
          ref={canvasRef} 
          className="canvas" 
          style={{ transform: facingMode === 'user' ? 'scaleX(-1)' : 'scaleX(1)' }}
        />
      </div>
    </div>
  );
};

export default App;