import { NativeModule, requireNativeModule } from 'expo';

import type {
  BenchmarkOptions, ModelInfo, NativeProbe, RawMeasurement,
  CaptureOptions, CaptureResult, OverlayStyle, Session, SessionInfo, SessionOptions,
  TelemetrySample, TransformMode,
} from './ViziVision.types';

type Events = {
  /** ~2 Hz. Nunca por frame — ver contracts/camera-session.md. */
  onTelemetry(sample: TelemetrySample): void;
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
}

export default requireNativeModule<ViziVisionModule>('ViziVision');
