import { projectBox, type TrackedBox } from './tracker';

/**
 * O que a interface escolheu exibir por cima do vídeo.
 *
 * Nenhum destes campos chega mais às funções de desenho: a visibilidade das
 * camadas e a opacidade da máscara são resolvidas em CSS. O tipo continua aqui
 * porque é o contrato entre os controles e o componente de detecção.
 */
export interface OverlayOptions {
  showBoxes: boolean;
  showMasks: boolean;
  /** 0 a 1, aplicado como `opacity` na camada da máscara. */
  maskOpacity: number;
}

const BOX_COLOR = '#00FF00';
const LABEL_TEXT_COLOR = '#000000';
const LABEL_FONT = '16px Arial';
const LABEL_HEIGHT = 24;

/**
 * Escreve a máscara na sua própria camada.
 *
 * Antes isto passava por um canvas auxiliar porque `putImageData` sobrescreve
 * pixels e ignora `globalAlpha`, então desenhar direto apagaria as caixas e
 * deixaria o controle de opacidade sem efeito. Com máscara e caixas em canvas
 * separados nada disso vale: `putImageData` direto é o caminho mais curto, e a
 * opacidade virou uma propriedade CSS da camada (trabalho de compositor, sem
 * repintura).
 *
 * O `ImageData` é reaproveitado entre chamadas: `masks` chega como `Uint8Array`
 * e o `ImageData` exige `Uint8ClampedArray`, então a cópia é inevitável — mas a
 * alocação de ~1.2 MB por inferência não é.
 */
export const createMaskPainter = () => {
  let image: ImageData | null = null;

  return (ctx: CanvasRenderingContext2D, masks: Uint8Array) => {
    const { width, height } = ctx.canvas;

    // Um modelo sem cabeça de segmentação devolve um array vazio, e o overlay
    // só se alinha ao vídeo se vier exatamente nas dimensões dele.
    if (masks.length !== width * height * 4) {
      ctx.clearRect(0, 0, width, height);
      return;
    }

    if (!image || image.width !== width || image.height !== height) {
      image = new ImageData(width, height);
    }

    image.data.set(masks);
    ctx.putImageData(image, 0, 0);
  };
};

/**
 * Desenha as caixas na camada de cima, projetadas para o instante `now` e
 * deslocadas pelo movimento da câmera.
 *
 * Chamado a cada rAF, e não a cada inferência: entre duas detecções a caixa
 * continua se movendo em vez de ficar congelada e saltar. É o que dá a
 * impressão de overlay a 60 FPS sobre ~2 inferências por segundo.
 */
export const drawBoxes = (
  ctx: CanvasRenderingContext2D,
  tracked: TrackedBox[],
  now: number,
  /**
   * Deslocamento global da câmera desde a inferência, em pixels do frame.
   * Somado por cima da projeção por velocidade: a velocidade responde pelo
   * movimento *relativo* dos objetos, e isto pelo movimento da câmera, que é a
   * maior parte do que acontece na tela ao varrer uma estante.
   */
  offsetX = 0,
  offsetY = 0
) => {
  const { width, height } = ctx.canvas;
  ctx.clearRect(0, 0, width, height);

  ctx.lineWidth = 4;
  ctx.strokeStyle = BOX_COLOR;
  ctx.font = LABEL_FONT;

  for (const entry of tracked) {
    const box = projectBox(entry, now);

    // A lib devolve xyxy em pixels; o canvas desenha a partir de x/y + tamanho.
    const x = box.x1 + offsetX;
    const y = box.y1 + offsetY;
    const boxWidth = box.x2 - box.x1;
    const boxHeight = box.y2 - box.y1;
    const label = `#${entry.id} ${Math.round(box.conf * 100)}%`;

    ctx.strokeRect(x, y, boxWidth, boxHeight);

    const textWidth = ctx.measureText(label).width;

    ctx.fillStyle = BOX_COLOR;
    ctx.fillRect(x, y - LABEL_HEIGHT, textWidth + 10, LABEL_HEIGHT);

    ctx.fillStyle = LABEL_TEXT_COLOR;
    ctx.fillText(label, x + 5, y - 6);
  }
};
