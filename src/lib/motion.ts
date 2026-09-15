/**
 * Estimador de movimento global da câmera.
 *
 * Faz duas coisas a partir da mesma leitura reduzida do frame:
 *
 * 1. **Gating** — quanto a cena mudou desde a última inferência. Apontar a
 *    câmera para uma estante é quase estático; rodar ~340ms de rede sobre um
 *    frame idêntico não muda a contagem e só gera calor, que vira throttling.
 *
 * 2. **Compensação** — para que lado a imagem andou desde a última inferência.
 *    Com detecção a ~2 fps e vídeo a 60, o overlay passa a maior parte do tempo
 *    descrevendo o passado. A observação que resolve: varrendo uma estante,
 *    quase todo o movimento na imagem é *pan da câmera* — translação global,
 *    igual para todos os objetos — e estimar translação é ordens de magnitude
 *    mais barato do que detectar objetos. Deslocando o overlay inteiro por esse
 *    valor, ele gruda na imagem entre uma detecção e outra.
 *
 * Tudo em cima de um frame reduzido: a estimativa custa a casa do décimo de
 * milissegundo, contra centenas da inferência.
 */

/**
 * Lado do frame reduzido.
 *
 * 48 em vez de 32 porque agora a leitura não é só "mudou quanto" e sim "andou
 * para onde": num frame de 480x640, cada pixel da amostra vale 10px na imagem,
 * e é esse passo que limita a precisão do deslocamento (antes do refinamento
 * sub-pixel abaixo). Dobrar de novo custaria 4x o tempo por pouco ganho.
 */
const SAMPLE_SIZE = 48;

/**
 * Raio da busca por deslocamento, em pixels da amostra.
 *
 * 4 cobre ±40px de imagem por frame — a 60fps, mais de 2400px/s, bem além de
 * qualquer movimento de mão. Ampliar custa quadrático e só serviria para
 * movimentos que já borrariam a imagem de qualquer forma.
 */
const SEARCH_RADIUS = 4;

/**
 * Teto do deslocamento acumulado, em fração da dimensão do frame.
 *
 * O acumulado zera a cada inferência, mas num ciclo lento com pan rápido ele
 * pode ficar grande o bastante para arrastar o overlay para fora de qualquer
 * relação com a imagem. Aí é melhor ficar para trás do que mentir.
 */
const MAX_OFFSET_FRACTION = 0.25;

/** Teto do acumulado, em pixels da amostra. */
const OFFSET_LIMIT = SAMPLE_SIZE * MAX_OFFSET_FRACTION;

/**
 * Diferença média por pixel (0-255) que separa ruído de movimento real.
 *
 * Medido no iPhone alvo em 14/09/2026:
 *
 *   parado sobre a mesa   0.1          <- piso de ruído do sensor
 *   segurando na mão      3.0 a 10.0   <- movimento real mais fraco: 3.0
 *
 * 0.5 fica 5x acima do ruído e 6x abaixo do movimento mais fraco — as duas
 * margens são multiplicativas e ficam equilibradas (0.5 é praticamente a média
 * geométrica de 0.1 e 3.0). O primeiro chute foi 4, que caía **dentro** da faixa
 * de movimento real e congelava a detecção no meio de um pan lento.
 *
 * Sobrescrevível por `?motion=N`; o painel de debug mostra a leitura ao vivo ao
 * lado do limiar para recalibrar em outra câmera ou com pouca luz.
 */
export const DEFAULT_MOTION_THRESHOLD = 0.5;

export interface MotionTracker {
  /**
   * Lê o frame atual: atualiza o deslocamento acumulado e a diferença contra a
   * referência. Chamado pelo loop de desenho, a cada frame.
   */
  sample: (video: HTMLVideoElement) => void;
  /** Diferença média por pixel contra o frame da última inferência. */
  readonly mad: number;
  /** Deslocamento acumulado desde a última inferência, em pixels do frame. */
  readonly offsetX: number;
  readonly offsetY: number;
  /**
   * Marca o frame atual como referência e zera o acumulado. Chamado depois de
   * uma inferência: é dela que o overlay agora na tela descende, então é dela
   * que o deslocamento deve ser contado.
   */
  commit: () => void;
}

/**
 * Refinamento sub-pixel por parábola.
 *
 * A busca devolve o melhor deslocamento inteiro; sem isto o overlay andaria aos
 * saltos de 10px (o tamanho de um pixel da amostra na imagem). Ajustar uma
 * parábola nos três SADs em volta do mínimo e pegar o vértice dá o fundo do
 * vale com precisão de fração de pixel, ao custo de três subtrações.
 */
const subPixel = (before: number, center: number, after: number): number => {
  const denominator = before - 2 * center + after;
  if (denominator === 0) return 0;

  const delta = (0.5 * (before - after)) / denominator;
  // Fora de ±1 a parábola não descreve mais o vale: o mínimo real está noutro
  // ponto da grade e o refinamento seria ruído.
  return Math.abs(delta) <= 1 ? delta : 0;
};

