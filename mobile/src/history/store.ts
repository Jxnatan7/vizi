import { Directory, File, Paths } from 'expo-file-system';

import {
  ViziVision,
  type CaptureResult,
  type HistoryEntry,
  type SaveResultOptions,
} from '../../modules/vizi-vision';

/**
 * Histórico local (US4): imagens em arquivo, índice em JSON.
 *
 * A imagem é gravada pelo nativo e nunca passa por aqui — o que atravessa é o
 * caminho (princípio II). O índice guarda só metadado: com a imagem dentro,
 * cresceria sem limite e a listagem ficaria lenta (data-model).
 */

/** Política da gravação. Vive aqui, não no Swift — princípio IV. */
export const DEFAULT_SAVE: SaveResultOptions = {
  /**
   * JPEG quase sem perda. As faixas salvas são o material para medir a
   * releitura no Colab, e artefato de compressão ali viraria ruído na medida.
   */
  quality: 0.9,
};

type Index = { version: 1; entries: HistoryEntry[] };

/** A mesma pasta em que o nativo grava as imagens. */
const folder = () => new Directory(Paths.document, 'history');
const indexFile = () => new File(folder(), 'index.json');

/** Mais recente primeiro. Sem índice ainda não há histórico — não é erro. */
export async function listEntries(): Promise<HistoryEntry[]> {
  const { entries } = await read();
  return [...entries].sort((a, b) => b.capturedAt - a.capturedAt);
}

/**
 * Leitura e escrita do índice acontecem em fila: dois toques seguidos em
 * "salvar" leriam o mesmo índice, e a segunda escrita apagaria a primeira.
 */
let pending: Promise<unknown> = Promise.resolve();

/** Grava o resultado que está na tela e o acrescenta ao índice (FR-013). */
export function saveResult(result: CaptureResult, capturedAt: number): Promise<HistoryEntry> {
  const run = pending.then(async () => {
    const saved = await ViziVision.saveResult(DEFAULT_SAVE);
    const entry: HistoryEntry = {
      id: saved.id,
      file: saved.file,
      count: result.count,
      // De qual leitura veio a contagem (spec 006, FR-009). Sem isto, o índice
      // misturaria contagens da foto e da releitura sem dizer qual é qual.
      countSource: result.countSource,
      straightened: result.straightened,
      capturedAt,
      width: saved.width,
      height: saved.height,
    };
    const { entries } = await read();
    write({ version: 1, entries: [...entries.filter((e) => e.id !== entry.id), entry] });
    return entry;
  });
  pending = run.catch(() => undefined);
  return run;
}

/** O `uri` que o `<Image>` carrega: o pixel vai do arquivo à tela pelo nativo. */
export function imageUri(entry: HistoryEntry): string {
  return new File(Paths.document, ...entry.file.split('/')).uri;
}

async function read(): Promise<Index> {
  const file = indexFile();
  if (!file.exists) return { version: 1, entries: [] };
  const text = await file.text();
  try {
    const parsed = JSON.parse(text) as Partial<Index>;
    if (!Array.isArray(parsed.entries)) throw new Error('sem lista de entradas');
    return { version: 1, entries: parsed.entries };
  } catch (e) {
    // Ilegível não vira vazio: recomeçar em silêncio apagaria o histórico na
    // próxima gravação.
    throw new Error(`Índice do histórico ilegível: ${String(e)}`);
  }
}

function write(next: Index) {
  const dir = folder();
  if (!dir.exists) dir.create({ intermediates: true, idempotent: true });
  indexFile().write(JSON.stringify(next));
}
