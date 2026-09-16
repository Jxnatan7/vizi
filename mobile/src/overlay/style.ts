import type { OverlayStyle } from '../../modules/vizi-vision';

/**
 * Aparência do overlay. Vive aqui, não no Swift — é a mitigação do princípio IV
 * registrada no plano do marco 3.
 *
 * O nativo executa o desenho; este objeto decide como ele fica.
 */
export const DEFAULT_OVERLAY: OverlayStyle = {
  showBoxes: true,
  showMasks: true,

  /** Pixels do espaço do modelo (640), não da tela. */
  boxWidth: 3,
  maskOpacity: 0.45,

  /**
   * Separado do limiar de detecção de propósito: aquele decide o que *existe*,
   * este decide o que *aparece*. É a diferença entre um overlay poluído e um
   * legível, e dá para ajustar um sem mexer no outro.
   */
  minConfidence: 0.3,

  /** Atribuída por posição no nativo — ver R11. */
  palette: ['#4AC79E', '#FAB554', '#6BA6F5', '#F2757F', '#BA94F0', '#66D9DE'],
};
