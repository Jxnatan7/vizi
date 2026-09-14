import type { Box } from '@ultralytics/yolo';

/** Uma caixa do frame atual, já com a identidade atribuída pelo tracker. */
export interface TrackedBox {
  id: number;
  box: Box;
  /**
   * Velocidade por coordenada, em px/ms, para extrapolar entre inferências.
   * Zero numa caixa recém-criada, que ainda não tem histórico.
   */
  velocity: { x1: number; y1: number; x2: number; y2: number };
  /** `performance.now()` da inferência que produziu esta caixa. */
  at: number;
  /**
   * Até quando esta caixa pode ser projetada para frente, em ms desde `at`.
   *
   * Derivado da cadência real de inferência, e não fixo: com constante fixa a
   * caixa congela assim que o teto é atingido e salta quando o resultado
   * seguinte chega. Foi exatamente o que aconteceu — teto de 150ms contra um
   * ciclo medido de 472ms deixava a caixa parada dois terços do tempo.
   */
  maxProjectionMs: number;
}

// Sobreposição mínima para considerar que duas caixas são o mesmo objeto.
// Baixo de propósito: a mão treme e a caixa pula bastante entre inferências.
const IOU_THRESHOLD = 0.3;

/**
 * Tudo abaixo é expresso em **ciclos de inferência**, não em milissegundos.
 *
 * A cadência real varia demais para constantes fixas: 136ms com o modelo de
 * 320, 472ms com o de 640 e guarda térmica ativa, e mais ainda num aparelho
 * quente. Duas calibrações em ms já quebraram por isso — a extrapolação
 * congelava e a velocidade era descartada. O tracker mede o próprio intervalo
 * entre atualizações e deriva os limites dele.
 */

/** Tolerância de sumiço, em ciclos. Dois perdoam uma oclusão rápida. */
const MISSED_CYCLES = 2;

/**
 * Até onde projetar, em ciclos. Um pouco mais que um ciclo inteiro para a
 * caixa nunca congelar esperando o resultado seguinte, mas não tanto a ponto
 * de sair viajando quando a detecção some de vez.
 */
const PROJECTION_CYCLES = 1.25;

/** Acima disto o intervalo não é uma cadência, é uma retomada: velocidade zerada. */
const VELOCITY_VALID_CYCLES = 3;

/** Enquanto não há cadência medida, e como piso/teto de sanidade. */
const FALLBACK_CYCLE_MS = 300;
const MIN_CYCLE_MS = 80;
const MAX_CYCLE_MS = 1500;

/**
 * Suavização da velocidade (não da posição).
 *
 * Suavizar a posição atrasaria ainda mais a caixa, que já mostra onde o objeto
 * estava uma inferência atrás. Suavizar a velocidade tira o tranco entre
 * medidas sem adicionar atraso à projeção.
 */
const VELOCITY_SMOOTHING = 0.5;

interface Track {
  id: number;
  cls: number;
  box: Box;
  velocity: { x1: number; y1: number; x2: number; y2: number };
  at: number;
  missedSince: number | null;
}

const iou = (a: Box, b: Box) => {
  const interWidth = Math.min(a.x2, b.x2) - Math.max(a.x1, b.x1);
  const interHeight = Math.min(a.y2, b.y2) - Math.max(a.y1, b.y1);

  if (interWidth <= 0 || interHeight <= 0) return 0;

  const intersection = interWidth * interHeight;
  const areaA = (a.x2 - a.x1) * (a.y2 - a.y1);
  const areaB = (b.x2 - b.x1) * (b.y2 - b.y1);
  const union = areaA + areaB - intersection;

  return union > 0 ? intersection / union : 0;
};

/**
 * Projeta a caixa para o instante `now`, usando a velocidade estimada.
 *
 * É o que permite desenhar a 60 FPS sobre inferências de ~3 por segundo: em vez
 * de repetir a mesma caixa por 300ms e saltar, o desenho acompanha o movimento
 * estimado. Pura de propósito — o loop de desenho a chama a cada frame sem
 * tocar no estado do tracker.
 */
export const projectBox = ({ box, velocity, at, maxProjectionMs }: TrackedBox, now: number): Box => {
  const age = Math.min(Math.max(now - at, 0), maxProjectionMs);
  if (age === 0) return box;

  return {
    ...box,
    x1: box.x1 + velocity.x1 * age,
    y1: box.y1 + velocity.y1 * age,
    x2: box.x2 + velocity.x2 * age,
    y2: box.y2 + velocity.y2 * age
  };
};

/**
 * Tracker por IoU. Guarda as caixas do frame anterior e casa cada detecção
 * nova com a mais sobreposta, de forma que o mesmo objeto físico mantenha o
 * mesmo id enquanto estiver em cena.
 *
 * O casamento é feito contra a posição **projetada** para o instante atual, não
 * contra a última posição medida: num pan, a caixa antiga já não sobrepõe a
 * nova, e o track morreria sem necessidade.
 *
 * Ids são sempre crescentes: um objeto que some por tempo demais leva o id
 * embora e ganha um novo se voltar. O estado vive todo no closure, então basta
 * criar outra instância para zerar a numeração (ex.: ao trocar de câmera).
 */
