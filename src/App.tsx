import React, { useState, useCallback } from 'react';
import { useTensorFlowModel } from './hooks/useTensorFlowModel';
import { useWebcam } from './hooks/useWebcam';
import { Header } from './components/Header';
import { DetectionView } from './components/DetectionView';
import './App.css';

const App: React.FC = () => {
  const [bookCount, setBookCount] = useState(0);
  
  const { model, isModelLoaded, error: modelError } = useTensorFlowModel();
  const { stream, isCameraActive, cameraError, facingMode, startCamera, toggleCamera } = useWebcam();

  const handleBookCountChange = useCallback((count: number) => {
    setBookCount(count);
  }, []);

  return (
    <div className="app-container">
      {/* Camada de Fundo: Câmera (Sempre presente, tela preta se inativa) */}
      <div className="background-layer">
        {isCameraActive && model && stream ? (
          <DetectionView 
            model={model} 
            stream={stream} 
            facingMode={facingMode}
            onBookCountChange={handleBookCountChange} 
          />
        ) : (
          <div className="camera-placeholder">
            {!isModelLoaded ? (
              <div className="loader">Carregando IA...</div>
            ) : (
              <div className="ready-text">Pronto para iniciar</div>
            )}
          </div>
        )}
      </div>

      {/* Camada Flutuante: Interface do Usuário */}
      <div className="ui-layer">
        <Header bookCount={bookCount} />

        {/* Centro da tela: Erros, se houver */}
        <div className="center-content">
          {(cameraError || modelError) && (
            <div className="error-card">
              <strong>Atenção:</strong> {cameraError || modelError}
            </div>
          )}
        </div>

        {/* Rodapé: Controles flutuantes */}
        <div className="bottom-controls">
          {isModelLoaded && !isCameraActive && (
            <button className="fab-btn primary" onClick={() => startCamera('environment')}>
              Ativar Câmera
            </button>
          )}

          {isCameraActive && (
            <button className="fab-btn secondary" onClick={toggleCamera}>
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M21 2v6h-6"></path>
                <path d="M3 12a9 9 0 0 1 15-6.7L21 8"></path>
                <path d="M3 22v-6h6"></path>
                <path d="M21 12a9 9 0 0 1-15 6.7L3 16"></path>
              </svg>
              Inverter Lente
            </button>
          )}
        </div>
      </div>
    </div>
  );
};

export default App;