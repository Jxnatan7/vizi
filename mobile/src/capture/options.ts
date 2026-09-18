import type { CaptureOptions } from '../../modules/vizi-vision';

/**
 * Política da captura. Vive aqui, não no Swift — princípio IV.
 *
 * Os limiares de geometria são **palpites iniciais**. A T024 os substitui por
 * números calibrados em capturas deliberadamente ruins: poucos livros, estante
 * curva, ângulo extremo.
 */
export const DEFAULT_CAPTURE: CaptureOptions = {
  /** Margem em volta da faixa de livros, como fração da largura. */
  cropMargin: 0.05,

  /** Abaixo disto a estante é mal determinada e nem vale tentar. */
  minInstancesForGeometry: 5,

  /** Endireitar errado é pior que não endireitar — daí o limiar alto. */
  minGeometryConfidence: 0.6,

  transitionMs: 600,

  /**
   * Mostra horizonte, pontos de fuga, recorte e a curva de azimute sobre a
   * foto crua, em vez do resultado.
   *
   * Existe porque geometria projetiva falha de formas que parecem iguais na
   * saída — horizonte torto, ponto de fuga errado e cantos trocados produzem
   * todos "a imagem ficou estranha". Sem ver as etapas, consertar é adivinhar.
   */
  diagnostics: false,
};
