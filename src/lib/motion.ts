/**
 * Detector de movimento barato, para decidir se vale a pena rodar a inferência.
 *
 * Apontar a câmera para uma estante é um caso quase estático: o telefone fica
 * parado na mão. Rodar ~300ms de rede neural sobre um frame idêntico ao anterior
 * não muda a contagem e só gera calor — que vira throttling térmico, que deixa a
 * inferência mais lenta. Medimos `infer` variando de 264 a 317ms conforme o
 * aparelho esquentava.
 *
 * A comparação é feita num frame reduzido a 32x32: 1024 pixels bastam para
 * separar "a mão tremeu" de "nada mudou", e o custo fica na casa do
 * microssegundo, contra centenas de milissegundos da inferência.
 */

/** Lado do frame reduzido. 32x32 = 1024 amostras. */
const SAMPLE_SIZE = 32;

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

export interface MotionSampler {
  /**
   * Diferença média por pixel entre o frame atual e o de referência.
   * Devolve `Infinity` enquanto não houver referência, para que a primeira
   * inferência sempre aconteça.
   */
  sample: (video: HTMLVideoElement) => number;
  /**
   * Promove o último frame amostrado a referência. Chamado depois de uma
   * inferência: a referência precisa ser o frame que produziu o resultado
   * atualmente na tela, senão uma deriva lenta nunca acumula diferença
   * suficiente para disparar.
   */
  commit: () => void;
}

export const createMotionSampler = (): MotionSampler => {
  const canvas = document.createElement('canvas');
  canvas.width = SAMPLE_SIZE;
  canvas.height = SAMPLE_SIZE;

  // `willReadFrequently` mantém o canvas na CPU: são muitos getImageData
  // pequenos, exatamente o caso que essa dica existe para atender.
  const ctx = canvas.getContext('2d', { willReadFrequently: true });

  const pixelCount = SAMPLE_SIZE * SAMPLE_SIZE;
  const scratch = new Uint8ClampedArray(pixelCount);
  const reference = new Uint8ClampedArray(pixelCount);
  let hasReference = false;

  const sample = (video: HTMLVideoElement): number => {
    if (!ctx) return Infinity; // Sem canvas não dá para medir: nunca bloqueia.

    ctx.drawImage(video, 0, 0, SAMPLE_SIZE, SAMPLE_SIZE);
    const { data } = ctx.getImageData(0, 0, SAMPLE_SIZE, SAMPLE_SIZE);

    // Canal verde como proxy de luminância: é o que mais pesa na percepção de
    // brilho e evita somar três canais por pixel à toa.
    let total = 0;
    for (let i = 0; i < pixelCount; i += 1) {
      const green = data[i * 4 + 1];
      scratch[i] = green;
      total += Math.abs(green - reference[i]);
    }

    return hasReference ? total / pixelCount : Infinity;
  };

  const commit = () => {
    reference.set(scratch);
    hasReference = true;
  };

  return { sample, commit };
};
