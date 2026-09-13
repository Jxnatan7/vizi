import { useState, useRef, useCallback, useEffect } from 'react';

export type FacingMode = 'environment' | 'user';

export const useWebcam = () => {
  const [stream, setStream] = useState<MediaStream | null>(null);
  const [isCameraActive, setIsCameraActive] = useState(false);
  const [cameraError, setCameraError] = useState<string | null>(null);
  const [facingMode, setFacingMode] = useState<FacingMode>('environment');
  
  const streamRef = useRef<MediaStream | null>(null);

  const stopCamera = useCallback(() => {
    if (streamRef.current) {
      streamRef.current.getTracks().forEach(track => track.stop());
      streamRef.current = null;
      setStream(null);
      setIsCameraActive(false);
    }
  }, []);

  const startCamera = useCallback(async (mode: FacingMode) => {
    setCameraError(null);
    stopCamera(); // Limpa a anterior antes de pedir nova

    try {
      const newStream = await navigator.mediaDevices.getUserMedia({ 
        video: { facingMode: mode } 
      });
      streamRef.current = newStream;
      setFacingMode(mode);
      setStream(newStream);
      setIsCameraActive(true);
    } catch (error: any) {
      console.error('Erro de câmera:', error);
      if (error.name === 'NotAllowedError' || error.name === 'PermissionDeniedError') {
        setCameraError('Permissão negada. Permita o acesso à câmera nas configurações.');
      } else if (error.name === 'NotFoundError' || error.name === 'DevicesNotFoundError') {
        setCameraError('Nenhuma câmera encontrada.');
      } else {
        setCameraError('Erro inesperado ao acessar a câmera.');
      }
    }
  }, [stopCamera]);

  const toggleCamera = useCallback(() => {
    const newMode = facingMode === 'environment' ? 'user' : 'environment';
    startCamera(newMode);
  }, [facingMode, startCamera]);

  // Cleanup no unmount
  useEffect(() => {
    return stopCamera;
  }, [stopCamera]);

  return { stream, isCameraActive, cameraError, facingMode, startCamera, toggleCamera };
};