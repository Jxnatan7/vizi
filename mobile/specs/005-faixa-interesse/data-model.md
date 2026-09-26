# Fase 1 — Modelo de dados

## Faixa

| Atributo | Descrição |
|---|---|
| modo | `off` · `horizontal` · `vertical` |
| centro | posição do centro no eixo em que a faixa anda, de 0 a 1 |
| espessura | fração da imagem nesse mesmo eixo, de 0 a 1 |

A horizontal é limitada em y e ocupa a largura toda; a vertical, o contrário.

As coordenadas são as da **imagem canônica**, que é ao mesmo tempo a entrada
do modelo e o que a tela mostra. Por isso uma faixa só serve ao ao vivo e à
captura: a foto passa pela mesma transformação.

**Invariantes ao soltar:** a faixa inteira dentro de [0, 1], e a espessura
acima da mínima. Durante o gesto, o elástico deixa passar um pouco; ao soltar,
a mola traz de volta.

**Desligada**, centro e espessura não valem nada: a faixa é a moldura.

---

## Última faixa ligada

Guardada quando a faixa desliga. Religar pela cápsula volta a ela (FR-019); se a
orientação escolhida for a outra, vira mantendo centro e espessura como fração.

Some com a sessão.

---

## Regra de pertença

Uma detecção pertence à faixa quando

```
sobreposição entre a caixa e a faixa, no eixo limitado
    ≥ membership × extensão da caixa nesse eixo
```

Com `membership` = 0,5, é a maior parte da caixa. Desligada, tudo pertence.

**A caixa, não a máscara.** A faixa é grosseira perto da precisão de uma
máscara, e a caixa já está pronta em todo frame. Máscara custaria um produto de
matrizes por objeto para decidir algo que a caixa decide igual.

---

## Política da faixa — `SessionOptions.band`

Comportamento. Chega com a sessão, e a sessão começa por ela (R26).

| Campo | Inicial | O que decide |
|---|---|---|
| `defaultThickness` | 1/3 | espessura no começo da sessão e ao voltar ao centro — a linha do meio da grade 3×3 |
| `minThickness` | 0,10 | o mínimo; **decisão adiada**, ajustar no aparelho |
| `membership` | 0,5 | a fração da caixa que precisa estar dentro |
| `flipHysteresisDegrees` | 15 | folga em torno da diagonal para virar |
| `offMargin` | 0,04 | quanto as duas bordas passam da imagem para desligar |
| `rubberBand` | 0,35 | quanto do excesso aparece ao puxar além do limite |
| `startSlopPoints` | 6 | quanto o dedo anda antes de o gesto começar — abaixo disso é toque |
| `edgeGrabPoints` | 22 | meia altura da área de agarrar uma borda: 44 pt no total, o mínimo do iOS |
| `countWindowMs` | 500 | janela da mediana da contagem |
| `springResponse` | 0,35 s | tempo da mola |
| `springDamping` | 0,85 | abaixo de 1 a mola passa um pouco e volta — é o que dá peso |
| `haptics` | `true` | retorno tátil |

No Swift, os defaults são **inválidos de propósito**, como os da T037 da 004:
zerados, a faixa nasce sem espessura, e o defeito aparece na primeira sessão em
vez de rodar com um valor plausível e defasado.

---

## Aparência — `OverlayStyle`

Pela regra da 003: aparência só no `OverlayStyle`.

| Campo | Inicial |
|---|---|
| `bandDimOpacity` | 0,55 |
| `bandEdgeColor` | `#FFFFFF` |
| `bandEdgeWidth` | 1,5 pt |
| `bandHandleLength` | 28 pt |
| `bandHandleThickness` | 5 pt |
| `bandCountFontSize` | 13 pt |

---

## Transições de modo

| de | para | por |
|---|---|---|
| desligada | horizontal ou vertical | cápsula — volta à última faixa ligada · dois dedos — nasce entre eles, o eixo decide |
| horizontal | vertical, e vice-versa | cápsula — mantém centro e espessura · eixo dos dedos — refaz entre os dedos |
| horizontal ou vertical | desligada | cápsula · dedos além da imagem |
| horizontal ou vertical | a mesma, no centro, espessura padrão | dois toques na faixa |
| qualquer | horizontal, centro, espessura padrão | começo de sessão |

Toda transição é animada (FR-017) e dispara `onBandChange` ao terminar.

---

## Estados do gesto

Só com a faixa ligada, salvo a criação por dois dedos.

| estado | entra quando | faz |
|---|---|---|
| parado | — | — |
| um dedo · mover | um dedo anda além da folga, fora das bordas | move a faixa no eixo livre |
| um dedo · borda | um dedo anda além da folga sobre uma borda | move só aquela borda |
| dois dedos | pousa o segundo dedo, de qualquer estado | pinça em torno do ponto médio; o eixo decide a orientação |
| de volta a um dedo | um dos dois dedos levanta | segue como "mover" com o dedo que ficou, sem salto |

---

## Evento `onBandChange`

| Campo | |
|---|---|
| `mode` | `off` · `horizontal` · `vertical` |
| `center`, `thickness` | de 0 a 1 |

Dispara só em mudança discreta: fim de gesto que mudou algo, troca de modo,
volta ao centro, começo de sessão. **Nunca durante o arrasto.**

---

## `CaptureResult`

| Campo novo | |
|---|---|
| `outsideBandCount` | detecções da foto descartadas pela faixa. Com `count` zero e isto maior que zero, a tela diz "nenhum livro na faixa" em vez de "nenhum livro" |

---

## Apresentação

| | |
|---|---|
| oculta | durante a captura e no resultado; o reconhecedor também desliga (FR-020) |
| visível | no resto do tempo em que a sessão roda — inclusive desligada, quando só a cápsula aparece |
