# Contrato — releitura do recorte

```ts
// módulo nativo — a assinatura não muda
capture(options: CaptureOptions): Promise<CaptureResult>
dismissResult(): Promise<void>

// src/history/store.ts
saveResult(result: CaptureResult, capturedAt: number): Promise<HistoryEntry>
```

```ts
/** De qual leitura veio a contagem. */
type CountSource = 'reread' | 'photo';
```

## `CaptureOptions` — campos novos

| Campo | Regra |
|---|---|
| `reread` | liga a releitura; desligada, o resultado é a leitura da foto |
| `rereadMembership` | 0 a 1: fração da área da caixa que precisa estar no recorte sem a margem |

## `CaptureResult`

**Campos novos**

| Campo | Regra |
|---|---|
| `countSource` | `'reread'` quando a releitura produziu o resultado; `'photo'` quando não houve recorte, `reread` estava desligado ou a releitura falhou |
| `rereadMs` | quanto a releitura custou: montar o quadrado, inferir, filtrar e agrupar. Zero sem releitura |

**Campos que passam a vir da releitura** quando `countSource` é `'reread'`

| Campo | Regra |
|---|---|
| `count` | as caixas que passaram pela regra das bordas — **as mesmas que aparecem na tela** |
| `shelves` | fileiras da releitura: contagem, divisões e banda vertical, normalizadas no recorte |
| `shelfCount`, `lyingCount` | da releitura |

**Campo que muda de ponto de medida**

| Campo | Regra |
|---|---|
| `readyMs` | do toque ao resultado **na tela**, antes da releitura. O final continua aparecendo em `readyMs + transitionMs` |

**Continuam da foto**, venha a contagem de onde vier: `straightened`,
`declineReason`, `geometryConfidence`, `azimuthConfidence`, `usedGravity`,
`azimuthScores` e `outsideBandCount`. Descrevem como a imagem foi endireitada e o
que a faixa deixou de fora.

## `HistoryEntry`

| Campo novo | Regra |
|---|---|
| `countSource` | a origem da contagem salva; ausente nas entradas de antes da 006 |

## Regras invioláveis

1. **A releitura lê o que está na tela.** O recorte exibido, encaixado no
   quadrado, centrado, com preto no resto. Nada de girar, esticar ou
   preencher de outro jeito.
2. **Só a releitura é o resultado** quando ela existe. A foto acha os livros,
   endireita e recorta.
3. **Caixa na tela é caixa contada**, e vice-versa. No resultado, o overlay não
   aplica a faixa nem o limiar de aparência.
4. **Nada do resultado sobrevive à volta.** Nem caixa, nem máscara, nem
   divisão — inclusive se a releitura terminar depois.
5. **Nenhum pixel atravessa.** O quadrado e as máscaras da releitura ficam no
   nativo, como a foto.
