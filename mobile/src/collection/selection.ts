import type {
  CollectionPurpose, CollectionTags, ShelfAngle, ShelfDistance,
} from '../../modules/vizi-vision';
import { ANGLES, DISTANCES } from './policy';
import { snapshot, type ShelfStore } from './shelves';

/**
 * A escolha na câmera (spec 008, data-model "A escolha na câmera"): o que a
 * próxima captura vai gravar como `tags`. Persiste de uma captura para a outra
 * e é esquecida quando a sessão fecha.
 */
export type TagSelection = {
  shelfId: string | null;
  /** "Sem livros": esquece a prateleira e a célula. */
  background: boolean;
  distance: ShelfDistance | null;
  angle: ShelfAngle | null;
};

export const EMPTY_SELECTION: TagSelection = { shelfId: null, background: false, distance: null, angle: null };

/**
 * O que vai para o item. `null` fora do modo ou numa sessão sem tipo — o
 * fluxo da 007. Uma prateleira apagada depois de escolhida não vai.
 */
export function tagsFor(
  selection: TagSelection, store: ShelfStore | null, purpose: CollectionPurpose | null,
): CollectionTags | null {
  if (!purpose) return null;
  if (purpose === 'training' && selection.background) {
    return { shelf: null, background: true, distance: null, angle: null };
  }
  const shelf = store?.shelves.find((s) => s.id === selection.shelfId);
  return {
    shelf: shelf ? snapshot(shelf) : null,
    background: false,
    // A prova não tem variação: só a prateleira inteira, de frente.
    distance: purpose === 'training' ? selection.distance : null,
    angle: purpose === 'training' ? selection.angle : null,
  };
}

/** O que falta escolher para capturar (FR-003), ou `null` quando nada falta. */
export function missingFor(tags: CollectionTags | null, purpose: CollectionPurpose | null): string | null {
  if (!purpose || !tags) return null;
  if (tags.background) return null;
  if (!tags.shelf) {
    return purpose === 'training' ? 'Escolha a prateleira, ou "sem livros".' : 'Escolha a prateleira.';
  }
  if (purpose === 'training' && (!tags.distance || !tags.angle)) {
    return 'Escolha a distância e o ângulo no guia.';
  }
  return null;
}

/** "sala 1 · perto · frente", "sem livros". Para o indicador e a nota. */
export function describeTags(tags: CollectionTags): string {
  if (tags.background) return 'sem livros';
  const parts = [tags.shelf?.name ?? 'sem prateleira'];
  const distance = DISTANCES.find((d) => d.key === tags.distance);
  const angle = ANGLES.find((a) => a.key === tags.angle);
  if (distance) parts.push(distance.label);
  if (angle) parts.push(angle.label);
  return parts.join(' · ');
}
