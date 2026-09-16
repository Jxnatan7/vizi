import * as Clipboard from 'expo-clipboard';

import type { Session } from '../../modules/vizi-vision';

/**
 * Sessão → JSON → área de transferência.
 *
 * O objetivo é tornar a medição **versionável**: colar em
 * `specs/002-camera-telemetry/medicoes/` e o número deixa de depender de
 * alguém lembrar dele.
 */
export async function copySessionToClipboard(session: Session): Promise<number> {
  const json = JSON.stringify(session, null, 2);
  await Clipboard.setStringAsync(json);
  return json.length;
}

/** Avaliação do portão do marco, calculada sobre a sessão. */
export type GateVerdict = {
  label: string;
  pass: boolean;
  detail: string;
};

const ORDER = ['nominal', 'fair', 'serious', 'critical'];

export function evaluateGate(session: Session): GateVerdict[] {
  const s = session.samples;
  if (s.length < 4) {
    return [{ label: 'Amostras insuficientes', pass: false, detail: `${s.length} amostras` }];
  }

  // Comparar o começo com o fim é o que revela degradação: uma média sobre a
  // sessão inteira a esconderia.
  const head = s.slice(0, Math.max(1, Math.floor(s.length * 0.1)));
  const tail = s.slice(-Math.max(1, Math.floor(s.length * 0.1)));
  const med = (xs: number[]) => [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)] ?? 0;

  const inferHead = med(head.map((x) => x.inferMs));
  const inferTail = med(tail.map((x) => x.inferMs));
  const fpsHead = med(head.map((x) => x.fpsInferred));
  const fpsTail = med(tail.map((x) => x.fpsInferred));
  const e2e = med(s.map((x) => x.e2eMs));
  const worstThermal = s.reduce(
    (w, x) => (ORDER.indexOf(x.thermalState) > ORDER.indexOf(w) ? x.thermalState : w),
    'nominal',
  );
  const maxQueue = Math.max(...s.map((x) => x.queueDepth));
  const batteryDrop = session.batteryAtStart - session.batteryAtEnd;

  const growth = inferHead > 0 ? (inferTail - inferHead) / inferHead : 0;
  const fpsDrop = fpsHead > 0 ? (fpsHead - fpsTail) / fpsHead : 0;

  return [
    {
      label: 'SC-001 · térmico ≤ fair',
      pass: ORDER.indexOf(worstThermal) <= 1,
      detail: `pior: ${worstThermal}`,
    },
    {
      label: 'SC-002 · latência +50% máx',
      pass: growth <= 0.5,
      detail: `${inferHead.toFixed(2)} → ${inferTail.toFixed(2)} ms (${(growth * 100).toFixed(0)}%)`,
    },
    {
      label: 'SC-003 · fps −20% máx',
      pass: fpsDrop <= 0.2,
      detail: `${fpsHead.toFixed(1)} → ${fpsTail.toFixed(1)} /s (${(fpsDrop * 100).toFixed(0)}%)`,
    },
    {
      label: 'SC-004 · fila ≤ 1',
      pass: maxQueue <= 1,
      detail: `máx ${maxQueue}`,
    },
    {
      label: 'SC-005 · e2e < 80 ms',
      pass: e2e < 80,
      detail: `${e2e.toFixed(1)} ms`,
    },
    {
      label: 'SC-007 · bateria',
      pass: true, // registrado, não julgado — não há alvo declarado
      detail: session.batteryAtStart < 0 ? '—' : `−${(batteryDrop * 100).toFixed(1)} pontos`,
    },
  ];
}
