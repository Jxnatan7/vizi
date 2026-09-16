import { ViziVision, type BenchmarkOptions, type Measurement } from '../../modules/vizi-vision';

import { summarize } from './stats';

/**
 * A política da medição vive aqui, não no Swift — princípio IV da constituição.
 *
 * `warmupDiscard: 25` veio da medição de 16/09/2026 (T029), não de palpite.
 * A curva das 20 primeiras execuções cai de 33,2 ms para ~5,0 ms e continua
 * caindo: a mediana das 95 amostras válidas ficou em 3,2 ms, abaixo de
 * qualquer valor das 20 primeiras. O aquecimento dura mais de 20 iterações.
 */
export const DEFAULT_OPTIONS: BenchmarkOptions = {
  repetitions: 100,
  warmupDiscard: 25,
  confidenceThreshold: 0.25,
};

export async function runBenchmark(
  options: BenchmarkOptions = DEFAULT_OPTIONS,
): Promise<Measurement> {
  const raw = await ViziVision.runBenchmark(options);

  const discard = Math.min(options.warmupDiscard, raw.modelMsAll.length - 1);
  const model = raw.modelMsAll.slice(discard);
  const cycle = raw.cycleMsAll.slice(discard);

  return {
    repetitions: raw.modelMsAll.length,
    discarded: discard,
    firstRunMs: raw.modelMsAll[0] ?? 0,
    modelMs: summarize(model),
    cycleMs: summarize(cycle),
    thermalState: raw.thermalState,
    executionUnit: raw.executionUnit,
    instances: raw.instances,
    warmupCurve: raw.modelMsAll.slice(0, 20),
  };
}
