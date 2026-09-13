import React, { useState, useCallback } from 'react';
import { useTensorFlowModel } from './hooks/useTensorFlowModel';
import { useWebcam } from './hooks/useWebcam';
import { Header } from './components/Header';
import { DetectionView } from './components/DetectionView';
import './App.css';

const App: React.FC = () => {
  const [bookCount, setBookCount] = useState(0);
  
  // Custom Hooks
  const { model, isModelLoaded, error: modelError } = useTensorFlowModel();
  const { stream, isCameraActive, cameraError, facingMode, startCamera, toggleCamera } = useWebcam();

  // useCallback evita que a referência da função mude, prevenindo re-renders no DetectionView
  const handleBookCountChange = useCallback((count: number) => {
    setBookCount(count);
  }, []);

  return (
    <div className="container">
      <Header bookCount={bookCount} />

      {/* Tratamento de Erros */}
      {(cameraError || modelError) && (
        <div style={{ color: '#ff4d4d', marginBottom: '1rem', textAlign: 'center', maxWidth: '600px' }}>
          <strong>Atenção:</strong> {cameraError || modelError}
        </div>
      )}

      {/* Controles da UI */}
      {!isModelLoaded ? (
        <p className="status-text">Loading model...</p>
      ) : !isCameraActive ? (
        <button className="start-btn" onClick={() => startCamera('environment')}>
          Start Camera
        </button>
      ) : (
        <div className="controls">
          <button className="switch-btn" onClick={toggleCamera}>
            Trocar Câmera
          </button>
        </div>
      )}

      {/* View de Detecção Isolada */}
      {isCameraActive && model && stream && (
        <DetectionView 
          model={model} 
          stream={stream} 
          facingMode={facingMode}
          onBookCountChange={handleBookCountChange} 
        />
      )}
    </div>
  );
};

export default App;