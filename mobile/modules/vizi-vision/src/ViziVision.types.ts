// Contrato da fronteira nativo ↔ JavaScript.
// Espelha specs/001-coreml-proof/contracts/vizi-vision.md.
//
// Regra do princípio II da constituição: nada aqui pode carregar pixels ou
// tensores. Se algum destes tipos crescer além de ~64 KB por chamada, a
// fronteira foi violada.

/** Sinal de vida do módulo nativo. Marco 1, US1. */
export type NativeProbe = {
  module: string;
  os: string;
  processorCount: number;
  physicalMemoryMB: number;
  lowPowerMode: boolean;
};

/** Metadados lidos do próprio modelo. O JavaScript recebe, nunca declara. */
export type ModelInfo = {
  identifier: string;
  inputWidth: number;
  inputHeight: number;
  /** Mapa índice → nome, dos metadados do modelo. */
  classes: Record<string, string>;
  /** Derivado da forma dos protótipos, não fixado em código. */
  maskCoeffCount: number;
  computeUnits: string;
  /** true = o .mlpackage foi compilado agora; custo pago uma vez. */
  compiledAtRuntime: boolean;
  loadMs: number;
};

export type LatencyStats = {
  median: number;
  p95: number;
  min: number;
};

/** Uma instância detectada, já decodificada do lado nativo. */
export type Instance = {
  classIndex: number;
  score: number;
  /** Canto superior esquerdo, em pixels da entrada do modelo. */
  x: number;
  y: number;
  width: number;
  height: number;
};

/** Política da medição. Vive em TypeScript — princípio IV. */
export type BenchmarkOptions = {
  repetitions: number;
  warmupDiscard: number;
  confidenceThreshold: number;
};

/**
 * O que o nativo devolve: latências INDIVIDUAIS, sem agregação.
 *
 * Agregar é decisão de política e fica no TypeScript. Devolver a série crua
 * também é o que permite caracterizar o aquecimento (T029) — com a mediana
 * pronta, seria impossível ver onde a curva estabiliza.
 */
export type RawMeasurement = {
  modelMsAll: number[];
  cycleMsAll: number[];
  thermalState: string;
  executionUnit: string;
  instances: Instance[];
};

/** Resultado agregado, montado em TypeScript a partir do RawMeasurement. */
export type Measurement = {
  repetitions: number;
  discarded: number;
  /** Custo da primeira execução, isolado — FR-004. */
  firstRunMs: number;
  /** Execução do modelo. É a isto que o portão de 30 ms se vincula. */
  modelMs: LatencyStats;
  /** Ciclo completo: preparo da entrada, execução e decodificação — FR-014. */
  cycleMs: LatencyStats;
  thermalState: string;
  executionUnit: string;
  instances: Instance[];
  /** Série crua das primeiras execuções, para inspecionar o aquecimento. */
  warmupCurve: number[];
};