export const createMotionTracker = (): MotionTracker => {
  const canvas = document.createElement('canvas');
  canvas.width = SAMPLE_SIZE;
  canvas.height = SAMPLE_SIZE;

  // `willReadFrequently` mantém o canvas na CPU: são muitos getImageData
  // pequenos, exatamente o caso que essa dica existe para atender.
  const ctx = canvas.getContext('2d', { willReadFrequently: true });

  const pixelCount = SAMPLE_SIZE * SAMPLE_SIZE;
  const current = new Uint8Array(pixelCount);
  const previous = new Uint8Array(pixelCount);
  const reference = new Uint8Array(pixelCount);

  let hasPrevious = false;
  let hasReference = false;

  // Acumulado em pixels da amostra; só vira pixel de imagem na leitura.
  let offsetSampleX = 0;
  let offsetSampleY = 0;
  let scaleX = 1;
  let scaleY = 1;

  let mad = Infinity;

  /**
   * Diferença média por pixel entre `current` e `previous`, deslocando
   * `previous` de (dx, dy). Normalizada pela área sobreposta: sem isso um
   * deslocamento grande sempre venceria, por comparar menos pixels.
   */
  const shiftedDifference = (dx: number, dy: number): number => {
    const xStart = Math.max(0, -dx);
    const xEnd = Math.min(SAMPLE_SIZE, SAMPLE_SIZE - dx);
    const yStart = Math.max(0, -dy);
    const yEnd = Math.min(SAMPLE_SIZE, SAMPLE_SIZE - dy);

    let total = 0;
    let count = 0;

    for (let y = yStart; y < yEnd; y += 1) {
      const currentRow = y * SAMPLE_SIZE;
      const previousRow = (y + dy) * SAMPLE_SIZE + dx;

      for (let x = xStart; x < xEnd; x += 1) {
        total += Math.abs(current[currentRow + x] - previous[previousRow + x]);
        count += 1;
      }
    }

    return count > 0 ? total / count : Infinity;
  };

  const sample = (video: HTMLVideoElement) => {
    if (!ctx || !video.videoWidth) return;

    scaleX = video.videoWidth / SAMPLE_SIZE;
    scaleY = video.videoHeight / SAMPLE_SIZE;

    ctx.drawImage(video, 0, 0, SAMPLE_SIZE, SAMPLE_SIZE);
    const { data } = ctx.getImageData(0, 0, SAMPLE_SIZE, SAMPLE_SIZE);

    // Canal verde como proxy de luminância: é o que mais pesa na percepção de
    // brilho e evita somar três canais por pixel à toa.
    let referenceTotal = 0;
    for (let i = 0; i < pixelCount; i += 1) {
      const green = data[i * 4 + 1];
      current[i] = green;
      referenceTotal += Math.abs(green - reference[i]);
    }

    mad = hasReference ? referenceTotal / pixelCount : Infinity;

    if (hasPrevious) {
      // Busca exaustiva num raio pequeno. Guarda os vizinhos do melhor para o
      // refinamento sub-pixel logo abaixo.
      let bestX = 0;
      let bestY = 0;
      let bestScore = Infinity;

      for (let dy = -SEARCH_RADIUS; dy <= SEARCH_RADIUS; dy += 1) {
        for (let dx = -SEARCH_RADIUS; dx <= SEARCH_RADIUS; dx += 1) {
          const score = shiftedDifference(dx, dy);
          if (score < bestScore) {
            bestScore = score;
            bestX = dx;
            bestY = dy;
          }
        }
      }

      // Mínimo na borda da busca não é um casamento: ou o movimento passou do
      // alcance, ou a imagem é ambígua (textura repetitiva, parede lisa) e o
      // vale caiu ali por acaso. Um teste sintético com padrão periódico
      // devolvia (4, -4) para um deslocamento real de (-0.5, 1.5) — errado em
      // sinal e magnitude. Nesses frames é melhor não deslocar nada: o overlay
      // fica para trás por um frame em vez de sair correndo para o lado errado.
      const onBoundary =
        Math.abs(bestX) === SEARCH_RADIUS || Math.abs(bestY) === SEARCH_RADIUS;

      if (!onBoundary) {
        const refinedX =
          bestX +
          subPixel(
            shiftedDifference(bestX - 1, bestY),
            bestScore,
            shiftedDifference(bestX + 1, bestY)
          );

        const refinedY =
          bestY +
          subPixel(
            shiftedDifference(bestX, bestY - 1),
            bestScore,
            shiftedDifference(bestX, bestY + 1)
          );

        // O deslocamento encontrado diz de onde veio o conteúdo do frame atual,
        // então o overlay antigo precisa andar no sentido oposto.
        offsetSampleX = Math.max(-OFFSET_LIMIT, Math.min(OFFSET_LIMIT, offsetSampleX - refinedX));
        offsetSampleY = Math.max(-OFFSET_LIMIT, Math.min(OFFSET_LIMIT, offsetSampleY - refinedY));
      }
    }

    previous.set(current);
    hasPrevious = true;
  };

  return {
    sample,
    get mad() {
      return mad;
    },
    get offsetX() {
      return offsetSampleX * scaleX;
    },
    get offsetY() {
      return offsetSampleY * scaleY;
    },
    commit: () => {
      reference.set(current);
      hasReference = true;
      offsetSampleX = 0;
      offsetSampleY = 0;
    }
  };
};