export const createTracker = () => {
  let tracks: Track[] = [];
  let nextId = 1;

  // Cadência observada entre atualizações. É o que dá escala a todos os limites
  // temporais daqui: o mesmo código serve a 7 fps com o modelo de 320 e a 2 fps
  // com o de 640 sob calor, sem recalibrar nada.
  let emaCycleMs = FALLBACK_CYCLE_MS;
  let lastUpdateAt = 0;

  const update = (boxes: Box[], now = performance.now()): TrackedBox[] => {
    if (lastUpdateAt > 0) {
      const cycleMs = now - lastUpdateAt;
      // Um intervalo absurdo veio de uma pausa (motion gating, aba em segundo
      // plano) e não descreve a cadência: não pode contaminar a média.
      if (cycleMs >= MIN_CYCLE_MS && cycleMs <= MAX_CYCLE_MS) {
        emaCycleMs = emaCycleMs * 0.7 + cycleMs * 0.3;
      }
    }
    lastUpdateAt = now;

    const maxMissedMs = emaCycleMs * MISSED_CYCLES;
    const maxProjectionMs = emaCycleMs * PROJECTION_CYCLES;
    const maxVelocityGapMs = emaCycleMs * VELOCITY_VALID_CYCLES;

    // Casamento guloso: a melhor sobreposição global vence primeiro, o que
    // evita que uma caixa roube o id de um vizinho por ordem de iteração.
    const pairs: Array<{ trackIndex: number; boxIndex: number; score: number }> = [];

    tracks.forEach((track, trackIndex) => {
      const predicted = projectBox({ ...track, maxProjectionMs }, now);

      boxes.forEach((box, boxIndex) => {
        // Classes diferentes nunca são o mesmo objeto, por mais que se sobreponham.
        if (track.cls !== box.cls) return;

        const score = iou(predicted, box);
        if (score >= IOU_THRESHOLD) pairs.push({ trackIndex, boxIndex, score });
      });
    });

    pairs.sort((a, b) => b.score - a.score);

    const trackToBox = new Map<number, number>();
    const takenBoxes = new Set<number>();

    for (const pair of pairs) {
      if (trackToBox.has(pair.trackIndex) || takenBoxes.has(pair.boxIndex)) continue;
      trackToBox.set(pair.trackIndex, pair.boxIndex);
      takenBoxes.add(pair.boxIndex);
    }

    const survivors: Track[] = [];
    const tracked: TrackedBox[] = [];

    tracks.forEach((track, trackIndex) => {
      const boxIndex = trackToBox.get(trackIndex);

      if (boxIndex === undefined) {
        // Sumiu neste ciclo: segura o id pelo período de tolerância.
        const missedSince = track.missedSince ?? now;
        if (now - missedSince <= maxMissedMs) {
          survivors.push({ ...track, missedSince });
        }
        return;
      }

      const box = boxes[boxIndex];
      const dt = now - track.at;

      // dt zero seria divisão por zero; um dt enorme veio de um track que ficou
      // parado no limbo e cuja "velocidade" não significaria nada.
      const measured =
        dt > 0 && dt <= maxVelocityGapMs
          ? {
              x1: (box.x1 - track.box.x1) / dt,
              y1: (box.y1 - track.box.y1) / dt,
              x2: (box.x2 - track.box.x2) / dt,
              y2: (box.y2 - track.box.y2) / dt
            }
          : { x1: 0, y1: 0, x2: 0, y2: 0 };

      const velocity = {
        x1: track.velocity.x1 + (measured.x1 - track.velocity.x1) * VELOCITY_SMOOTHING,
        y1: track.velocity.y1 + (measured.y1 - track.velocity.y1) * VELOCITY_SMOOTHING,
        x2: track.velocity.x2 + (measured.x2 - track.velocity.x2) * VELOCITY_SMOOTHING,
        y2: track.velocity.y2 + (measured.y2 - track.velocity.y2) * VELOCITY_SMOOTHING
      };

      survivors.push({ id: track.id, cls: box.cls, box, velocity, at: now, missedSince: null });
      tracked.push({ id: track.id, box, velocity, at: now, maxProjectionMs });
    });

    boxes.forEach((box, boxIndex) => {
      if (takenBoxes.has(boxIndex)) return;

      const id = nextId++;
      const velocity = { x1: 0, y1: 0, x2: 0, y2: 0 };

      survivors.push({ id, cls: box.cls, box, velocity, at: now, missedSince: null });
      tracked.push({ id, box, velocity, at: now, maxProjectionMs });
    });

    tracks = survivors;

    // Ordena pelo id para que a lista saia estável entre frames, e não na
    // ordem em que o modelo devolveu as caixas.
    return tracked.sort((a, b) => a.id - b.id);
  };

  return { update };
};
