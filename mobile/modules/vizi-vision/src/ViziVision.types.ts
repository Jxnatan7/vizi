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
  /** A faixa de interesse. A sessão começa por ela — spec 005, FR-002. */
  band: BandPolicy;
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
  /** Divisões entre livros sobre o resultado endireitado (FR-008). */
  showDividers: boolean;
  /** "#RRGGBB". */
  dividerColor: string;
  /** Pontos de tela: o resultado não está no espaço do modelo. */
  dividerWidth: number;
  /** Faixa de interesse: o escurecimento fora dela, de 0 a 1. */
  bandDimOpacity: number;
  /** "#RRGGBB". Bordas, alças e o texto da contagem. */
  bandEdgeColor: string;
  /** As medidas da faixa são em pontos de tela. */
  bandEdgeWidth: number;
  bandHandleLength: number;
  bandHandleThickness: number;
  bandCountFontSize: number;
};

// ---------------------------------------------------------------------------
// Marco 4 — captura e resultado
// ---------------------------------------------------------------------------

export type CaptureOptions = {
  cropMargin: number;
  minInstancesForGeometry: number;
  minGeometryConfidence: number;
  /** Aproximação que começa no toque, antes de a foto existir (FR-009). */
  approachMs: number;
  /** Endireitamento, depois que o resultado existe — e a volta. */
  transitionMs: number;
  /** Mostra o que o algoritmo inferiu em vez do resultado. */
  diagnostics: boolean;
  /** O que decide em pé, fileira e confiança da geometria. */
  geometry: GeometryTuning;
  /** Divisões mais perto que isto das bordas do recorte são descartadas. */
  dividerEdgeMargin: number;
  /**
   * A releitura do recorte (spec 006): o modelo lê por último o quadrado que
   * está na tela, e o que ele encontra é o resultado. Desligada, o resultado é
   * a leitura da foto, como na 005.
   */
  reread: boolean;
  /**
   * Fração da área da caixa que precisa estar dentro do recorte sem a margem
   * para contar (FR-004). A margem mostra pedaços do que está em volta.
   */
  rereadMembership: number;
};

/** De qual leitura veio a contagem (spec 006, FR-009). */
export type CountSource = 'reread' | 'photo';

/**
 * Política da estimativa da estante. Estava fixa no Swift até a T037 deste
 * marco; são os números que a grade e a releitura vão querer ajustar sem
 * rebuild.
 */
export type GeometryTuning = {
  /** Quanto uma lombada pode se afastar da vertical e ainda contar como em pé. */
  standingToleranceDegrees: number;
  /** Vão que separa duas fileiras, como fração da altura mediana dos livros. */
  rowGapFactor: number;
  /** Piso desse vão, como fração do lado da imagem. */
  minRowGap: number;
  /** Fileiras menores contam livros mas não entram na estimativa. */
  minBooksPerRow: number;
  /** Livros em pé que dão nota máxima ao sinal de contagem. */
  fullConfidenceCount: number;
  /** Resíduo médio das bases que zera o sinal da reta, como fração do lado. */
  maxBaseResidual: number;
  /** Dispersão angular das lombadas, em radianos, que zera o sinal. */
  maxAngleSpread: number;
  /** Diferença de inclinação entre fileiras que zera o sinal. */
  maxRowSlopeSpread: number;
  weightsWithGravity: ConfidenceWeights;
  weightsWithoutGravity: ConfidenceWeights;
};

/** Peso de cada sinal na confiança da geometria (R15). */
export type ConfidenceWeights = {
  count: number;
  line: number;
  spread: number;
  rows: number;
};

