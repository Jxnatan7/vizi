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
  /** Supressão não-máxima. 0,7 é o padrão do Ultralytics, que gerou a referência. */
  iouThreshold: number;
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

// ---------------------------------------------------------------------------
// Marco 2 — sessão de câmera
// ---------------------------------------------------------------------------

/** Como o frame da câmera vira o quadrado que o modelo espera. */
export type TransformMode = 'stretch' | 'centerCrop' | 'letterbox';

export type SessionOptions = {
  /** Cadência do evento de telemetria. Nunca menor que 100 ms. */
  sampleIntervalMs: number;
  transform: TransformMode;
  confidenceThreshold: number;
  iouThreshold: number;
};

export type SessionInfo = {
  captureWidth: number;
  captureHeight: number;
  maxFrameRate: number;
  thermalAtStart: string;
  batteryAtStart: number;
};

/** Uma leitura periódica. Taxas são da janela, não acumuladas. */
export type TelemetrySample = {
  /** Milissegundos desde o início da sessão. */
  t: number;
  fpsCaptured: number;
  fpsInferred: number;
  /** Medianas da janela, não acumuladas. */
  transformMs: number;
  inferMs: number;
  decodeMs: number;
  /** Do carimbo do próprio frame até o resultado pronto (FR-009). */
  e2eMs: number;
  instanceCount: number;
  transform: TransformMode;
  /** Diagnóstico do overlay: se a view está montada e o que ela pintou. */
  overlayAttached: boolean;
  overlayDrawnCount: number;
  drawMs: number;
  /** 0 ou 1. Acima disso, o descarte falhou. */
  queueDepth: number;
  dropped: number;
  thermalState: string;
  /** 0 a 1, ou -1 quando indisponível. */
  batteryLevel: number;
  lowPowerMode: boolean;
};

export type ThermalTransition = {
  t: number;
  from: string;
  to: string;
};

/** O que `stopSession` devolve. A única travessia grande, e acontece uma vez. */
export type Session = {
  startedAt: number;
  durationMs: number;
  received: number;
  processed: number;
  dropped: number;
  transform: TransformMode;
  /** Sem as condições iniciais, uma sessão não é comparável com outra. */
  thermalAtStart: string;
  batteryAtStart: number;
  thermalAtEnd: string;
  batteryAtEnd: number;
  samples: TelemetrySample[];
  thermalTransitions: ThermalTransition[];
  /** Milissegundos de cada captura, para correlacionar quedas de taxa. */
  captureMarks: number[];
  /** true = amostras antigas foram descartadas pelo buffer circular. */
  truncated: boolean;
};

// ---------------------------------------------------------------------------
// Marco 3 — overlay
// ---------------------------------------------------------------------------

/** O nativo desenha; isto decide como. Ver contracts/overlay-style.md. */
export type OverlayStyle = {
  showBoxes: boolean;
  showMasks: boolean;
  /** Pixels do espaço do modelo, não da tela. */
  boxWidth: number;
  maskOpacity: number;
  /** O que *aparece*, separado do limiar que decide o que *existe*. */
  minConfidence: number;
  /** Cores "#RRGGBB". A atribuição por objeto é do nativo. */
  palette: string[];
};

// ---------------------------------------------------------------------------
// Marco 4 — captura e resultado
// ---------------------------------------------------------------------------

export type CaptureOptions = {
  cropMargin: number;
  minInstancesForGeometry: number;
  minGeometryConfidence: number;
  transitionMs: number;
};

export type CaptureResult = {
  count: number;
  straightened: boolean;
  /** Texto legível quando a correção foi recusada — FR-011. */
  declineReason: string;
  geometryConfidence: number;
  /** Posições das divisões, normalizadas de 0 a 1. */
  dividers: number[];
  /**
   * **Identificador, não pixels.** A foto em resolução máxima fica no nativo;
   * atravessar a fronteira com ela violaria o princípio II num caso em que
   * seria tentador — é só uma imagem, e é só uma vez.
   */
  imageId: string;
  elapsedMs: number;
  photoWidth: number;
  photoHeight: number;
};
