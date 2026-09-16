import type { Instance } from '../../modules/vizi-vision';

import expected from '../../assets/reference-expected.json';

/**
 * Compara a saída do aparelho com a referência gerada pelo Ultralytics.
 *
 * Só é justo porque a imagem de referência tem exatamente o tamanho da entrada
 * do modelo (640×640): nenhum dos dois caminhos redimensiona, então os dois
 * veem os mesmos pixels. Qualquer diferença aqui é da conversão do modelo ou
 * da decodificação — que é o que a US3 quer medir.
 */

/** Um par conta como o mesmo objeto acima disto. */
export const MATCH_IOU = 0.9;

export type Comparison = {
  expectedCount: number;
  actualCount: number;
  matched: number;
  /** Pior IoU entre os pares casados — quanto a geometria divergiu. */
  worstIoU: number;
  /** Maior desvio do centro, em pixels. */
  maxCenterDeltaPx: number;
  classMismatches: number;
  pass: boolean;
};

type Box = { cls: number; x1: number; y1: number; x2: number; y2: number };

const reference: Box[] = expected.boxes_xyxy.map((b: number[], i: number) => ({
  cls: Math.round(expected.classes[i]),
  x1: b[0], y1: b[1], x2: b[2], y2: b[3],
}));

const toBox = (i: Instance): Box => ({
  cls: i.classIndex,
  x1: i.x, y1: i.y, x2: i.x + i.width, y2: i.y + i.height,
});

function iou(a: Box, b: Box): number {
  const w = Math.max(0, Math.min(a.x2, b.x2) - Math.max(a.x1, b.x1));
  const h = Math.max(0, Math.min(a.y2, b.y2) - Math.max(a.y1, b.y1));
  const inter = w * h;
  if (inter <= 0) return 0;
  const union = (a.x2 - a.x1) * (a.y2 - a.y1) + (b.x2 - b.x1) * (b.y2 - b.y1) - inter;
  return union > 0 ? inter / union : 0;
}

const centerDelta = (a: Box, b: Box) =>
  Math.hypot((a.x1 + a.x2) / 2 - (b.x1 + b.x2) / 2, (a.y1 + a.y2) / 2 - (b.y1 + b.y2) / 2);

export function compareWithReference(instances: Instance[]): Comparison {
  const pool = [...reference];
  let matched = 0;
  let worstIoU = 1;
  let maxCenterDeltaPx = 0;
  let classMismatches = 0;

  // Guloso pelo melhor IoU: cada referência é consumida uma vez, então uma
  // caixa duplicada não casa duas vezes e infla o resultado.
  for (const inst of instances) {
    const box = toBox(inst);
    let bestIdx = -1;
    let best = 0;
    pool.forEach((ref, idx) => {
      const score = iou(box, ref);
      if (score > best) { best = score; bestIdx = idx; }
    });

    if (bestIdx >= 0 && best >= MATCH_IOU) {
      const ref = pool[bestIdx];
      matched += 1;
      worstIoU = Math.min(worstIoU, best);
      maxCenterDeltaPx = Math.max(maxCenterDeltaPx, centerDelta(box, ref));
      if (ref.cls !== box.cls) classMismatches += 1;
      pool.splice(bestIdx, 1);
    }
  }

  return {
    expectedCount: reference.length,
    actualCount: instances.length,
    matched,
    worstIoU: matched ? worstIoU : 0,
    maxCenterDeltaPx,
    classMismatches,
    // SC-003: contagem exata, todas casadas, nenhuma classe divergente.
    pass:
      instances.length === reference.length &&
      matched === reference.length &&
      classMismatches === 0,
  };
}
