# Fase 0 — Pesquisa

Onze incógnitas, nenhuma sobre o filtro. A regra de pertença é uma conta de
sobreposição em um eixo; tudo o que é difícil aqui é fazer a faixa **parecer
física** sem pagar em quadros nem em re-render.

A R18 e a R22 são as que decidem se a experiência é premium ou só funcional.

---

## R18 — Onde vive o gesto

**Decisão.** Um `UIGestureRecognizer` próprio, na `PreviewView`, que acompanha
até dois toques numa máquina de estados: parado → um dedo (mover ou borda) →
dois dedos (pinça) → parado. Mais um `UITapGestureRecognizer` de dois toques
para voltar ao centro.

O reconhecedor só começa depois que o dedo anda alguns pontos, ou quando pousa
o segundo dedo. Assim um toque simples não é engolido, e os dois toques chegam
ao reconhecedor deles.

**Por quê.** Seguir o dedo a 60 fps sem React é o princípio III. E o gesto
principal desta spec é justamente a passagem de um para dois dedos: a pessoa
arrasta, pousa o segundo dedo e passa a ajustar a espessura. Com um dono só, a
passagem é contínua.

**Alternativas.**

| | por que não |
|---|---|
| arrasto e pinça do UIKit, separados | trocam de dono quando o segundo dedo pousa — um salto no meio do gesto principal |
| Reanimated + Gesture Handler | resolvem o III no JavaScript, mas são duas dependências nativas grandes, plugin de Babel e rebuild — e o filtro precisa da faixa no nativo de qualquer jeito, o que faria o estado atravessar a cada quadro |
| `PanResponder` do React Native | roda no thread do JavaScript; a lógica de orientação por quadro violaria o III |

**Como fechar.** SC-003, e olhar se a borda cola no dedo.

---

## R19 — O gesto e a tela que rola

**Decisão.** O preview sai da `ScrollView` da `CameraScreen` e fica fixo no
topo, com a cápsula logo abaixo. Os cartões rolam embaixo.

**Por quê.** Dentro da `ScrollView`, o arrasto vertical sobre a imagem disputa
com a rolagem. Fora dela, a disputa não existe e o FR-018 vale por construção.
E um visor que rola para fora da tela nunca foi o que uma câmera faz.

**Alternativas.** Manter o preview na `ScrollView` e obrigar a rolagem a
esperar a falha do reconhecedor da faixa: resolve a disputa, mas a `ScrollView`
do iOS ainda pode segurar o toque antes de entregá-lo — e atraso no primeiro
toque é exatamente o que separa o premium do funcional. Desligar a rolagem
durante o gesto por evento do nativo: uma corrida entre dois threads a cada
gesto.

**Como fechar.** Arrastar a faixa para cima e para baixo: a tela não se mexe.

---

## R20 — Desenhar a faixa

**Decisão.** Três camadas na `PreviewView`:

| camada | o que é | onde |
|---|---|---|
| escurecimento | um `CAShapeLayer` com preenchimento par-ímpar: a moldura menos a faixa | **abaixo** do overlay |
| bordas e alças | um `CAShapeLayer` com as duas linhas e as duas cápsulas | acima do overlay |
| contagem | uma pílula com texto, presa à ponta de uma borda | acima do overlay |

O escurecimento fica abaixo das caixas de propósito: um livro que conta aparece
inteiro e vivo, mesmo onde passa da borda. Caixa acesa quer dizer "conta".

Toda mudança de estado é uma mola no caminho — `CASpringAnimation` de
retângulo para retângulo: virar, ligar, desligar, voltar ao centro, soltar no
limite. Durante o arrasto as ações implícitas ficam desligadas, e a camada vai
exatamente para onde o dedo está.

**Por quê.** Retângulo para retângulo tem o mesmo número de pontos, então a
interpolação não torce; e é trabalho do servidor de renderização, não da CPU. É
o mesmo recurso da transição da 004. Ligar e desligar viram o mesmo movimento:
desligada, a faixa **é** a moldura, e o escurecimento não tem área.

