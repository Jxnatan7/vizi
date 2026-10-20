# Contrato — a fronteira da coleta

```ts
// módulo nativo — funções novas
startCollection(options: CollectionOptions): Promise<CollectionState>
stopCollection(): Promise<CollectionState>
getCollectionState(): CollectionState            // síncrona: a tela monta sabendo

markFrame(): Promise<MarkReceipt>
answerItem(itemId: string, count: number | null): Promise<void>
resumeLive(): Promise<void>

listCollections(): Promise<CollectionSummary[]>
renameCollection(id: string, name: string): Promise<void>
deleteCollection(id: string): Promise<void>
exportCollection(id: string): Promise<ExportOutcome>

// evento novo — só em mudança discreta, nunca por quadro
onCollectionChange(state: CollectionState): void

// assinatura que não muda; o retorno ganha dois campos
capture(options: CaptureOptions): Promise<CaptureResult>
```

## Tipos

```ts
/** Política da coleta (princípio IV) e as políticas em vigor, para o registro. */
type CollectionOptions = {
  /** Até que confiança gravar. Usa-se o menor entre este e o limiar da sessão. */
  minScore: number;
  /** Abaixo disto de espaço livre, marcar é recusado e a captura não é gravada. */
  minFreeBytes: number;
  /** Qualidade de todas as imagens da coleta, de 0 a 1. */
  jpegQuality: number;
  /**
   * DEFAULT_SESSION, DEFAULT_CAPTURE, DEFAULT_BAND, DEFAULT_OVERLAY e
   * DEFAULT_COLLECTION, como estão. Gravadas sem interpretar.
   */
  policies: Record<string, unknown>;
};

type CollectionState = {
  open: boolean;
  /** Ausentes com a coleta fechada. */
  id?: string;
  startedAt?: number;
  marks: number;
  captures: number;
  answered: number;
  bytes: number;
  /** Abaixo de `minFreeBytes` na última conferência. */
  lowSpace: boolean;
  /** O último item que não conseguiu ser gravado, e por quê. */
  lastError?: string;
};

/** O que `markFrame` devolve, depois de o quadro estar parado na tela. */
type MarkReceipt = {
  itemId: string;
  /** A mediana da faixa no toque; null com a faixa desligada. */
  displayedCount: number | null;
  /** As detecções do quadro que existem e estão na faixa. */
  frameCount: number;
};

type CollectionSummary = {
  id: string;
  name: string | null;
  startedAt: number;
  endedAt: number | null;
  /** A aberta aparece na lista, sem exportar. */
  open: boolean;
  endReason: 'stopped' | 'background' | 'recovered' | null;
  marks: number;
  captures: number;
  answered: number;
  bytes: number;
  exportedAt: number | null;
};

type ExportOutcome = {
  /** Relativo à pasta de documentos — o absoluto muda a cada reinstalação. */
  file: string;
  bytes: number;
  /** false quando a pessoa fechou o menu sem compartilhar. O zip fica. */
  shared: boolean;
};
```

## `CaptureResult` — campos novos

| Campo | Regra |
|---|---|
| `collectionItemId` | o item gravado para esta captura, ou `null` sem coleta aberta ou sem gravação |
| `collectionSkipped` | `'space'` quando a coleta estava aberta e a captura não foi gravada por falta de espaço; `null` nos outros casos |

Nenhum outro campo muda, e nenhum valor muda com a coleta ligada (FR-003).

## Comportamento

| Chamada | Pré-condição | Efeito | Recusa com |
|---|---|---|---|
| `startCollection` | coleta fechada | abre a sessão, grava o `session.json` | — (aberta: devolve o estado atual) |
| `stopCollection` | — | espera a fila, fecha; sem itens, apaga | — (fechada: devolve o estado) |
| `markFrame` | coleta aberta, câmera rodando, ao vivo | pede o próximo quadro, congela nele, grava em segundo plano; resolve com o quadro parado | `closed`, `camera`, `busy` (captura em andamento, resultado ou quadro parado), `space` |
| `answerItem` | `itemId` é o item à espera | grava a resposta depois do item; `null` = pulou | `stale` (não é o item à espera) |
| `resumeLive` | quadro parado | solta o congelamento e a pausa, limpa as caixas do quadro, destrava a faixa, libera o item à espera | — (sem quadro parado: nada) |
| `listCollections` | — | as sessões, mais recente primeiro | — |
| `renameCollection` | sessão fechada | grava o nome | `open`, `missing` |
| `deleteCollection` | sessão fechada | apaga a pasta e o zip | `open`, `missing` |
| `exportCollection` | sessão fechada | copia o `FORMAT.md`, gera o zip, abre o menu de compartilhar | `open`, `missing`, `space` |

As recusas chegam como erro com o código no começo da mensagem
(`"busy: há um resultado na tela"`), para a tela dizer o que fazer.

**`dismissResult`** passa a liberar também o item à espera. **`stopSession`**
solta um quadro parado como solta um resultado, e o item fica sem resposta.

## O evento

`onCollectionChange` é emitido quando a sessão abre ou fecha, quando um item
termina de gravar, quando uma resposta é gravada e quando o espaço cruza o
limite. Nunca por quadro. O tempo de sessão não vem por ele: o JS calcula a
partir de `startedAt` (R46).

## Regras invioláveis

1. **A coleta não muda o app.** Contagem, caixas, tempos e histórico iguais com
   ela ligada ou desligada.
2. **Imagem e detecções do mesmo quadro**, na marca e em cada leitura da
   captura.
3. **A lista gravada contém a do app.** Filtrada pelo limiar da sessão, é
   exatamente o que o app contou.
4. **Item inteiro ou nada.**
5. **Nenhum pixel atravessa.** O que volta são identificadores, contagens,
   bytes e caminhos relativos.
