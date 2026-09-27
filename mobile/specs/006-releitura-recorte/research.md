# Fase 0 — Pesquisa

Sete incógnitas, nenhuma sobre o modelo. A entrada é a mesma 640×640 de sempre;
o que precisa de cuidado é o caminho até ela e a volta dela para a tela.

A R31 é a que decide se o resultado mente: uma caixa escondida ou uma caixa de
outro espaço bastam para a contagem e a tela discordarem.

---

## R29 — Onde a releitura entra

**Decisão.** No fim do `capture`, depois do `showStill` e do `settle`. A
imagem vai para a tela exatamente como hoje; a transição começa; e só então a
releitura roda, na thread da captura. O resultado dela é publicado no overlay e
nas divisões num único bloco da thread de interface, **guardado pela época do
resultado**: se a captura já não for a atual, o bloco não faz nada.

O `readyMs` passa a ser medido antes da releitura, no instante em que o
resultado aparece — é o que o SC-001 da 004 sempre mediu, e o contrato diz que
o final aparece em `readyMs + transitionMs`. O custo da releitura vai em
`rereadMs`.

**Por quê.** É o que o autor pediu — "depois disso, no final do pipe, rode por
último". E é de graça: durante a transição o overlay está emprestado ao cartão
e não desenha, então a releitura tem 600 ms para terminar antes de alguém
poder ver o que ela publicou.

**A guarda.** Uma época muda a cada captura, volta e fim de sessão — é o
`dropResult` que a avança. A captura guarda a época em que começou; o bloco da
releitura e o `keepResult` só agem se ela ainda for a atual. Dispensado antes,
o bloco não publica; publicado antes, a volta limpa (R31), porque a limpeza da
volta roda na mesma fila, depois dele.

*Achado na revisão, 27/09:* a primeira versão guardava pelo `imageId`. Não
bastava: uma foto que chega depois do fim da sessão — a aba trocada no meio da
captura — chamava `keepResult` depois do `endResultState`, guardava o resultado
de novo e passava pela guarda. As divisões ficariam sobre o ao vivo da sessão
seguinte. Esse vazamento das divisões já existia na 005; a época o fecha junto.

**Alternativas.** Rodar antes do `showStill`: o resultado chegaria à tela uns
milissegundos mais tarde e as caixas já prontas — mas o pedido é "depois", e a
transição esconde o custo do mesmo jeito. Rodar em paralelo, fora da captura: a
promessa voltaria ao JavaScript sem a contagem que ele mostra.

**Como fechar.** `rereadMs` abaixo de `transitionMs` nas 10 capturas do SC-001.

---

## R30 — O quadrado

**Decisão.** Um método novo no `FrameTransform`: o recorte **exibido** — o
mesmo buffer que foi para a tela — encaixado em 640×640, centrado, sobre preto,
num buffer do pool que já existe. Ele devolve também o retângulo que o recorte
ocupa no quadrado, que é o que as contas das R32 e R33 usam.

O encaixe é o do `resizeAspect` da camada de vídeo: a menor das duas escalas,
centrado. Como o preview é quadrado, esse retângulo, escalado ao lado da view,
é exatamente onde o recorte aparece na tela.

A redução usa a amostragem de alta qualidade do Core Image. O recorte chega em
resolução cheia e encolhe mais de 4×; sem filtragem, as lombadas finas sairiam
serrilhadas, e a tela as mostra lisas.

**Por quê não o `transform`.** Ele normaliza a orientação girando toda imagem
mais larga que alta — a regra certa para a câmera, que entrega o sensor
deitado. Um recorte horizontal, que é o caso comum, entraria girado 90°, com os
livros deitados.

**O preto.** Decisão do autor, e a definição da entrada: é o fundo da
`PreviewView`, o que a tela mostra em volta do recorte. Por isso não vai para as
opções.

**Alternativas.** Montar o quadrado a partir da imagem retificada antes de
renderizar: um passo a menos, mas a entrada deixaria de ser *o que está na
tela* para ser uma imagem equivalente. Ler o buffer exibido deixa o FR-001
verdadeiro por construção.

**Como fechar.** Com as caixas ligadas, cada uma cai sobre o seu livro, e
nenhuma aparece girada ou deslocada.

---

## R31 — Desenhar o resultado como foi contado

**Decisão.** O `ResultStore` passa a saber se o que tem foi publicado pela
captura. Quando foi, o overlay desenha a lista **como está**: sem o filtro da
faixa e sem o `minConfidence` do estilo.