export type CaptureResult = {
  /**
   * Com `countSource: 'reread'`, as caixas da releitura que passaram pela
   * regra das bordas — as mesmas que aparecem na tela.
   */
  count: number;
  /**
   * `'reread'` quando a releitura produziu o resultado; `'photo'` quando não
   * havia recorte na tela, a releitura estava desligada ou falhou. Contagem,
   * fileiras e deitados vêm dela; a geometria vem sempre da foto.
   */
  countSource: CountSource;
  /** Montar o quadrado, inferir, filtrar e agrupar. Zero sem releitura. */
  rereadMs: number;
  straightened: boolean;
  /** Texto legível quando a correção foi recusada — FR-011. */
  declineReason: string;
  /** A confiança da geometria (R15) — a que `minGeometryConfidence` compara. */
  geometryConfidence: number;
  /** Nitidez do cruzamento entre a reta das bases e o horizonte. Diagnóstico. */
  azimuthConfidence: number;
  /**
   * Uma entrada por fileira. Prateleiras de uma estante são coplanares, então
   * todas vêm da MESMA homografia — e duas ou mais retas de base dão o ponto
   * de fuga por medição, em vez de suposição.
   */
  shelves: {
    count: number;
    /** Divisões entre livros, normalizadas de 0 a 1 na largura. */
    dividers: number[];
    /** Banda vertical da fileira, normalizada de 0 a 1. */
    top: number;
    bottom: number;
  }[];
  /** Fileiras detectadas, inclusive as curtas demais para entrar na geometria. */
  shelfCount: number;
  /** Objetos que não estão em pé: contados e marcados, fora da geometria. */
  lyingCount: number;
  /** `true` quando a vertical veio da gravidade, não das lombadas. */
  usedGravity: boolean;
  /**
   * A varredura de azimute inteira, normalizada. Pico nítido significa
   * estrutura horizontal dominante; platô significa escolha arbitrária.
   */
  azimuthScores: number[];
  /**
   * **Identificador, não pixels.** A foto em resolução máxima fica no nativo;
   * atravessar a fronteira com ela violaria o princípio II num caso em que
   * seria tentador — é só uma imagem, e é só uma vez.
   */
  imageId: string;
  /** Só a foto: troca de formato, captura e restauração. */
  elapsedMs: number;
  /**
   * Do toque ao resultado na tela, antes da releitura. O endireitamento começa
   * aqui, então o resultado final aparece em `readyMs + transitionMs` — é isso
   * que o SC-001 limita a 1,5 s. A releitura corre por baixo da transição.
   */
  readyMs: number;
  photoWidth: number;
  photoHeight: number;
  /**
   * Detecções da foto descartadas pela faixa. Com `count` zero e isto maior
   * que zero, não há livros **na faixa** — não é a cena que está vazia.
   */
  outsideBandCount: number;
  /**
   * O item gravado para esta captura (spec 007), ou `null` sem coleta aberta
   * ou sem gravação. É a chave do `answerItem`.
   */
  collectionItemId: string | null;
  /**
   * `'space'` quando a coleta estava aberta e a captura não foi gravada por
   * falta de espaço; `null` nos outros casos. A captura em si aconteceu igual.
   */
  collectionSkipped: 'space' | null;
};

// ---------------------------------------------------------------------------
// Spec 005 — faixa de interesse
// ---------------------------------------------------------------------------

export type BandMode = 'off' | 'horizontal' | 'vertical';

/** O estado da faixa. O nativo é o dono; o JavaScript espelha. */
export type BandState = {
  mode: BandMode;
  /** No eixo em que a faixa anda, de 0 a 1. */
  center: number;
  /** Fração da imagem nesse eixo, de 0 a 1. */
  thickness: number;
};

/**
 * Comportamento da faixa. Vive em TypeScript — princípio IV. Os valores
 * iniciais e o que cada um decide estão no data-model da 005.
 */
export type BandPolicy = {
  defaultThickness: number;
  minThickness: number;
  membership: number;
  flipHysteresisDegrees: number;
  offMargin: number;
  rubberBand: number;
  startSlopPoints: number;
  edgeGrabPoints: number;
  countWindowMs: number;
  springResponse: number;
  springDamping: number;
  haptics: boolean;
};

/** Política da gravação no histórico. */
export type SaveResultOptions = {
  /** Qualidade do JPEG, de 0 a 1. */
  quality: number;
};

/** O que o nativo devolve ao gravar: onde ficou, nunca o que tem dentro. */
export type SavedImage = {
  /** O mesmo `imageId` da captura. */
  id: string;
  /** Relativo à pasta de documentos — o absoluto muda a cada reinstalação. */
  file: string;
  width: number;
  height: number;
  bytes: number;
};

/** Uma captura guardada (US4). Data e contagem bastam agora — ver a spec. */
export type HistoryEntry = {
  id: string;
  /** Relativo à pasta de documentos. */
  file: string;
  count: number;
  /** Ausente nas entradas de antes da 006, que eram da foto. */
  countSource?: CountSource;
  straightened: boolean;
  /** Milissegundos desde a época. */
  capturedAt: number;
  /** Para exibir na proporção certa sem abrir a imagem. */
  width: number;
  height: number;
};

