import { ViziVision, type BenchmarkOptions, type Measurement } from '../../modules/vizi-vision';

import { summarize } from './stats';

/**
 * A política da medição vive aqui, não no Swift — princípio IV da constituição.
 *
 * `warmupDiscard` começa em 5 por palpite. O número definitivo sai da T029:
 * olhar `warmupCurve` e ver onde a série estabiliza.
 */
export const DEFAULT_OPTIONS: BenchmarkOptions = {
  repetitions: 100,
  warmupDiscard: 5,
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
