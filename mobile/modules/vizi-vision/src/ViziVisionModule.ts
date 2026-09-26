import { NativeModule, requireNativeModule } from 'expo';

import type {
  BandMode, BandState, BenchmarkOptions, ModelInfo, NativeProbe, RawMeasurement,
  CaptureOptions, CaptureResult, OverlayStyle, SavedImage, SaveResultOptions,
  Session, SessionInfo, SessionOptions, TelemetrySample, TransformMode,
} from './ViziVision.types';

type Events = {
  /** ~2 Hz. Nunca por frame — ver contracts/camera-session.md. */
  onTelemetry(sample: TelemetrySample): void;
  /**
   * Só em mudança discreta: fim de gesto, troca de modo, volta ao centro,
   * começo de sessão. Nunca durante o arrasto — spec 005, princípio III.
   */
  onBandChange(state: BandState): void;
};

declare class ViziVisionModule extends NativeModule<Events> {
  probe(): NativeProbe;

  loadModel(): Promise<ModelInfo>;
  runBenchmark(options: BenchmarkOptions): Promise<RawMeasurement>;
  unloadModel(): Promise<void>;

  hasCameraPermission(): Promise<boolean>;
  requestCameraPermission(): Promise<boolean>;
  startSession(options: SessionOptions): Promise<SessionInfo>;
  stopSession(): Promise<Session>;
  setTransform(transform: TransformMode): Promise<void>;
  setOverlayStyle(style: OverlayStyle): Promise<void>;

  capture(options: CaptureOptions): Promise<CaptureResult>;
  dismissResult(): Promise<void>;
  /** Grava o resultado que está na tela. O índice é do TypeScript. */
  saveResult(options: SaveResultOptions): Promise<SavedImage>;

  /** A cápsula. Animado e com retorno tátil no nativo; `onBandChange` no fim. */
  setBandMode(mode: BandMode): Promise<void>;
}

export default requireNativeModule<ViziVisionModule>('ViziVision');
