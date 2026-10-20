# Feature Specification: Modo coleta

**Feature Branch**: `mobile/007-modo-coleta`

**Created**: 2026-10-19

**Status**: Draft

**Input**: User description: "Quero que você me ajude a especificar uma implementação no app que vai ser um 'modo de teste para treino' ou um nome melhor que você pensar. A ideia é que quando esse modo for ativado, todas as leituras e capturas devem ser registradas junto das imagens de referência. Então, nesse modo, a leitura em tempo real não precisa pegar todos os quadros e armazenar eles e informações sobre eles, ele pode pegar um a cada segundo ou o que você pensar melhor. As capturas devem poder ser realizadas dentro desse modo 'super log' que registra tudo e as imagens que a câmera capturou, para que eu possa exportar em um .zip e te trazer os dados verdadeiros para analisarmos." Nas respostas antes desta spec: o nome é **modo coleta**, organizado em **sessões**; "imagens de referência" são as imagens que o modelo leu; o ao vivo é gravado **só sob demanda**, por um botão "marcar", e não um quadro por segundo; depois de cada captura e de cada marca o app pede a **contagem real**, que é a do que aparece na tela; o histórico continua só com o que a pessoa salva; o zip sai pelo menu de compartilhar; rótulos para o Roboflow ficam para depois.

> **Ferramenta, não produto.** As specs 004 a 006 construíram a contagem. A
> 007 não muda nenhuma contagem: grava o que o modelo viu e concluiu, com a
> contagem real ao lado, para medir o modelo de hoje e treinar o de amanhã. O
> dataset tem cerca de 1.000 imagens, e os erros que se repetem são a lombada
> fina que some, dois vizinhos que viram um, um livro que vira dois e o que não
> é livro contado como livro.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Uma sessão de capturas, com a verdade ao lado, num zip (Priority: P1)

A pessoa liga o modo coleta na câmera, e um indicador mostra que está
gravando. Ela captura como sempre: o resultado aparece igual, com a mesma
contagem e no mesmo tempo. Quando a contagem fica pronta, o app pergunta
quantos livros aparecem de verdade na tela, já preenchido com o número dele, e
ela corrige com +/− ou pula. Cada captura fica gravada com as imagens de cada
etapa, os dados de cada etapa e a resposta. Ao desligar, a sessão fecha; na
aba Medição, ela exporta um zip pelo menu de compartilhar.

**Why this priority**: é o pedido. As capturas são o caso de uso do app, e a
contagem real é o que transforma o zip num gabarito: sem ela, os dados mostram
o que o modelo achou, mas não o que estava certo.

**Independent Test**: abrir uma sessão, fazer 5 capturas respondendo a
contagem real, fechar e exportar. O zip traz as 5 capturas, cada uma com as
imagens, os dados e a resposta, e os dados reproduzem a contagem que a tela
mostrou em cada uma.

**Acceptance Scenarios**:

1. **Given** o modo desligado, **When** a pessoa o liga na câmera, **Then**
   começa uma sessão, e o indicador mostra que está gravando, há quanto tempo,
   quantas marcas, quantas capturas e quanto espaço a sessão ocupa.
2. **Given** uma sessão aberta, **When** a pessoa captura, **Then** o resultado
   aparece como fora do modo, e ao fim da leitura o app pede a contagem real,
   preenchida com a contagem mostrada.
3. **Given** o pedido na tela, **When** a pessoa corrige com +/− e confirma,
   **Then** a captura fica gravada com as imagens, os dados de cada etapa e a
   contagem real.
4. **Given** o pedido na tela, **When** a pessoa pula ou volta à câmera sem
   responder, **Then** a captura fica gravada com "sem resposta".
5. **Given** o resultado de uma captura em sessão, **When** a pessoa salva,
   **Then** o histórico o recebe como hoje; **When** não salva, **Then** nada
   entra no histórico.
6. **Given** uma sessão aberta, **When** a pessoa desliga o modo, **Then** a
   sessão fecha e aparece na Medição.
7. **Given** uma sessão fechada, **When** a pessoa a exporta, **Then** o menu de
   compartilhar oferece um zip, e a sessão continua no aparelho.
8. **Given** o zip aberto fora do aparelho, **When** a contagem de cada captura
   é recalculada a partir dos dados gravados, **Then** ela é igual à que a tela
   mostrou.

---

### User Story 2 - Marcar o ao vivo (Priority: P2)

