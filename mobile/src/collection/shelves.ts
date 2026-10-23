import { useCallback, useEffect, useState } from 'react';
import { File, Paths } from 'expo-file-system';

import type {
  CollectionLight, CollectionTags, ShelfAngle, ShelfDistance, ShelfSnapshot,
} from '../../modules/vizi-vision';

/**
 * As prateleiras da casa e o guia de variações (spec 008, R49).
 *
 * São do app, não da sessão: sobrevivem às sessões apagadas, que é o que a
 * pessoa faz depois de mandar as fotos para o Roboflow (FR-012). O nativo não
 * sabe que elas existem — recebe a escolha da câmera como `tags`.
 */

export type Shelf = {
  /** Gerado ao cadastrar e nunca muda: o guia e as sessões seguem por ele. */
  id: string;
  name: string;
  /** O inventário, pela regra de contagem (`models/regra-de-contagem.md`). */
  count: number;
  createdAt: number;
};

/** Uma célula do guia: distância e ângulo, na chave do formato do zip. */
export type Cell = `${ShelfDistance}-${ShelfAngle}`;

export type CellCounts = Partial<Record<Cell, number>>;

export type ShelfStore = {
  version: 1;
  shelves: Shelf[];
  /** Por prateleira e luz, quantas capturas de treino cada célula tem. */
  coverage: Record<string, Record<CollectionLight, CellCounts>>;
  /** Fotos sem livros, por luz. */
  background: Record<CollectionLight, number>;
};

function empty(): ShelfStore {
  return { version: 1, shelves: [], coverage: {}, background: { day: 0, night: 0 } };
}

const storeFile = () => new File(Paths.document, 'shelves.json');

export function cellOf(distance: ShelfDistance, angle: ShelfAngle): Cell {
  return `${distance}-${angle}`;
}

/** A prateleira como vai para o item: o número de hoje fica gravado com ele. */
export function snapshot(shelf: Shelf): ShelfSnapshot {
  return { id: shelf.id, name: shelf.name, count: shelf.count };
}

/** As células de uma prateleira numa luz. Vazio quando ainda não tem nenhuma. */
export function cellsOf(store: ShelfStore, shelfId: string, light: CollectionLight): CellCounts {
  return store.coverage[shelfId]?.[light] ?? {};
}

/** Quantas das nove células já têm captura. */
export function doneCells(counts: CellCounts): number {
  return Object.values(counts).filter((n) => (n ?? 0) > 0).length;
}

// ── Leitura e escrita ─────────────────────────────────────────────────────

async function read(): Promise<ShelfStore> {
  const file = storeFile();
  if (!file.exists) return empty();
  const text = await file.text();
  let parsed: Partial<ShelfStore>;
  try {
    parsed = JSON.parse(text) as Partial<ShelfStore>;
  } catch (e) {
    throw new Error(`O arquivo das prateleiras está ilegível: ${String(e)}`);
  }
  // Uma versão que o app não conhece não é sobrescrita: gravar por cima
  // apagaria o que um app mais novo guardou (data-model).
  if (parsed.version !== 1 || !Array.isArray(parsed.shelves)) {
    throw new Error(`O arquivo das prateleiras tem uma versão que este app não lê (${String(parsed.version)}).`);
  }
  return {
    version: 1,
    shelves: parsed.shelves,
    coverage: parsed.coverage ?? {},
    background: { day: parsed.background?.day ?? 0, night: parsed.background?.night ?? 0 },
  };
}

/**
 * Uma escrita por vez, como o índice do histórico: duas capturas seguidas
 * leriam o mesmo arquivo, e a segunda escrita apagaria a primeira.
 */
let pending: Promise<unknown> = Promise.resolve();

let cache: ShelfStore | null = null;
const listeners = new Set<(store: ShelfStore) => void>();

function publish(store: ShelfStore) {
  cache = store;
  for (const listener of listeners) listener(store);
}