- **Sem a faixa**, porque ela vive nas coordenadas do frame ao vivo. Sobre o
  recorte, uma faixa arrastada para o alto da imagem apagaria tudo o que está
  no centro do quadrado. A faixa já agiu antes: foi ela que decidiu o recorte.
- **Sem o limiar de aparência**, porque a contagem usa o limiar de detecção
  (0,25) e o overlay só desenha a partir de 0,3. Ao vivo isso é legibilidade;
  no resultado seria uma caixa que conta e não aparece — o que o autor disse
  que não existe (FR-005).

Vale também para o recuo em que a imagem na tela é a canônica: a lista publicada
é a dos membros da faixa, e é a que conta.

**Dois ajustes que o resultado expõe.**

- **O estilo redesenha.** Hoje trocar o estilo só vale no próximo resultado
  publicado, e ao vivo isso é o próximo frame. No resultado não chegam frames:
  ligar e desligar caixas e máscaras não faria nada. O `style` ganha um
  `didSet` que força o desenho seguinte (FR-006).
- **A volta limpa o store.** `dismissResult` e `endResultState` esvaziam o
  `ResultStore` antes de soltar a pausa. Sem isso, as caixas da releitura
  apareceriam sobre a câmera ao vivo até o primeiro frame novo (FR-011).

**Alternativas.** Uma camada de overlay própria do resultado, presa à camada
`cutout` da transição, que se desentortaria junto com ela: mais bonito na
transição, mas outro desenhador de caixas e máscaras para manter igual ao
primeiro. Como o quadrado da releitura é o espaço do overlay que já existe, a
camada nova não compraria nada além da animação.

**Como fechar.** SC-002: contar as caixas na tela e comparar com o número. SC-007:
dez voltas, nenhuma caixa sobre o ao vivo.

---

## R32 — A regra das bordas

**Decisão.** O `PlaneRectifier` passa a devolver onde os livros ficam no
resultado — a extensão das caixas da faixa, antes da margem —, normalizada de 0
a 1 com a origem no topo. É o recorte sem a margem, **medido**. A releitura o
leva ao retângulo que o recorte ocupa no quadrado, e uma caixa conta quando
`rereadMembership` da sua **área** está lá dentro. Começa em 0,5: a maior parte,
como a regra da faixa.

**Por quê área, e não um eixo.** A faixa é limitada num eixo só; o recorte, nos
dois. Uma fatia de vizinho na faixa vertical sai pelo lado; um pedaço da
prateleira de cima, pelo alto. A área pega os dois com a mesma regra.

**Por quê medir, e não deduzir da margem.** A margem é uma fração `m` da
extensão dos livros, de cada lado, e no caminho endireitado dá para deduzir o
recorte sem ela: `[m/(1+2m), (1+m)/(1+2m)]` — o `CIPerspectiveCorrection` leva
o quadrilátero aos cantos de um retângulo e não corta nada. A primeira versão
fazia assim.

*Achado na revisão, 27/09:* no recuo de só rotação, o recorte é cortado pela
borda da imagem girada. Numa prateleira que atravessa a foto — o caso comum —
a margem some dos dois lados, e a dedução apertava o miolo em até 4,5% da
largura de cada lado: mais que uma lombada, e os livros das pontas deixariam de
contar. Medido contra a extensão real do recorte, o miolo é exato nos dois
caminhos.

**Como fechar.** SC-003: dez capturas da faixa vertical sobre uma coluna,
nenhuma fatia contada. Se falhar, a fração é o primeiro número a mexer.

---

## R33 — Fileiras e divisões da releitura

**Decisão.** A `ShelfGeometry.estimate` roda sobre as caixas que passaram pela
regra das bordas, com os protótipos da releitura e **sem gravidade**. Sem
gravidade ela usa o eixo médio das lombadas como vertical — e numa imagem
endireitada, ou só girada pela gravidade, esse eixo é a vertical de verdade. As
fileiras, os deitados e as regras de vão e tolerância de em pé são os mesmos
que o autor validou na 004, vindos das mesmas opções.

O mínimo de livros é **um**, não o `minInstancesForGeometry`. Aquele mínimo
existe para o quadrilátero, que a releitura não estima; com ele, uma prateleira
de três livros sairia sem fileira e sem divisões.

