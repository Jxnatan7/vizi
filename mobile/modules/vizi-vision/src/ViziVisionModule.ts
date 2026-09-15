import { NativeModule, requireNativeModule } from 'expo';

import type { NativeProbe } from './ViziVision.types';

declare class ViziVisionModule extends NativeModule<{}> {
  /** Marco 1, US1: prova que o código nativo foi compilado e instalado. */
  probe(): NativeProbe;

  // US2 (T020–T025) acrescenta aqui, conforme contracts/vizi-vision.md:
  //   loadModel(assetName: string): Promise<ModelInfo>
  //   runBenchmark(options: BenchmarkOptions): Promise<Measurement>
  //   unloadModel(): Promise<void>
  //
  // Declarados só quando existirem do lado Swift: uma assinatura em TypeScript
  // sem implementação nativa compila e falha em tempo de execução.
}

export default requireNativeModule<ViziVisionModule>('ViziVision');