function mutate(change: (store: ShelfStore) => ShelfStore): Promise<ShelfStore> {
  const run = pending.then(async () => {
    const next = change(await read());
    storeFile().write(JSON.stringify(next));
    publish(next);
    return next;
  });
  pending = run.catch(() => undefined);
  return run;
}

function sameName(a: string, b: string): boolean {
  return a.trim().toLocaleLowerCase('pt-BR') === b.trim().toLocaleLowerCase('pt-BR');
}

function checkName(store: ShelfStore, name: string, except?: string) {
  if (!name.trim()) throw new Error('Dê um nome à prateleira.');
  if (store.shelves.some((s) => s.id !== except && sameName(s.name, name))) {
    throw new Error(`Já existe uma prateleira "${name.trim()}".`);
  }
}

function checkCount(count: number) {
  if (!Number.isInteger(count) || count < 0) throw new Error('O número de livros é um inteiro, de 0 para cima.');
}

// ── Ações ─────────────────────────────────────────────────────────────────

export function addShelf(name: string, count: number): Promise<ShelfStore> {
  return mutate((store) => {
    checkName(store, name);
    checkCount(count);
    const id = `s-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
    return { ...store, shelves: [...store.shelves, { id, name: name.trim(), count, createdAt: Date.now() }] };
  });
}

export function renameShelf(id: string, name: string): Promise<ShelfStore> {
  return mutate((store) => {
    checkName(store, name, id);
    return { ...store, shelves: store.shelves.map((s) => (s.id === id ? { ...s, name: name.trim() } : s)) };
  });
}

/** Vale dali em diante: os itens já gravados guardam o número do momento. */
export function setShelfCount(id: string, count: number): Promise<ShelfStore> {
  return mutate((store) => {
    checkCount(count);
    return { ...store, shelves: store.shelves.map((s) => (s.id === id ? { ...s, count } : s)) };
  });
}

/** Leva o contador junto. As sessões gravadas guardam o nome em `tags`. */
export function removeShelf(id: string): Promise<ShelfStore> {
  return mutate((store) => {
    const coverage = { ...store.coverage };
    delete coverage[id];
    return { ...store, shelves: store.shelves.filter((s) => s.id !== id), coverage };
  });
}

/**
 * Uma captura de treino gravada (FR-012). Sobe a célula da prateleira, ou as
 * fotos sem livros; uma prateleira apagada no meio do caminho não volta.
 */
export function recordTrainingCapture(tags: CollectionTags, light: CollectionLight): Promise<ShelfStore> {
  return mutate((store) => {
    if (tags.background) {
      return { ...store, background: { ...store.background, [light]: store.background[light] + 1 } };
    }
    const { shelf, distance, angle } = tags;
    if (!shelf || !distance || !angle || !store.shelves.some((s) => s.id === shelf.id)) return store;
    const cell = cellOf(distance, angle);
    const byLight = store.coverage[shelf.id] ?? { day: {}, night: {} };
    const counts = { ...byLight[light], [cell]: (byLight[light][cell] ?? 0) + 1 };
    return { ...store, coverage: { ...store.coverage, [shelf.id]: { ...byLight, [light]: counts } } };
  });
}

/**
 * As prateleiras e o guia, iguais em todas as telas: a câmera e a Medição
 * vivem montadas ao mesmo tempo, e uma captura na primeira muda a segunda.
 */
export function useShelves() {
  const [store, setStore] = useState<ShelfStore | null>(cache);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    listeners.add(setStore);
    if (!cache) {
      read()
        .then((loaded) => {
          if (!cache) publish(loaded);
          setError(null);
        })
        .catch((e) => setError(e instanceof Error ? e.message : String(e)));
    }
    return () => {
      listeners.delete(setStore);
    };
  }, []);

  /** Roda a ação e guarda o erro para a tela; resolve com `true` quando deu certo. */
  const run = useCallback(async (action: () => Promise<unknown>): Promise<boolean> => {
    try {
      await action();
      setError(null);
      return true;
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      return false;
    }
  }, []);

  return { store, error, run };
}
