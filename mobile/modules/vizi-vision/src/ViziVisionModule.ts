import { NativeModule, requireNativeModule } from 'expo';

import type { BenchmarkOptions, ModelInfo, NativeProbe, RawMeasurement } from './ViziVision.types';

declare class ViziVisionModule extends NativeModule<{}> {
  /** Prova que o código nativo foi compilado e instalado. US1. */
  probe(): NativeProbe;

  /** Carrega e, se necessário, compila o modelo. Caro na primeira vez. */
  loadModel(): Promise<ModelInfo>;

  /** Executa a série sobre a imagem embarcada. Devolve latências individuais. */
  runBenchmark(options: BenchmarkOptions): Promise<RawMeasurement>;

  unloadModel(): Promise<void>;
}

export default requireNativeModule<ViziVisionModule>('ViziVision');