As divisões são a conta de hoje — o meio entre a borda direita de um livro e a
esquerda do vizinho, por fileira —, feita no quadrado e normalizada no recorte:
tirar o deslocamento do encaixe e dividir pelo tamanho que o recorte ocupa. É
o espaço em que a `PreviewView` já desenha as divisões. O `dividerEdgeMargin`
continua descartando as coladas na borda.

Como não dependem mais da homografia, as divisões aparecem também no recuo de
só rotação (FR-007).

**O defeito que a leitura achou.** `estimate` monta as lombadas com
`compactMap`, então uma máscara com menos de 20 pixels ativos some da lista, e
as posições deslocam. As fileiras guardavam **índices de lombada**, e quem as
lia — as divisões da 004 — os tratava como **índices de instância**. Com uma
lombada perdida, as divisões de uma fileira eram calculadas com os livros
errados. A correção guarda de qual instância veio cada lombada e devolve
fileiras e deitados em índices de instância.

**Alternativas.** Agrupar as caixas por altura, sem máscara: seria uma segunda
regra de fileira para manter igual à primeira, e sem o critério de em pé.
Passar uma gravidade sintética "para baixo": funcionaria, mas faria a
`ShelfGeometry` calcular horizonte e ponto de fuga de uma câmera que não
existe.

**Como fechar.** SC-005: com caixas e divisões ligadas, toda divisão entre duas
caixas vizinhas da mesma fileira.

---

## R34 — O que continua vindo da foto

**Decisão.**

| | de onde |
|---|---|
| `count`, `shelves`, `shelfCount`, `lyingCount`, caixas e máscaras | da releitura, quando ela existe |
| `straightened`, `declineReason`, `geometryConfidence`, `azimuthConfidence`, `usedGravity`, `azimuthScores` | da foto — descrevem como a imagem foi feita |
| `outsideBandCount` | da foto — é o que a faixa deixou de fora dela |

**Quando não há releitura**, a leitura da foto é o resultado, como na 004, e
`countSource` diz `'photo'`:

- **sem recorte na tela** — o endireitamento recusado antes de haver recorte.
  A tela mostra a canônica, que é exatamente o que a foto leu (FR-008);
- **`reread` desligado** nas opções;
- **a releitura falhou** — o quadrado não foi montado ou o modelo lançou erro
  (FR-012).

**No diagnóstico**, a releitura roda sobre o recorte que teria ido para a tela,
para a contagem não mudar com o modo, e nada dela é desenhado (FR-010).

**A mensagem "nenhum livro na faixa"** passa a exigir `countSource: 'photo'`.
Com a releitura em zero, a faixa tinha livros — a foto os achou, ou não haveria
recorte —, e quem não os achou foi a releitura. A tela diz isso.

---

## R35 — O que muda nas specs anteriores

**Decisão.**

- O FR-004 da 004 fica riscado, com a nota de revogação e o link para esta
  spec. Ladrilhamento continua fora.
- O SC-004 da 004 ganha a nota de redefinição: a contagem da captura é a da
  releitura. O SC-006 da 005 herda por ele, e vira o SC-006 desta.
- O contrato da 004 não muda de forma: os campos de `CaptureResult` são os
  mesmos, e o que muda é de onde alguns vêm. Está no
  [contrato desta spec](./contracts/reread.md).

---

## Já decidido, sem pesquisa

| Decisão | Valor |
|---|---|
| Entrada da releitura | o recorte exibido, encaixado no quadrado, centrado, preto em volta |
| Limiares | os da sessão, como a foto (FR-003) |
| Ladrilhos, entrada larga, retreino | fora — decisão do autor em 27/09 |
| Arrasto e ampliação do resultado | continuam fora (adiados na 004) |
| Histórico | a origem da contagem vai no índice; a imagem salva é a da tela, como antes |

---

## Constitution Check, revisto depois da fase 1

| Princípio | Depois do desenho |
|---|---|
| I | A releitura roda na thread da captura. O overlay lê o store no relógio do display, e o bloco que publica não espera nada. |
| II | O quadrado e os protótipos ficam no nativo. `rereadMs` e `countSource` são os únicos campos novos que atravessam, e são números e texto. |
| III | Nenhum estado de React novo por quadro. O resultado chega uma vez. |
| IV | `reread` e `rereadMembership` nas opções. O recorte sem a margem é medido, não ajustado (R32). O preto é definição, não ajuste (R30). As guardas contra entrada degenerada — área zero, retângulo vazio — ficam no Swift, como na T043 da 005. |
| V | SC-001 a SC-007 numéricos, verificados no aparelho. |

**Continua sem violação.**
