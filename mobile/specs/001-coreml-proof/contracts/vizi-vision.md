# Contrato — módulo `vizi-vision`

Este é **a fronteira** do princípio II. Tudo que atravessa entre nativo e
JavaScript passa por aqui, e nada além disto atravessa.

O contrato é definido pela forma dos dados, não pela sintaxe. A assinatura
abaixo é ilustrativa; o que vincula é a regra de cada campo.

```ts
loadModel(assetName: string): Promise<ModelInfo>

runBenchmark(options: {
  repetitions: number      // política vive em TS (princípio IV)
  warmupDiscard: number
  confidenceThreshold: number
}): Promise<Measurement>

unloadModel(): Promise<void>
```

## `ModelInfo`

Metadados lidos do próprio modelo. O JavaScript **não** os declara; recebe.

| Campo | Regra |
|-------|-------|
| `identifier` | nome da variante carregada |
| `inputShape` | dimensões esperadas, como o modelo as declara |
| `classes` | mapa índice → nome |
| `computeUnits` | unidades que o sistema autorizou, ou `"unavailable"` |

## `Measurement`

O único objeto de resultado. Corresponde à entidade *Registro de medição*.

| Campo | Regra |
|-------|-------|
| `repetitions`, `discarded` | ecoam o que foi pedido, para o resultado ser autoexplicativo |
| `firstRunMs` | latência da primeira execução, isolada |
| `modelMs` | `{ median, p95, min }` da execução do modelo — **é o que o portão vincula** |
| `cycleMs` | `{ median, p95, min }` do ciclo completo |
| `thermalState` | estado térmico no momento da sequência |
| `executionUnit` | onde o modelo rodou, ou `"unavailable"` com o motivo |
| `instances` | detecções decodificadas: classe, confiança, caixa |

## Regras invioláveis da fronteira

1. **Nenhum pixel atravessa.** A imagem de referência é carregada e consumida do
   lado nativo. O JavaScript nunca a vê.
2. **Nenhum tensor atravessa.** Saída crua e protótipos de máscara são
   decodificados no nativo. Para o JavaScript vai apenas `instances`.
3. **`Measurement` é pequeno por construção.** Dezenas de campos e dezenas de
   instâncias, na casa de um kilobyte. Se algum dia passar de 64 KB, o princípio
   II foi violado.
4. **Nenhuma constante de política vive no Swift.** Repetições, descarte e
   limiar chegam como parâmetro. O nativo não tem opinião sobre eles.
5. **`runBenchmark` não bloqueia a thread de interface.** Não há loop de desenho
   neste marco, mas estabelecer o precedente contrário custaria caro no marco 4.

## Nomes de saída são frágeis

O exportador gerou `var_1011` e `var_1049` — nomes automáticos, sem semântica,
que **mudam entre exports**. O código nativo não pode fixá-los. As saídas devem
ser resolvidas por forma: a de três dimensões é a detecção, a de quatro são os
protótipos.

Fixar o nome faria o app quebrar silenciosamente no próximo re-treino.

## Erros

Falhas retornam mensagem legível para exibição na tela (**FR-008**), não códigos
opacos. No aparelho não há console à mão, e essa string é a única pista que
chega ao desenvolvedor — lição herdada do protótipo web.
