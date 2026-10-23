import type {
  CaptureOptions, CollectionLight, CollectionOptions, ShelfAngle, ShelfDistance,
} from '../../modules/vizi-vision';

/**
 * Política da coleta (spec 007). Vive aqui, não no Swift — princípio IV.
 *
 * As políticas em vigor, que vão junto para o registro, são acrescentadas por
 * quem abre a sessão (`useCollection`).
 */
export const DEFAULT_COLLECTION: Omit<CollectionOptions, 'policies' | 'session'> = {
  /**
   * Até que confiança as detecções são gravadas. Abaixo do limiar da sessão
   * está o que distingue o livro "quase visto" do "não visto" — o motivo da
   * coleta. A gravação usa o menor entre este e o limiar da sessão: nunca
   * perde uma detecção que o app contou.
   */
  minScore: 0.05,

  /**
   * Abaixo disto de espaço livre, marcar é recusado e a captura acontece sem
   * ser gravada (FR-020). Uma captura gravada ocupa uns 8 MB; 1 GB deixa o
   * aparelho respirar.
   */
  minFreeBytes: 1_000_000_000,

  /**
   * Qualidade de todas as imagens da coleta. A mesma do histórico: artefato de
   * compressão viraria ruído no treino e na medida.
   */
  jpegQuality: 0.9,
};

// ---------------------------------------------------------------------------
// Spec 008 — treino e prova
// ---------------------------------------------------------------------------

/**
 * As linhas do guia. A ordem importa: a diagonal que escolhe a foto inteira
 * para o pacote usa o índice daqui (research, R53). A chave é a do formato do
 * zip; rótulo e descrição são o que a pessoa lê ao escolher (FR-007).
 */
export const DISTANCES: readonly { key: ShelfDistance; label: string; description: string }[] = [
  { key: 'near', label: 'perto', description: 'Só um pedaço da prateleira: poucos livros, grandes na tela.' },
  { key: 'mid', label: 'média', description: 'A prateleira inteira dentro da faixa.' },
  { key: 'far', label: 'longe', description: 'A prateleira inteira pequena, com as vizinhas aparecendo.' },
];

/** As colunas do guia, na mesma regra de ordem das linhas. */
export const ANGLES: readonly { key: ShelfAngle; label: string; description: string }[] = [
  { key: 'left', label: 'esquerda', description: 'Uns 20 a 30° para a esquerda.' },
  { key: 'front', label: 'frente', description: 'De frente para a estante.' },
  { key: 'right', label: 'direita', description: 'Uns 20 a 30° para a direita.' },
];

/** Dia vale 0 e noite 1 na diagonal da foto inteira: a noite pega outra (R53). */
export const LIGHTS: readonly { key: CollectionLight; label: string }[] = [
  { key: 'day', label: 'dia' },
  { key: 'night', label: 'noite' },
];

/**
 * Quantas fotos sem livros o guia pede. Cerca de 10% das ~270 capturas, como a
 * Ultralytics recomenda para ensinar o que não é livro. Decisão adiada: ajustar
 * pelo que a prova mostrar de não-livros contados.
 */
export const BACKGROUND_GOAL = 30;

/**
 * O modo rápido do treino (R48). Sem aproximação nem endireitamento, e a volta
 * acontece assim que o resultado chega: a captura roda inteira e é gravada
 * igual, só a tela do resultado é pulada. O `ResultRenderer` encaixa sem animar
 * quando a duração é zero.
 */
export const FAST_CAPTURE: Pick<CaptureOptions, 'approachMs' | 'transitionMs'> = {
  approachMs: 0,
  transitionMs: 0,
};
