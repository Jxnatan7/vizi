import type { TrackedBox } from './tracker';

/** O que a interface escolheu exibir por cima do vídeo. */
export interface OverlayOptions {
  showBoxes: boolean;
  showMasks: boolean;
  /**
   * Multiplica o alfa que o engine já embutiu na máscara, então 1 é o teto:
   * dá para apagar a máscara, não para deixá-la mais opaca que o padrão.
   */
  maskOpacity: number;
}

const BOX_COLOR = '#00FF00';
const LABEL_TEXT_COLOR = '#000000';
const LABEL_FONT = '16px Arial';
const LABEL_HEIGHT = 24;

/**
 * Compõe máscara e caixas no canvas visível, na ordem em que precisam se
 * sobrepor: a máscara é o fundo, as caixas ficam por cima.
 *
 * A máscara passa por um canvas auxiliar antes de entrar no principal porque
 * putImageData sobrescreve pixels e ignora globalAlpha — desenhá-la direto
 * apagaria as caixas e deixaria o controle de opacidade sem efeito.
 */
export const drawOverlay = (
  ctx: CanvasRenderingContext2D,
  offscreen: HTMLCanvasElement,
  tracked: TrackedBox[],
  masks: Uint8Array,
  { showBoxes, showMasks, maskOpacity }: OverlayOptions
) => {
  const { width, height } = ctx.canvas;

  // Limpa sempre: com os dois modos desmarcados o vídeo fica sem nada por cima.
  ctx.clearRect(0, 0, width, height);

  // O engine devolve a máscara já composta e colorida, do tamanho do frame.
  // Um modelo sem cabeça de segmentação devolve um array vazio, e o overlay só
  // se alinha ao vídeo se vier exatamente nas dimensões dele.
  if (showMasks && maskOpacity > 0 && masks.length === width * height * 4) {
    if (offscreen.width !== width || offscreen.height !== height) {
      offscreen.width = width;
      offscreen.height = height;
    }

    const offscreenCtx = offscreen.getContext('2d');
    if (offscreenCtx) {
      // A cópia é o que ImageData exige (Uint8ClampedArray); é o mesmo caminho
      // que o annotate da própria lib faz.
      const image = new ImageData(new Uint8ClampedArray(masks), width, height);
      offscreenCtx.putImageData(image, 0, 0);

      ctx.globalAlpha = maskOpacity;
      ctx.drawImage(offscreen, 0, 0);
      ctx.globalAlpha = 1;
    }
  }

  if (!showBoxes) return;

  tracked.forEach(({ id, box }) => {
    // A lib devolve xyxy em pixels; o canvas desenha a partir de x/y + tamanho.
    const x = box.x1;
    const y = box.y1;
    const boxWidth = box.x2 - box.x1;
    const boxHeight = box.y2 - box.y1;
    const label = `#${id} ${Math.round(box.conf * 100)}%`;

    ctx.strokeStyle = BOX_COLOR;
    ctx.lineWidth = 4;
    ctx.strokeRect(x, y, boxWidth, boxHeight);

    ctx.font = LABEL_FONT;
    const textWidth = ctx.measureText(label).width;

    ctx.fillStyle = BOX_COLOR;
    ctx.fillRect(x, y - LABEL_HEIGHT, textWidth + 10, LABEL_HEIGHT);

    ctx.fillStyle = LABEL_TEXT_COLOR;
    ctx.fillText(label, x + 5, y - 6);
  });
};
