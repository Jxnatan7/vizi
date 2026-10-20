import type { CollectionOptions } from '../../modules/vizi-vision';

/**
 * Política da coleta (spec 007). Vive aqui, não no Swift — princípio IV.
 *
 * As políticas em vigor, que vão junto para o registro, são acrescentadas por
 * quem abre a sessão (`useCollection`).
 */
export const DEFAULT_COLLECTION: Omit<CollectionOptions, 'policies'> = {
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
