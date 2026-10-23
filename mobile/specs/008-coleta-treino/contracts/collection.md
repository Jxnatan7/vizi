# Contrato — o que muda na fronteira da coleta

Só a diferença para o [contrato da 007](../../007-modo-coleta/contracts/collection.md).
Tudo o que não está aqui continua como lá.

```ts
// assinaturas que mudam — um argumento novo, sempre enviado (null quando não há)
capture(options: CaptureOptions, tags: CollectionTags | null): Promise<CaptureResult>
markFrame(tags: CollectionTags | null): Promise<MarkReceipt>

// assinatura igual; CollectionOptions ganha `session`
startCollection(options: CollectionOptions): Promise<CollectionState>
```

## Tipos

```ts
/** O que a sessão é. Gravado no topo do `session.json` sem interpretar. */
type CollectionSessionInfo =
  | { purpose: 'training'; light: 'day' | 'night'; shelves: ShelfSnapshot[] }
  | { purpose: 'exam'; light: null; shelves: ShelfSnapshot[] };

/** Uma prateleira como estava no instante: o número muda com o tempo. */
type ShelfSnapshot = { id: string; name: string; count: number };

/** A escolha na câmera no instante do toque. Gravada em `item.json` como `tags`. */
type CollectionTags = {
  shelf: ShelfSnapshot | null;
  /** Foto sem livros: sem prateleira, distância nem ângulo. */
  background: boolean;
  distance: 'near' | 'mid' | 'far' | null;
  angle: 'left' | 'front' | 'right' | null;
};

type CollectionOptions = {
  minScore: number;
  minFreeBytes: number;
  jpegQuality: number;
  policies: Record<string, unknown>;
  /** Novo. */
  session: CollectionSessionInfo;
};

/** Campos novos, ausentes com a coleta fechada. */
type CollectionState = {
  // … os da 007
  purpose?: 'training' | 'exam' | null;   // null: sessão anterior à 008
  light?: 'day' | 'night' | null;
};

/** Campos novos. */
type CollectionSummary = {
  // … os da 007
  purpose: 'training' | 'exam' | null;
  light: 'day' | 'night' | null;
};
```

## Comportamento

| Chamada | O que muda |
|---|---|
| `startCollection` | grava `purpose`, `light` e `shelves` de `session` no topo do `session.json`; o estado passa a trazer `purpose` e `light` |
| `capture` | guarda `tags` no instante do toque, com a faixa; o item da coleta grava `tags` como chegou. Sem coleta aberta, `tags` é ignorado |
| `markFrame` | o mesmo, para a marca |
| `listCollections` | cada sessão traz `purpose` e `light`, lidos do `session.json`; `null` nas anteriores à 008 |
| gravação do recorte | o `crop.jpg` sai composto sobre preto (research, R50) |

O nativo **não valida** `tags` nem `session`: grava o que recebeu. Quem decide
o que é uma prateleira, uma distância ou um ângulo é o TypeScript (princípio
IV).

## O que fica no TypeScript

| O quê | Onde |
|---|---|
| Treino ou prova, e a luz | escolhidos ao ligar, enviados em `session` |
| O modo rápido | `FAST_CAPTURE` sobre `DEFAULT_CAPTURE`, e `dismissResult` assim que o resultado chega (R48) |
| Capturar sem escolha | o botão fica desligado; o nativo não sabe da regra (FR-003) |
| A pergunta da prova | `TruthPrompt` preenchido com `tags.shelf.count` |
| Prateleiras e guia | `Documents/shelves.json` ([data-model](../data-model.md)) |

## Regras invioláveis

As cinco da 007 continuam, e mais uma: **a escolha gravada é a do toque**. Ela
viaja como argumento da captura e da marca, e mudar a escolha depois do toque
não muda o item.
