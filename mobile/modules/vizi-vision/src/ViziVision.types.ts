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
  /** Como o modelo declara, em pixels. */
  inputWidth: number;
  inputHeight: number;
  /** Mapa índice → nome, dos metadados do modelo. */
  classes: Record<number, string>;
  /** Unidades autorizadas pelo sistema, ou 'unavailable'. */
  computeUnits: string;
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
  /** Coordenadas no espaço da imagem de entrada. */
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

/** O único objeto de resultado que atravessa a fronteira. */
export type Measurement = {
  repetitions: number;
  discarded: number;
  /** Custo da primeira execução, isolado — FR-004. */
  firstRunMs: number;
  /** Execução do modelo. É a isto que o portão de 30 ms se vincula. */
  modelMs: LatencyStats;
  /** Ciclo completo: preparação, execução e decodificação — FR-014. */
  cycleMs: LatencyStats;
  /** FR-005. */
  thermalState: string;
  /** Onde o modelo rodou, ou 'unavailable' com o motivo — FR-006, FR-015. */
  executionUnit: string;
  /** FR-007. Dezenas de itens; é o que mantém o objeto pequeno. */
  instances: Instance[];
};
