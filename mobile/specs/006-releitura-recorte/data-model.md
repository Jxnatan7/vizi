# Fase 1 — Modelo de dados

## Quadrado da releitura

O recorte que está na tela, do jeito que a tela o mostra. Vive e morre no
nativo, dentro da captura.

| Atributo | Descrição |
|---|---|
| imagem | 640×640, o recorte exibido encaixado e centrado, **preto** no resto |
| conteúdo | o retângulo que o recorte ocupa no quadrado, em pixels do modelo |

O encaixe é o da camada de vídeo: a menor das duas escalas, centrado. Como o
preview é quadrado, o conteúdo escalado ao lado da view é onde o recorte aparece
na tela — e as caixas da releitura caem sobre a imagem sem conversão.

**Nunca atravessa a fronteira** (princípio II).

---

## Releitura

O que o modelo encontra no quadrado. **É o resultado** (FR-002).

| Atributo | Descrição |
|---|---|
| instâncias | caixas no espaço do quadrado, com os coeficientes de máscara — só as que passam pela regra das bordas |
| protótipos | as máscaras dessas instâncias; **nunca atravessam** |
| contagem | o número de instâncias |
| fileiras | agrupadas pela `ShelfGeometry`, sem gravidade, em **índices de instância**; a partir de um livro |
| deitados | instâncias fora da tolerância de em pé |
| divisões | por fileira, normalizadas de 0 a 1 no recorte, com a banda vertical da fileira |

---

## Recorte sem a margem

A extensão dos livros da faixa dentro do recorte — as caixas da foto, antes da
margem —, de 0 a 1, com a origem no topo. **Medida pelo `PlaneRectifier`**, nos
dois caminhos, contra a extensão real do recorte: no recuo de só rotação a
borda da foto pode cortar a margem de um lado, e deduzi-la do `cropMargin`
apertaria aquele lado (R32).

**Regra das bordas:** uma instância conta quando

```
área da caixa dentro do recorte sem a margem  ≥  rereadMembership × área da caixa
```

Com 0,5, é a maior parte da caixa. Caixa sem área não conta.

---

## Origem da contagem

`'reread'` ou `'photo'`. Vai no resultado e na entrada do histórico.

| Origem | Quando |
|---|---|
| `'reread'` | havia recorte, `reread` ligado e a releitura terminou |
| `'photo'` | não havia recorte na tela; ou `reread` desligado; ou a releitura falhou |

Com `'photo'`, o resultado é exatamente o da 005: a leitura da foto, filtrada
pela faixa.

---

## O que o overlay está mostrando

O `ResultStore` passa a saber quem publicou.

| Estado | Quem escreve | Como o overlay desenha |
|---|---|---|
| ao vivo | a inferência a cada frame (`publish`) | membros da faixa, acima do `minConfidence` |
| resultado | a captura (`publishOverriding`) | **a lista como está** — sem faixa, sem limiar de aparência (FR-005) |
| vazio | `clear`, na volta e no fim da sessão | nada, até o primeiro frame ao vivo |

Trocar o estilo força o próximo desenho, em qualquer estado (FR-006).

---

## Política — `CaptureOptions`

| Campo | Inicial | O que decide |
|---|---|---|
| `reread` | `true` | a releitura existe; desligada, o resultado é a leitura da foto, como na 005 |
| `rereadMembership` | 0,5 | a fração da caixa que precisa estar no recorte sem a margem; **decisão adiada**, ajustar pelo SC-003 |

As fileiras e as divisões da releitura usam os campos que já existem:
`geometry` (vão entre fileiras, tolerância de em pé) e `dividerEdgeMargin`. O
`minInstancesForGeometry` não entra: ele existe para o quadrilátero, que a
releitura não estima. Os limiares de detecção são os da sessão, como na foto.

No Swift, os defaults dos campos novos são **inválidos de propósito**, como os
da T037 da 004: `reread` falso e `rereadMembership` 2, que não deixa nenhuma
caixa passar.

---

## Entrada de histórico

| Atributo | Descrição |
|---|---|
| `countSource` | novo — a origem da contagem salva. Ausente nas entradas de antes da 006, que eram da foto |

O resto não muda. A imagem salva continua sendo a que está na tela.
