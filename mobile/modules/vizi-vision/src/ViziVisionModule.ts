import { NativeModule, requireNativeModule } from 'expo';

import type {
  BenchmarkOptions, ModelInfo, NativeProbe, RawMeasurement,
  SessionInfo, SessionOptions, SessionSummary, TelemetrySample,
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
  stopSession(): Promise<SessionSummary>;
}

export default requireNativeModule<ViziVisionModule>('ViziVision');
