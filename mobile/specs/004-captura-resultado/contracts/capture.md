# Contrato — captura e resultado

```ts
capture(options: CaptureOptions): Promise<CaptureResult>
dismissResult(): Promise<void>
saveResult(): Promise<HistoryEntry>
```

## `CaptureOptions` — política, vinda do TypeScript

| Campo | Regra |
|---|---|
| `cropMargin` | margem em volta da faixa, como fração |
| `minInstancesForGeometry` | abaixo disto, nem tenta endireitar |
| `minGeometryConfidence` | 0 a 1 |
| `transitionMs` | duração da animação |

## `CaptureResult` — o que atravessa

| Campo | Regra |
|---|---|
| `count` | a contagem |
| `straightened` | se a correção foi aplicada |
| `declineReason` | texto legível quando não foi (**FR-011**) |
| `geometryConfidence` | 0 a 1, para diagnóstico |
| `dividers` | posições das divisões, normalizadas de 0 a 1 |
| `imageId` | **identificador, não pixels** |
| `elapsedMs` | do toque ao resultado, para o SC-001 |

**`imageId` é o ponto deste contrato.** A foto em resolução máxima são dezenas
de megabytes. Ela fica no nativo; o JavaScript recebe um identificador e a view
nativa sabe o que desenhar. O princípio II num caso em que violá-lo seria
tentador — é só uma imagem, e é só uma vez.

## Regras invioláveis

1. **Nenhum pixel atravessa.** Nem da foto, nem das máscaras, nem do resultado.
2. **A transição começa no toque** (FR-009), antes de `capture` resolver.
   A promessa entrega o resultado; a animação não a espera.
3. **`dismissResult` devolve 60 fps** em menos de 500 ms (SC-005).
4. **Recusar é um desfecho válido**, não um erro. `straightened: false` com
   `declineReason` é sucesso.