Uma mola interrompida por um novo toque parte de onde a camada está na tela,
lida da camada de apresentação — como a volta da 004 já faz.

**Alternativas.** Views do React com `Animated`: cada arrasto passaria pelo
JavaScript. Skia: não existe no projeto. Redesenhar com Core Graphics a cada
quadro: custo sem motivo.

**Como fechar.** `drawMs` na telemetria com a faixa em movimento.

---

## R21 — Onde o filtro age

**Decisão.** A regra de pertença é uma função pura, aplicada por quem
**consome** as detecções:

| quem | quando | com qual faixa |
|---|---|---|
| desenho do overlay | a cada tique do display | a mais recente, no mesmo thread do gesto |
| contagem junto à faixa | a cada tique do display | idem |
| contagem da telemetria | a cada frame, na fila da câmera | lida com trava |
| foco da aproximação | no toque de capturar | a do toque |
| captura | nas detecções da foto, **antes** da geometria | a do toque (FR-006) |

O `ResultStore` continua publicando todas as detecções. O overlay passa a
redesenhar quando muda o resultado **ou** a faixa.

**Por quê.** Filtrando no desenho, a caixa troca no quadro exato em que a borda
passa por ela. Filtrando na publicação, o desenho ficaria um quadro atrás do
dedo — pouco, mas é o tipo de coisa que se sente sem saber o que é. E as
descartadas ficam à mão para o diagnóstico (FR-022), e para dizer "nenhum livro
na faixa" em vez de "nenhum livro" (US1, cenário 5).

**Alternativas.** Filtrar antes de publicar: um lugar só, ao custo de um quadro
de atraso e de perder as descartadas.

**Como fechar.** Arrastar uma borda devagar sobre um livro: a caixa troca
quando a maior parte dele passa, nem antes nem depois.

---

## R22 — Dois dedos

**Decisão.**

- **Segurar.** Ao pousar o segundo dedo, a faixa segue os dois como numa pinça
  em torno do ponto médio: a espessura escala com a distância entre os dedos, e
  o centro acompanha o ponto médio. Nada salta no toque (FR-009).
- **Virar.** O ângulo do segmento entre os dedos decide. Acima de 45° mais a
  folga, horizontal; abaixo de 45° menos a folga, vertical; entre os dois,
  mantém. Ao virar, a faixa se refaz exatamente entre os dedos no novo eixo,
  numa mola e com um toque háptico, e a pinça recomeça dali.
- **Criar.** Com a faixa desligada, dois dedos a criam entre eles, orientada
  pelo eixo.
- **Desligar.** Quando as duas bordas passam das bordas da imagem além de uma
  margem, a faixa se dissolve. Se os dedos voltarem no mesmo gesto, ela renasce
  entre eles.
- **Limites.** Com um dedo ou com dois, uma borda além do limite resiste
  (elástico) e volta numa mola ao soltar. Um toque háptico leve na primeira vez
  que encosta.

**Por quê.** O modelo mais literal — cada dedo vira uma borda no instante do
toque — salta ao pousar, a menos que a pessoa acerte as bordas. A pinça
relativa mantém a sensação de segurar as bordas sem o salto. O único salto que
sobra é ao virar, que é onde ele é o ponto: animado e sentido na mão.

**Alternativas.** Gesto de girar para virar: ambíguo com a pinça, e girar 90°
com dois dedos numa área pequena é desconfortável. Botão para virar: existe, na
cápsula, para quem não descobre o gesto e para o leitor de tela.

**Como fechar.** SC-004, ajustando a folga — o valor inicial é palpite.

---

## R23 — A contagem junto à faixa

**Decisão.** A mediana das contagens da faixa numa janela de tempo, calculada no
desenho. O texto só muda quando a mediana muda.

**Por quê.** A contagem crua oscila de quadro a quadro. A mediana mata o tremor
sem esconder uma mudança real: uma prateleira nova entrando na faixa muda a
mediana em meia janela.

