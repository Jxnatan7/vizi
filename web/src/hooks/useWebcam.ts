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
      // O modelo letterboxa para 640x640 de qualquer jeito, então captura maior
      // não traz precisão — só custa. E custa duas vezes: a leitura de pixels
      // para RGBA e a máscara que o engine devolve no tamanho do frame
      // (width*height*4 bytes por inferência). Sem constraint, um iPhone recente
      // entrega 1920x1080 e a máscara passa de 8 MB por frame.
      //
      // Sem constraint de resolução, de propósito. Duas tentativas de limitar
      // saíram pior que o padrão, as duas porque o Safari do iOS resolve
      // width+height cortando em quadrado em vez de preservar o aspecto:
      //
      //   { ideal: 640, max: 1280 } nos dois eixos -> 640x640
      //   { max: 640 }              nos dois eixos -> 640x640
      //   (nenhuma)                                -> 480x640  <- o melhor
      //
      // 640x640 são 409600 px contra 307200 px do nativo: 33% mais pixels para
      // ler e para o engine devolver como máscara (width*height*4 por
      // inferência). O padrão do aparelho já é a melhor opção medida.
      //
      // Se algum dia um aparelho entregar algo grande demais, limitar só UM
      // eixo (`height: { max: 640 }`) deve evitar o corte quadrado — não foi
      // testado, e vale medir antes de confiar.
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