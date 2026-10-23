import { NativeModule, requireNativeModule } from 'expo';

import type {
  BandMode, BandState, BenchmarkOptions, ModelInfo, NativeProbe, RawMeasurement,
  CaptureOptions, CaptureResult, OverlayStyle, SavedImage, SaveResultOptions,
  Session, SessionInfo, SessionOptions, TelemetrySample, TransformMode,
  CollectionOptions, CollectionState, CollectionSummary, ExportOutcome, MarkReceipt,
  CollectionTags,
} from './ViziVision.types';

type Events = {
  /** ~2 Hz. Nunca por frame — ver contracts/camera-session.md. */
  onTelemetry(sample: TelemetrySample): void;
  /**
   * Só em mudança discreta: fim de gesto, troca de modo, volta ao centro,
   * começo de sessão. Nunca durante o arrasto — spec 005, princípio III.
   */
  onBandChange(state: BandState): void;
  /**
   * Só em mudança discreta da coleta: abriu, fechou, item gravado, resposta
   * gravada, espaço cruzando o limite. Nunca por quadro — spec 007.
   */
  onCollectionChange(state: CollectionState): void;
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

  /**
   * `tags` é a escolha da câmera no toque (spec 008), gravada no item da coleta
   * como chegou. Sempre enviado — `null` sem escolha ou sem coleta.
   */
  capture(options: CaptureOptions, tags: CollectionTags | null): Promise<CaptureResult>;
  dismissResult(): Promise<void>;
  /** Grava o resultado que está na tela. O índice é do TypeScript. */
  saveResult(options: SaveResultOptions): Promise<SavedImage>;

  /** A cápsula. Animado e com retorno tátil no nativo; `onBandChange` no fim. */
  setBandMode(mode: BandMode): Promise<void>;

  // Spec 007 — o contrato está em specs/007-modo-coleta/contracts/collection.md.
  // As recusas chegam com o código no começo da mensagem ("busy: …").

  /** Abre uma sessão de coleta. Com uma aberta, devolve o estado dela. */
  startCollection(options: CollectionOptions): Promise<CollectionState>;
  /** Fecha a sessão: o nativo espera os itens pendentes e grava o fim. */
  stopCollection(): Promise<CollectionState>;
  /** Síncrona: a tela monta sabendo se a coleta está aberta. */
  getCollectionState(): CollectionState;
  /** Grava o próximo quadro processado e congela a tela nele, com a escolha do toque. */
  markFrame(tags: CollectionTags | null): Promise<MarkReceipt>;
  /** A contagem real do item que espera resposta; `null` = pulou. */
  answerItem(itemId: string, count: number | null): Promise<void>;
  /** Solta o quadro parado de uma marca e volta ao ao vivo. */
  resumeLive(): Promise<void>;
  listCollections(): Promise<CollectionSummary[]>;
  renameCollection(id: string, name: string): Promise<void>;
  deleteCollection(id: string): Promise<void>;
  /** Gera o zip e abre o menu de compartilhar; resolve quando ele fecha. */
  exportCollection(id: string): Promise<ExportOutcome>;
}

export default requireNativeModule<ViziVisionModule>('ViziVision');
