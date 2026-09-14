import type { Box } from '@ultralytics/yolo';

/** Uma caixa do frame atual, já com a identidade atribuída pelo tracker. */
export interface TrackedBox {
  id: number;
  box: Box;
}

// Sobreposição mínima para considerar que duas caixas são o mesmo objeto.
// Baixo de propósito: a mão treme e a caixa pula bastante entre inferências.
const IOU_THRESHOLD = 0.3;

// Por quantas inferências seguidas um objeto pode sumir e ainda recuperar o
// mesmo id. Com uma inferência a cada ~100ms, isso dá meio segundo de perdão —
// o bastante para uma oclusão rápida ou um frame em que a confiança caiu.
const MAX_MISSED_FRAMES = 5;

interface Track {
  id: number;
  cls: number;
  box: Box;
  missedFrames: number;
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
 * Tracker por IoU. Guarda as caixas do frame anterior e casa cada detecção
 * nova com a mais sobreposta, de forma que o mesmo objeto físico mantenha o
 * mesmo id enquanto estiver em cena.
 *
 * Ids são sempre crescentes: um objeto que some por tempo demais leva o id
 * embora e ganha um novo se voltar. O estado vive todo no closure, então basta
 * criar outra instância para zerar a numeração (ex.: ao trocar de câmera).
 */
export const createTracker = () => {
  let tracks: Track[] = [];
  let nextId = 1;

  const update = (boxes: Box[]): TrackedBox[] => {
    // Casamento guloso: a melhor sobreposição global vence primeiro, o que
    // evita que uma caixa roube o id de um vizinho por ordem de iteração.
    const pairs: Array<{ trackIndex: number; boxIndex: number; score: number }> = [];

    tracks.forEach((track, trackIndex) => {
      boxes.forEach((box, boxIndex) => {
        // Classes diferentes nunca são o mesmo objeto, por mais que se sobreponham.
        if (track.cls !== box.cls) return;

        const score = iou(track.box, box);
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
        // Sumiu neste frame: segura o id pelo período de tolerância.
        if (track.missedFrames + 1 <= MAX_MISSED_FRAMES) {
          survivors.push({ ...track, missedFrames: track.missedFrames + 1 });
        }
        return;
      }

      const box = boxes[boxIndex];
      survivors.push({ id: track.id, cls: box.cls, box, missedFrames: 0 });
      tracked.push({ id: track.id, box });
    });

    boxes.forEach((box, boxIndex) => {
      if (takenBoxes.has(boxIndex)) return;

      const id = nextId++;
      survivors.push({ id, cls: box.cls, box, missedFrames: 0 });
      tracked.push({ id, box });
    });

    tracks = survivors;

    // Ordena pelo id para que a lista saia estável entre frames, e não na
    // ordem em que o modelo devolveu as caixas.
    return tracked.sort((a, b) => a.id - b.id);
  };

  return { update };
};
