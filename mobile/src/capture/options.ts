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

  /**
   * Aproximação no toque, antes de a foto existir (FR-009). Da ordem de
   * `readyMs`: mais curta, a imagem para e espera; mais longa, ainda está se
   * movendo quando o endireitamento começa.
   */
  approachMs: 700,

  /**
   * Endireitamento, a partir do resultado pronto, e a volta à câmera. Soma-se
   * a `readyMs` no SC-001.
   */
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

  /**
   * Viviam como constantes no `ShelfGeometry.swift` até a T037 deste marco.
   * Os valores são os mesmos de lá: mudar de lugar não pode mudar a geometria
   * que o autor validou em 24/09.
   */
  geometry: {
    /** Em pé ou deitado. Só é mensurável porque a gravidade dá referência. */
    standingToleranceDegrees: 25,

    /** Duas fileiras se separam onde o vão passa de meia altura mediana… */
    rowGapFactor: 0.5,
    /** …e nunca menos que 2% do lado da imagem. */
    minRowGap: 0.02,

    /** Duas bases dão uma reta frágil, que contaminaria a homografia. */
    minBooksPerRow: 3,

    // Confiança (R15): cada sinal vai de 1 a 0 até o limite abaixo.
    fullConfidenceCount: 12,
    maxBaseResidual: 0.02,
    maxAngleSpread: 0.5,
    maxRowSlopeSpread: 0.3,

    /** Com gravidade a vertical não é estimativa: as retas pesam mais. */
    weightsWithGravity: { count: 0.15, line: 0.5, spread: 0.1, rows: 0.25 },
    weightsWithoutGravity: { count: 0.15, line: 0.35, spread: 0.3, rows: 0.2 },
  },

  /** Uma divisão colada na borda do recorte é a borda, não uma divisão. */
  dividerEdgeMargin: 0.01,

  /**
   * A releitura do recorte (spec 006). Por último, o modelo lê o quadrado que
   * está na tela, e só o que ele encontra é o resultado. Desligada, volta a
   * valer a leitura da foto, como na 005.
   */
  reread: true,

  /**
   * A maior parte da caixa dentro do recorte sem a margem, como a regra da
   * faixa. A margem mostra fatias dos vizinhos — na faixa vertical, quase
   * sempre — e é isto que as impede de contar. Decisão adiada: ajustar pelo
   * SC-003 da 006.
   */
  rereadMembership: 0.5,
};