**Alternativas.** Média: arredondada, tremula entre dois inteiros. Histerese de
±1: esconde justamente as mudanças pequenas e reais.

**Como fechar.** Faixa parada sobre uma prateleira: o número não pisca.

---

## R24 — Retorno tátil

**Decisão.** `UISelectionFeedbackGenerator` para virar, ligar, desligar e voltar
ao centro; `UIImpactFeedbackGenerator(style: .light)` para encostar num limite.
Preparados no começo do gesto; nada durante o arrasto contínuo. A política pode
desligar tudo.

**Por quê.** O toque na mão tem que coincidir com o quadro do evento. Disparado
do nativo, onde o evento nasce, não há ida e volta pela ponte. O `expo-haptics`
seria uma dependência a mais para chamar as mesmas APIs, com atraso.

**Como fechar.** Sentir — e conferir que o arrasto contínuo não vibra.

---

## R25 — Leitor de tela e o caminho sem dois dedos

**Decisão.** A faixa é um elemento de acessibilidade **ajustável**: deslizar
para cima e para baixo a move. Tem ações próprias: virar, engrossar, afinar,
voltar ao centro, desligar. A cápsula tem três botões com rótulo e estado.

Sem leitor de tela, o caminho sem dois dedos (FR-021) é: arrastar com um dedo,
alças para a espessura, cápsula para o modo, dois toques para o centro.

**Como fechar.** A jornada inteira com o VoiceOver ligado.

---

## R26 — Quem é dono do estado

**Decisão.** O nativo. Um `BandModel` com trava guarda o estado, a última faixa
ligada e a política: o gesto escreve no thread principal, a fila da câmera lê.

- Ao JavaScript vai o evento `onBandChange`, só quando o estado muda de verdade
  — fim de gesto, troca de modo, volta ao centro. Nunca durante o arrasto.
- O JavaScript muda o modo por `setBandMode`, quando a pessoa toca a cápsula.
- `startSession` reinicia a faixa com o padrão da política, que chega em
  `SessionOptions.band` — atômico com o começo da sessão (FR-002). Sem chamada
  separada que pudesse chegar depois do primeiro frame.

**Por quê.** Uma fonte da verdade só, e o princípio III: o JavaScript espelha o
estado para desenhar a cápsula, e nunca o dirige quadro a quadro.

**Alternativas.** Estado no JavaScript, com `setBand` a cada quadro: viola o
III e atravessa a fronteira por quadro.

---

## R27 — A faixa durante a captura

**Decisão.** No toque de capturar, as camadas da faixa somem numa animação
curta e o reconhecedor desliga. Voltam quando a transição de volta termina: a
`ResultRenderer` avisa no fim do `dismiss`. A cápsula some junto, pelo estado de
captura que o React já tem.

**Por quê.** FR-020. A faixa sobre o resultado não significa nada, e um gesto
nela mexeria num estado que a captura já leu.

---

## R28 — Desfocar além de escurecer *(decisão adiada)*

**Direção.** Duas `UIVisualEffectView`, acima e abaixo da faixa, sobre a camada
de vídeo, acompanhando as bordas. O efeito é o de modo retrato: a prateleira
nítida, o resto fora de foco.

**O que decide.** A telemetria: se `fpsCaptured` ou `drawMs` piorarem com o
desfoque ligado, fica só o escurecimento. **Não entra na primeira passada** —
a spec o adiou até haver número.

---

## Constitution Check, revisto depois da fase 1

O desenho da fase 1 ([data-model](./data-model.md), [contrato](./contracts/band.md))
não mudou nenhum veredito:

- **III** — o contrato só tem um evento, e ele dispara em mudança discreta.
  Nenhum caminho do gesto escreve estado de React.
- **IV** — doze campos de comportamento e seis de aparência, todos em TS.
  Nenhum deles tem default com significado no Swift: os campos novos seguem os
  defaults inválidos de propósito que a T037 da 004 adotou.
- **II** — o maior dado novo que atravessa é o estado da faixa: três números e
  um texto.
