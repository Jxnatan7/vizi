import React, { useState, useCallback } from 'react';
import { useYoloModel } from './hooks/useYoloModel';
import { useWebcam } from './hooks/useWebcam';
import { Header } from './components/Header';
import { DetectionView } from './components/DetectionView';
import { OverlayControls } from './components/OverlayControls';
import { DiagnosticsPanel, type Diagnostics } from './components/DiagnosticsPanel';
import { debugEnabled, deviceOverride } from './lib/debugFlags';
import './App.css';

const App: React.FC = () => {
  const [bookCount, setBookCount] = useState(0);

  // Exibição do overlay. Não persiste entre sessões: volta ao padrão a cada
  // abertura do app.
  const [showBoxes, setShowBoxes] = useState(true);
  const [showMasks, setShowMasks] = useState(true);
  const [maskOpacity, setMaskOpacity] = useState(1);

  // Padrão do Ultralytics. Permissivo para um modelo de classe única, mas é o
  // valor que a validação em Python usa — calibre com ?debug=1 e fixe aqui.
  const [confidence, setConfidence] = useState(0.25);

  const [diagnostics, setDiagnostics] = useState<Diagnostics | null>(null);

  const { model, isModelLoaded, device, task, names, error: modelError } = useYoloModel(deviceOverride);
  const { stream, isCameraActive, cameraError, facingMode, startCamera, toggleCamera } = useWebcam();

  const handleBookCountChange = useCallback((count: number) => {
    setBookCount(count);
  }, []);

  // Sem ?debug=1 a prop fica indefinida e o loop nem monta o objeto.
  const handleDiagnostics = useCallback((next: Diagnostics) => {
    setDiagnostics(next);
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
            showBoxes={showBoxes}
            showMasks={showMasks}
            maskOpacity={maskOpacity}
            confidence={confidence}
            onBookCountChange={handleBookCountChange}
            onDiagnostics={debugEnabled ? handleDiagnostics : undefined}
          />
        ) : (
          <div className="camera-placeholder">
            {!isModelLoaded ? (
              <div className="loader">Carregando IA...</div>
            ) : (
              <div className="ready-text">
                Pronto para iniciar{device ? ` (${device})` : ''}
              </div>
            )}
          </div>
        )}
      </div>

      {/* Camada Flutuante: Interface do Usuário */}
      <div className="ui-layer">
        <Header bookCount={bookCount} />

        {debugEnabled && (
          <DiagnosticsPanel device={device} task={task} names={names} diagnostics={diagnostics} />
        )}

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
          {isCameraActive && (
            <OverlayControls
              showBoxes={showBoxes}
              showMasks={showMasks}
              maskOpacity={maskOpacity}
              canSegment={task === 'segment'}
              confidence={confidence}
              onConfidenceChange={debugEnabled ? setConfidence : undefined}
              onShowBoxesChange={setShowBoxes}
              onShowMasksChange={setShowMasks}
              onMaskOpacityChange={setMaskOpacity}
            />
          )}

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