Com a sessão aberta, a pessoa vê o ao vivo errar — uma lombada que some, uma
contagem que pula — e toca em "marcar". A tela para naquele quadro, como
estava, e pede a contagem real dos livros que aparecem nela. Respondendo ou
pulando, a câmera volta. A marca fica gravada com a imagem que o modelo leu, o
quadro da câmera sem esticar e as detecções daquele mesmo quadro.

**Why this priority**: as capturas já dão o gabarito. Marcar acrescenta o ao
vivo, que roda num quadro menor e é onde a pessoa vê o erro acontecer — mas o
zip vale sem isto.

**Independent Test**: abrir uma sessão, fazer 5 marcas com o aparelho se
movendo e exportar. Desenhadas sobre a imagem gravada de cada marca, as caixas
gravadas caem sobre os livros.

**Acceptance Scenarios**:

1. **Given** uma sessão aberta e a câmera ao vivo, **When** a pessoa toca em
   marcar, **Then** a tela para no quadro marcado como estava exibido — faixa,
   caixas e máscaras — e pede a contagem real, preenchida com a contagem que a
   tela mostrava.
2. **Given** o quadro parado, **When** a pessoa responde ou pula, **Then** a
   câmera volta ao vivo, e a marca fica gravada com as duas imagens, as
   detecções do quadro e a resposta.
3. **Given** a faixa ligada, **When** a pessoa marca, **Then** a contagem real
   pedida é a dos livros dentro da faixa; com a faixa desligada, a da imagem
   toda.
4. **Given** o resultado de uma captura na tela ou uma captura em andamento,
   **Then** marcar não está disponível.
5. **Given** o modo desligado, **Then** não há marcar.

---

### User Story 3 - As sessões no aparelho (Priority: P3)

