# Contrato — captura e resultado

```ts
// módulo nativo
capture(options: CaptureOptions): Promise<CaptureResult>
dismissResult(): Promise<void>
saveResult(options: SaveResultOptions): Promise<SavedImage>

// src/history/store.ts — o índice é do TypeScript
saveResult(result: CaptureResult, capturedAt: number): Promise<HistoryEntry>
listEntries(): Promise<HistoryEntry[]>
```

O `saveResult` nativo grava só a imagem. Quem monta a entrada e mantém o
índice é o TypeScript: é metadado, e o nativo não precisa saber o que é um
histórico.

## `CaptureOptions` — política, vinda do TypeScript

| Campo | Regra |
|---|---|
| `cropMargin` | margem em volta da faixa, como fração |
| `minInstancesForGeometry` | abaixo disto, nem tenta endireitar |
| `minGeometryConfidence` | 0 a 1, comparado com a confiança da R15 |
| `approachMs` | aproximação que começa no toque, antes da foto (FR-009) |
| `transitionMs` | endireitamento, a partir do resultado pronto, e a volta |
| `diagnostics` | mostra horizonte, pontos de fuga e recorte em vez do resultado |
| `geometry` | tolerância de em pé, vão entre fileiras, mínimo por fileira, limites e pesos da confiança |
| `dividerEdgeMargin` | divisões mais perto que isto das bordas do recorte são descartadas |

Os limiares de detecção **não** estão aqui: a foto usa os da sessão
(`SessionOptions`), os mesmos do ao vivo. É o que mantém o SC-004 comparando
contagens feitas com a mesma régua.

## `CaptureResult` — o que atravessa

| Campo | Regra |
|---|---|
| `count` | a contagem |
| `straightened` | se a correção foi aplicada |
| `declineReason` | texto legível quando não foi (**FR-011**) |
| `geometryConfidence` | 0 a 1: a confiança da R15, a que o limiar compara |
| `azimuthConfidence` | 0 a 1: nitidez do cruzamento entre a reta das bases e o horizonte, para diagnóstico |
| `shelves` | por fileira: contagem, divisões e banda vertical, normalizadas de 0 a 1 no resultado |
| `shelfCount`, `lyingCount`, `usedGravity` | diagnóstico da geometria |
| `azimuthScores` | a varredura de azimute, 90 números — só no diagnóstico |
| `imageId` | **identificador, não pixels** |
| `elapsedMs` | só a foto: troca de formato, captura e restauração |
| `readyMs` | do toque ao resultado pronto; o final aparece em `readyMs + transitionMs` (SC-001) |
| `photoWidth`, `photoHeight` | dimensões da foto |

**`imageId` é o ponto deste contrato.** A foto em resolução máxima são dezenas
de megabytes. Ela fica no nativo; o JavaScript recebe um identificador e a view
nativa sabe o que desenhar. O princípio II num caso em que violá-lo seria
tentador — é só uma imagem, e é só uma vez.

O identificador aponta para o resultado **exibido**, guardado no nativo até o
`dismissResult`, o fim da sessão ou a próxima captura. É ele que o `saveResult`
grava.

## Histórico

| `SaveResultOptions` | |
|---|---|
| `quality` | qualidade do JPEG, de 0 a 1 |

| `SavedImage` | |
|---|---|
| `id` | o `imageId` da captura |
| `file` | caminho **relativo** à pasta de documentos |
| `width`, `height`, `bytes` | da imagem gravada |

| `HistoryEntry` | |
|---|---|
| `id`, `file`, `width`, `height` | do `SavedImage` |
| `count`, `straightened` | do `CaptureResult` |
| `capturedAt` | milissegundos desde a época |

## Regras invioláveis

1. **Nenhum pixel atravessa.** Nem da foto, nem das máscaras, nem do resultado.
   O histórico exibe a imagem pelo `<Image>`, que a lê do arquivo no nativo.
2. **A transição começa no toque** (FR-009), antes de `capture` resolver.
   A promessa entrega o resultado; a animação não a espera.
3. **`dismissResult` devolve 60 fps** em menos de 500 ms (SC-005).
4. **Recusar é um desfecho válido**, não um erro. `straightened: false` com
   `declineReason` é sucesso.
5. **Caminho relativo, nunca absoluto.** O iOS troca o caminho do contêiner do
   app a cada reinstalação, e a reassinatura de 7 dias reinstala.
