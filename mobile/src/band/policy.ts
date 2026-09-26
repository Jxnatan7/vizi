import type { BandPolicy } from '../../modules/vizi-vision';

/**
 * Comportamento da faixa de interesse. Vive aqui, não no Swift — princípio IV.
 *
 * Vai junto com a sessão: é ela que diz como toda sessão começa (FR-002). Os
 * valores marcados como palpite são as decisões adiadas da spec — só o
 * aparelho, e o teste com pessoas (SC-005), dizem o número certo.
 */
export const DEFAULT_BAND: BandPolicy = {
  /**
   * Espessura no começo da sessão e ao voltar ao centro. Um terço é a linha do
   * meio da grade 3×3 que deu origem à faixa.
   */
  defaultThickness: 1 / 3,

  /** Estreita demais não cabe um livro inteiro. Palpite. */
  minThickness: 0.1,

  /**
   * Fração da caixa que precisa estar dentro. A maior parte: pela base, a
   * borda da faixa cairia exatamente na tábua da prateleira.
   */
  membership: 0.5,

  /** Folga em torno da diagonal para virar a faixa sem tremular. Palpite. */
  flipHysteresisDegrees: 15,

  /** Quanto as duas bordas passam da imagem para a faixa se desligar. Palpite. */
  offMargin: 0.04,

  /** Quanto do excesso aparece ao puxar além do limite — o elástico. */
  rubberBand: 0.35,

  /** Abaixo disto, em pontos, o dedo tocou: não arrastou. */
  startSlopPoints: 6,

  /** Meia altura da área de agarrar uma borda: 44 pt no total, o mínimo do iOS. */
  edgeGrabPoints: 22,

  /** Janela da mediana da contagem junto à faixa. Maior, estável e lenta. */
  countWindowMs: 500,

  /** Tempo da mola, em segundos. */
  springResponse: 0.35,

  /** Abaixo de 1 a mola passa um pouco e volta — é o que dá peso à faixa. */
  springDamping: 0.85,

  haptics: true,
};