// ---------------------------------------------------------------------------
// Spec 007 — modo coleta
// ---------------------------------------------------------------------------

/** Política da coleta (princípio IV) e as políticas em vigor, para o registro. */
export type CollectionOptions = {
  /**
   * Até que confiança as detecções são gravadas. A gravação usa o menor entre
   * este e o limiar da sessão: nunca perde uma detecção que o app contou.
   */
  minScore: number;
  /** Abaixo disto de espaço livre, marcar é recusado e a captura não é gravada. */
  minFreeBytes: number;
  /** Qualidade de todas as imagens da coleta, de 0 a 1. */
  jpegQuality: number;
  /**
   * As políticas em vigor — sessão, captura, faixa, aparência e coleta —, como
   * estão. O nativo grava sem interpretar.
   */
  policies: Record<string, unknown>;
  /** O que a sessão é (spec 008). Vai para o topo do `session.json` como está. */
  session: CollectionSessionInfo;
};

// ---------------------------------------------------------------------------
// Spec 008 — coleta para treino e prova
// ---------------------------------------------------------------------------

/** Treino — fotos para o Roboflow — ou prova, que nunca entra no treino. */
export type CollectionPurpose = 'training' | 'exam';

export type CollectionLight = 'day' | 'night';

export type ShelfDistance = 'near' | 'mid' | 'far';

export type ShelfAngle = 'left' | 'front' | 'right';

/** Uma prateleira como estava no instante: o número do inventário muda com o tempo. */
export type ShelfSnapshot = { id: string; name: string; count: number };

/**
 * O que a sessão é. No treino, a luz escolhida ao ligar; na prova, nenhuma.
 * As prateleiras cadastradas ao abrir vão junto: é contra elas que o relatório
 * da prova diz quais ficaram sem captura.
 */
export type CollectionSessionInfo =
  | { purpose: 'training'; light: CollectionLight; shelves: ShelfSnapshot[] }
  | { purpose: 'exam'; light: null; shelves: ShelfSnapshot[] };

/**
 * A escolha na câmera no instante do toque. Viaja como argumento da captura e
 * da marca, e o nativo a grava em `item.json` como `tags`, sem interpretar.
 */
export type CollectionTags = {
  shelf: ShelfSnapshot | null;
  /** Foto sem livros: sem prateleira, sem distância e sem ângulo. */
  background: boolean;
  /** Só no treino, com prateleira. */
  distance: ShelfDistance | null;
  angle: ShelfAngle | null;
};

/** O que o nativo diz da coleta. Espelhado pelo `onCollectionChange`. */
export type CollectionState = {
  open: boolean;
  /** Ausentes com a coleta fechada. */
  id?: string;
  startedAt?: number;
  /** O tipo da sessão aberta; `null` numa aberta antes da spec 008. */
  purpose?: CollectionPurpose | null;
  light?: CollectionLight | null;
  marks: number;
  captures: number;
  answered: number;
  bytes: number;
  /** Abaixo de `minFreeBytes` na última conferência. */
  lowSpace: boolean;
  /** O último item que não conseguiu ser gravado, e por quê. */
  lastError?: string;
};

/** O que `markFrame` devolve, com o quadro já parado na tela. */
export type MarkReceipt = {
  itemId: string;
  /** A mediana da faixa no toque; null com a faixa desligada. */
  displayedCount: number | null;
  /** As detecções do quadro que existem e estão na faixa. */
  frameCount: number;
};

/** Uma sessão de coleta, para a lista. */
export type CollectionSummary = {
  id: string;
  name: string | null;
  startedAt: number;
  endedAt: number | null;
  /** A aberta aparece na lista, sem exportar. */
  open: boolean;
  endReason: 'stopped' | 'background' | 'recovered' | null;
  /** `null` nas sessões gravadas antes da spec 008. */
  purpose: CollectionPurpose | null;
  light: CollectionLight | null;
  marks: number;
  captures: number;
  answered: number;
  bytes: number;
  exportedAt: number | null;
};

/** O que `exportCollection` devolve quando o menu de compartilhar fecha. */
export type ExportOutcome = {
  /** Relativo à pasta de documentos — o absoluto muda a cada reinstalação. */
  file: string;
  bytes: number;
  /** false quando a pessoa fechou o menu sem compartilhar. O zip fica. */
  shared: boolean;
};