Na aba Medição, a pessoa vê as sessões gravadas, dá nome a uma ("sala, luz da
noite"), exporta de novo uma que já exportou e apaga as que não quer mais. O
app não deixa a coleta encher o aparelho.

**Why this priority**: com uma sessão por vez, a US1 já basta. Isto é o que
torna o modo usável ao longo de semanas, sessão após sessão.

**Independent Test**: gravar três sessões, nomear uma, exportar a mesma duas
vezes e apagar outra. A lista reflete cada passo, e a apagada some do
aparelho.

**Acceptance Scenarios**:

1. **Given** sessões gravadas, **When** a pessoa abre a Medição, **Then** vê
   cada uma com data, nome, marcas, capturas, quantas têm resposta e tamanho.
2. **Given** uma sessão fechada, **When** a pessoa lhe dá um nome, **Then** a
   lista e o zip o usam.
3. **Given** uma sessão fechada, **When** a pessoa a apaga e confirma, **Then**
   ela some do aparelho.
4. **Given** uma sessão aberta, **When** a pessoa vai a outra aba e volta,
   **Then** a sessão continua gravando; na Medição, ela aparece em andamento e
   não pode ser exportada.
5. **Given** uma sessão aberta, **When** o app vai para segundo plano, **Then**
   a sessão fecha com o que já tinha.
6. **Given** pouco espaço livre no aparelho, **When** a pessoa marca, **Then** a
   marca é recusada com aviso; **When** captura, **Then** o resultado aparece
   normalmente, mas não é gravado na sessão, e o aviso diz isso.

---

### Edge Cases

- **Endireitamento recusado, ou releitura que falha.** A tela mostra a foto
  inteira, ou a contagem vem da foto (006, FR-008 e FR-012). Grava-se o que
  existe; as imagens que não existem ficam de fora, e os dados dizem por quê —
  a origem da contagem e o motivo da recusa.
- **Diagnóstico ligado.** A tela mostra um desenho sobre a foto, não o recorte.
  A captura é gravada igual, e a contagem real pedida é a dos livros dentro do
  recorte desenhado — o que a releitura leu.
- **A captura falha** — a foto não sai. Nada é gravado, e a sessão segue.
- **O espaço acaba no meio de uma gravação, ou o app é encerrado à força.** O
  item que estava sendo gravado não entra; os anteriores ficam inteiros. Ao
  abrir de novo, a sessão aparece fechada e exportável.
- **Sessão sem nenhuma marca nem captura.** Ao fechar, não fica na lista.
- **A pessoa sai da câmera com um quadro marcado parado.** A marca já está
  gravada e fica "sem resposta".
- **Exportar falha** — sem espaço para o zip, ou o compartilhamento é
  cancelado. A sessão continua intacta, e o aviso diz o que houve.
- **Sessão longa.** Não há limite de duração nem de itens; só o de espaço.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A tela da câmera MUST ter como ligar e desligar o modo coleta.
  Ligar abre uma sessão; desligar a fecha.
- **FR-002**: Com o modo ligado, a câmera MUST mostrar um indicador de
  gravação com o tempo da sessão, o número de marcas, o de capturas e o espaço
  ocupado.
- **FR-003**: O modo MUST NOT mudar o que o app mostra, conta ou guarda no
  histórico: mesmos limiares, mesmas caixas, mesma contagem, mesmo tempo até o
  resultado, e o histórico só com o que a pessoa salva.
- **FR-004**: Cada captura em sessão MUST gravar, quando existirem: a foto em
  resolução máxima; o quadrado que o modelo leu da foto; o recorte endireitado
  em resolução cheia; e o quadrado da releitura, como a tela mostrou.
- **FR-005**: Cada captura em sessão MUST gravar os dados de cada etapa: as
  detecções da foto e as da releitura; a faixa e as detecções que ela
  descartou; a geometria — endireitado ou não, motivo da recusa, confianças,
  gravidade, curva de azimute e recorte; quais detecções a regra das bordas
  deixou contar; a contagem, a origem dela, as fileiras, as divisões e os
  deitados; e os tempos.
- **FR-006**: Toda detecção gravada, na captura e na marca, MUST trazer caixa,
  máscara e confiança, e MUST ser gravada até a confiança 0,05, junto com os
  limiares em vigor — o que decide o que existe e o que aparece. Assim os dados
  distinguem o que contou, o que apareceu e o que só foi gravado.
- **FR-007**: Quando a contagem de uma captura em sessão ficar pronta, o app
  MUST pedir a contagem real — os livros que aparecem na tela —, preenchida com
  a contagem mostrada, ajustável com +/− e que se pode pular. Pular, ou sair
  sem responder, MUST gravar "sem resposta".
- **FR-008**: Com uma sessão aberta e a câmera ao vivo, a pessoa MUST poder
  marcar o quadro atual. A marca MUST gravar o quadrado que o modelo leu, o
  quadro da câmera sem esticar e as detecções desse mesmo quadro (FR-006) —
  imagens e detecções do mesmo instante —, além da faixa, da gravidade, da
  contagem que a tela mostrava e da contagem do próprio quadro.
- **FR-009**: Ao marcar, a tela MUST parar no quadro marcado, como estava
  exibido, e pedir a contagem real dos livros que aparecem nele — dentro da
  faixa, quando ligada —, preenchida com a contagem que a tela mostrava.
  Responder ou pular MUST voltar ao ao vivo.
- **FR-010**: Marcar MUST NOT estar disponível com o modo desligado, durante
  uma captura ou com o resultado de uma captura na tela.
- **FR-011**: A contagem real MUST ser dada só na hora. Não há como editá-la
  depois.
- **FR-012**: Cada sessão MUST guardar quando começou e terminou, o modelo, a
  versão do app, o aparelho e o sistema, todas as políticas em vigor — de
  detecção, captura, faixa e aparência — e a telemetria da câmera durante a
  sessão.
- **FR-013**: Trocar de aba MUST NOT fechar a sessão. Ir para segundo plano ou
  encerrar o app MUST fechá-la, com o que ela já tinha.
- **FR-014**: Cada marca e cada captura MUST ser gravada inteira ou não ser
  gravada: nenhuma sessão contém item pela metade, nem depois de falta de
  espaço ou de o app ser encerrado à força.
- **FR-015**: A aba Medição MUST listar as sessões com data, nome, número de
  marcas, de capturas, de respostas e tamanho. A sessão em andamento aparece
  como tal e não pode ser exportada.
- **FR-016**: Exportar uma sessão fechada MUST gerar um zip e abrir o menu de
  compartilhar do sistema. A sessão MUST continuar no aparelho, e pode ser
  exportada de novo.
- **FR-017**: O zip MUST conter a descrição do próprio formato, com versão, de
  modo que os dados possam ser lidos sem o código do app.
- **FR-018**: A pessoa MUST poder dar nome a uma sessão fechada e apagá-la.
  Apagar pede confirmação.
- **FR-019**: Uma sessão sem marcas nem capturas MUST NOT ficar na lista ao
  fechar.
- **FR-020**: Com o espaço livre abaixo do limite, marcar MUST ser recusado
  com aviso, e a captura MUST acontecer normalmente, sem ser gravada na sessão,
  com um aviso que diga isso.
- **FR-021**: Gravar MUST NOT degradar a câmera ao vivo nem atrasar o resultado
  da captura (SC-001, SC-004).
- **FR-022**: Nenhum pixel MUST atravessar para o JavaScript. O que atravessa
  são identificadores, contagens, tamanhos e respostas, conforme o princípio
  II.
- **FR-023**: O limiar mínimo de gravação, o limite de espaço e a qualidade das
  imagens MUST ser ajustáveis sem rebuild nativo, conforme o princípio IV.

### Key Entities

- **Sessão de coleta**: o intervalo entre ligar e desligar o modo. Tem nome
  opcional, as marcas, as capturas, as políticas em vigor e a telemetria. Vira
  um zip.
- **Marca**: um quadro do ao vivo gravado sob demanda — o quadrado que o
  modelo leu, o quadro da câmera, as detecções, a faixa, as contagens e a
  resposta.
- **Captura gravada**: uma captura feita em sessão — as imagens de cada etapa,
  os dados de cada etapa e a resposta.
- **Contagem real**: o número de livros que aparecem na tela, dado pela
  pessoa, ou "sem resposta". É o gabarito do item.
- **Zip da sessão**: tudo o que a sessão gravou, com a descrição do formato.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Numa sessão de 5 min com pelo menos 10 marcas e 10 capturas, a
  câmera se mantém a 60 fps fora dos instantes de captura e volta a 60 fps
  depois de cada captura e de cada marca, medido pela telemetria.
- **SC-002**: No zip real dessa sessão, trazido para fora do aparelho, a
  contagem recalculada a partir das detecções gravadas é igual à que a tela
  mostrou em 100% das capturas, e à contagem do próprio quadro em 100% das
  marcas — ao vivo, a tela mostra uma mediana de vários quadros. Cada resposta
  está no item a que foi dada.
- **SC-003**: Em toda captura gravada em que a tela mostrou um recorte, as
  quatro imagens estão no zip. Nas outras, o motivo está nos dados.
- **SC-004**: Com o modo ligado, o resultado continua visível em menos de 1,5 s
  do toque (SC-001 da 004) nas 10 capturas do SC-001.
- **SC-005**: Em 10 marcas feitas com o aparelho em movimento, as caixas
  gravadas, desenhadas sobre a imagem gravada, caem sobre os livros.
- **SC-006**: Com o app encerrado à força no meio de uma sessão, ao abrir de
  novo a sessão aparece fechada e exportável, com todos os itens concluídos e
  nenhum pela metade.

## Relação com as specs anteriores

- **Lê, não muda.** A foto, a geometria e o recorte (004), a faixa (005) e o
  quadrado da releitura (006) são gravados como são. Nenhuma regra de
  contagem muda.
- **A telemetria da 002** passa a ir também para dentro da sessão.
- **O histórico da 004** continua igual: só o que a pessoa salva.
- **A aba Medição** (001) ganha a lista de sessões.

## Assumptions

- **Para que serve.** Medir o modelo atual contra a contagem real e juntar
  imagens dos casos em que ele erra para retreinar.
- **Ferramenta do autor.** O modo fica à vista de quem usa o app; não há nada
  para escondê-lo.
- **A contagem real é a do que aparece na tela.** Decisão do autor: isola o
  erro do modelo. Quando o recorte deixa livros de fora, isso não aparece como
  erro de contagem — só nas imagens, e a foto inteira está no zip.
- **Sem amostragem automática do ao vivo.** O pedido sugeria um quadro por
  segundo; o autor escolheu marcar sob demanda.
- **O quadro da câmera da marca** tem a resolução do ao vivo — o menor formato
  que cobre a entrada do modelo —, não a da foto.
- **Imagens em JPEG**, como o histórico: é o formato que vai sem conversão para
  o Colab e para o Roboflow.
- **Fora de escopo, por decisão do autor em 19/10:** rótulos prontos para o
  Roboflow, editar a contagem real depois e amostrar o ao vivo sem marcar.
  Também fora: trocar ou comparar modelos dentro do app.
- **As sessões ficam até a pessoa apagar.** Não há limpeza automática.

## Decisões adiadas

- **O limite de espaço.** Começa em 1 GB livre. Ajustar se recusar cedo ou
  tarde demais no uso.
- **O limiar mínimo de gravação.** Começa em 0,05. Subir se o volume de
  detecções gravadas pesar no tamanho ou no tempo de gravação.
