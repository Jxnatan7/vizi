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

  // --- 2. References ---
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const modelRef = useRef<cocoSsd.ObjectDetection | null>(null);
  const requestRef = useRef<number>(0);
  const lastBookCountRef = useRef<number>(0);

  // --- 3. Initialization & 7. Lifecycle (Clean up) ---
  useEffect(() => {
    const initApp = async () => {
      try {
        // Explicitly set the WebGL backend for GPU acceleration
        await tf.setBackend('webgl');
        await tf.ready();
        
        // Load the COCO-SSD model
        const loadedModel = await cocoSsd.load();
        modelRef.current = loadedModel;
        setIsModelLoaded(true);
      } catch (error) {
        console.error('Failed to initialize TensorFlow or load the model:', error);
      }
    };

    initApp();

    // Cleanup: Stop animation frames and release the webcam
    return () => {
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

    // Clear the previous frame entirely
    ctx.clearRect(0, 0, canvasRef.current.width, canvasRef.current.height);

    predictions.forEach((prediction) => {
      const [x, y, width, height] = prediction.bbox;
      const scoreText = `Book - ${Math.round(prediction.score * 100)}%`;

      // Draw the bounding box
      ctx.strokeStyle = '#00FF00';
      ctx.lineWidth = 4;
      ctx.strokeRect(x, y, width, height);

      // Setup for text background
      ctx.font = '16px Arial';
      const textWidth = ctx.measureText(scoreText).width;
      const textHeight = 24;

      // Draw text background (just above the bounding box)
      ctx.fillStyle = '#00FF00';
      ctx.fillRect(x, y - textHeight, textWidth + 10, textHeight);

      // Draw the text
      ctx.fillStyle = '#000000';
      ctx.fillText(scoreText, x + 5, y - 6);
    });
  };

  // --- 4. The Detection Loop and Performance (Core Logic) ---
  const detectFrame = async () => {
    const video = videoRef.current;
    const canvas = canvasRef.current;
    const model = modelRef.current;

    // Validate that the elements exist and the video is playing
    if (!video || !canvas || !model || video.readyState < 2) {
      requestRef.current = requestAnimationFrame(detectFrame);
      return;
    }

    // Synchronize canvas dimensions strictly with the actual video resolution
    if (canvas.width !== video.videoWidth || canvas.height !== video.videoHeight) {
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
    }

    // Run the detection model
    const predictions = await model.detect(video);

    // Filter predictions to only 'book' class with high confidence
    const filteredPredictions = predictions.filter(
      (prediction) => prediction.class === 'book' && prediction.score >= 0.5
    );

    // Re-render Control: Only update React state if the count changed to avoid costly re-renders
    if (filteredPredictions.length !== lastBookCountRef.current) {
      setBookCount(filteredPredictions.length);
      lastBookCountRef.current = filteredPredictions.length;
    }

    // Draw visually bypassing React
    drawBoundingBoxes(filteredPredictions);

    // Schedule the next frame recursively
    requestRef.current = requestAnimationFrame(detectFrame);
  };

  // --- 3. Start Camera ---
  const startCamera = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: true });
      
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        // Use the onloadeddata event to safely start the detection loop
        videoRef.current.onloadeddata = () => {
          setIsCameraActive(true);
          detectFrame();
        };
      }
    } catch (error) {
      console.error('Error accessing the webcam:', error);
    }
  };

  // --- 6. JSX Structure ---
  return (
    <div className="container">
      <header className="header">
        <h1>Book Detector AI</h1>
        <div className="tag">Books detected: {bookCount}</div>
      </header>

      {!isModelLoaded ? (
        <p className="status-text">Loading model...</p>
      ) : !isCameraActive ? (
        <button className="start-btn" onClick={startCamera}>
          Start Camera
        </button>
      ) : null}

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
        />
        <canvas 
          ref={canvasRef} 
          className="canvas" 
        />
      </div>
    </div>
  );
};

export default App;