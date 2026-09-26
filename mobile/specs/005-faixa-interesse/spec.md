# Feature Specification: Faixa de interesse

**Feature Branch**: `mobile/005-faixa-interesse`

**Created**: 2026-09-25

**Status**: Draft

**Input**: User description: "Dividir a tela com uma grade 3×3 e poder selecionar linhas nessa grade, que seriam as linhas em que a detecção realmente rola. Para estantes horizontais, selecionar apenas a linha do meio; as linhas restantes ficariam desmarcadas, com a imagem escurecida, para ficar bem claro." Nas perguntas antes desta spec, a grade virou uma **faixa arrastável**: uma por vez, horizontal ou vertical, com espessura ajustável, que pode ser desligada e volta ao centro a cada sessão.

> **Segundo marco de produto.** A 004 deu à pessoa uma contagem; esta a deixa
> dizer **o que** contar. Hoje, com duas ou três prateleiras no quadro, o
> recorte pega todas e a geometria mistura as fileiras. Com a faixa, a captura
> passa a ser "esta prateleira".

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Contar só a prateleira que interessa (Priority: P1)

A câmera abre com uma faixa horizontal no terço do meio. Fora dela a imagem
fica escurecida, e só os livros dentro dela são marcados e contados — ao vivo e
na captura. A pessoa arrasta a faixa com um dedo até a prateleira que quer.

**Why this priority**: é o pedido. Sem a faixa limitando a contagem, arrastar e
desenhar seriam decoração.

**Independent Test**: numa estante de três prateleiras, pôr a faixa sobre a do
meio e capturar: a contagem e o recorte são só da prateleira do meio.

**Acceptance Scenarios**:

1. **Given** uma sessão nova, **When** a câmera abre, **Then** a faixa está
   ligada, horizontal, no centro, ocupando um terço da imagem, e o resto
   aparece escurecido.
2. **Given** a faixa sobre uma prateleira, **When** a pessoa olha a imagem ao
   vivo, **Then** só os livros dentro da faixa têm caixa e máscara, e junto à
   faixa aparece quantos são.
3. **Given** a faixa, **When** a pessoa a arrasta com um dedo, **Then** ela
   acompanha o dedo, só no eixo em que pode andar, sem sair da imagem.
4. **Given** a faixa sobre uma prateleira, **When** a pessoa captura, **Then** a
   contagem, a geometria e o recorte usam só os livros da faixa.
5. **Given** uma faixa sem nenhum livro dentro, **When** a pessoa captura,
   **Then** o resultado diz que não há livros **na faixa** — não que não há
   livros na cena.
6. **Given** a faixa movida, **When** a pessoa volta de uma captura, **Then** a
   faixa está onde ela deixou.

---

### User Story 2 - Voltar à imagem toda (Priority: P2)

A pessoa desliga a faixa, e o app volta a detectar e contar na imagem inteira,
exatamente como antes desta spec. Religa quando quiser.

**Why this priority**: a faixa começa ligada, então desligar precisa existir
desde o primeiro dia. Sem isso, uma estante que não cabe no terço do meio fica
impossível de contar inteira.

**Independent Test**: desligar a faixa e conferir que caixas, contagem e
captura voltam a considerar a imagem toda.

**Acceptance Scenarios**:

1. **Given** a faixa ligada, **When** a pessoa escolhe "imagem toda" no
   controle, **Then** a faixa se abre até a imagem inteira, o escurecimento
   some, e tudo volta a contar.
2. **Given** a faixa ligada, **When** a pessoa afasta dois dedos até as bordas
   da faixa saírem da imagem, **Then** a faixa se desliga do mesmo jeito.
3. **Given** a faixa desligada, **When** a pessoa pinça a imagem com dois
   dedos, **Then** a faixa nasce entre os dedos.
4. **Given** a faixa desligada, **When** a pessoa escolhe uma orientação no
   controle, **Then** a faixa volta onde estava da última vez nesta sessão.

---

### User Story 3 - Enquadrar a prateleira com os dedos (Priority: P3)

A pessoa ajusta a espessura da faixa à prateleira: puxando uma borda com um
dedo, ou segurando as duas bordas com dois dedos.

**Why this priority**: prateleira raramente cabe num terço exato. Mas a faixa
padrão com arrasto já serve à maioria das fotos, então este ajuste vem depois.

**Independent Test**: ajustar a faixa a uma prateleira baixa e a uma alta, e
conferir que cada uma fica coberta sem invadir a vizinha.

**Acceptance Scenarios**:

1. **Given** a faixa, **When** a pessoa puxa a alça de uma borda, **Then** só
   aquela borda se move, e a oposta fica parada.
2. **Given** a faixa, **When** a pessoa a segura com dois dedos e os afasta ou
   aproxima, **Then** a faixa acompanha os dedos — posição e espessura ao mesmo
   tempo —, sem saltar no primeiro toque.
3. **Given** uma borda no limite, **When** a pessoa continua puxando, **Then** a
   faixa resiste, volta ao limite quando solta, e há um toque háptico ao
   encostar.
4. **Given** a faixa fora do lugar, **When** a pessoa toca duas vezes nela,
   **Then** ela volta ao centro e ao tamanho padrão.

---

### User Story 4 - Virar a faixa (Priority: P4)

Para uma coluna de livros, a pessoa vira a faixa na vertical — girando os dois
dedos que a seguram, ou pelo controle.

**Why this priority**: o caso do autor é a estante horizontal. A vertical
completa o modelo, e é o caso menos frequente.

**Independent Test**: virar a faixa sobre uma coluna de uma estante e capturar
só aquela coluna.

**Acceptance Scenarios**:

1. **Given** a faixa horizontal segurada com dois dedos, um acima do outro,
   **When** a pessoa gira os dedos até ficarem lado a lado, **Then** a faixa
   vira vertical ao passar da diagonal, com animação e um toque háptico.
2. **Given** os dedos perto da diagonal, **When** eles oscilam um pouco,
   **Then** a faixa não fica trocando de orientação.
3. **Given** a faixa horizontal, **When** a pessoa escolhe "vertical" no
   controle, **Then** a faixa vira mantendo o centro e a proporção da
   espessura.
4. **Given** a faixa vertical sobre uma coluna, **When** a pessoa captura,
   **Then** a contagem, a geometria e o recorte usam só os livros da coluna.

---

### Edge Cases

- **Livro na fronteira.** Conta quem tem a maior parte da caixa dentro da
  faixa, medida no eixo em que ela é limitada. Arrastada sobre a prateleira, a
  faixa tem as bordas nas tábuas: um critério pela base do livro cairia
  exatamente na borda, e uma faixa um pouco torta perderia a prateleira toda.
- **Faixa estreita demais para um livro inteiro.** A espessura tem um mínimo.
- **Poucos livros na faixa.** A geometria recusa o endireitamento e diz por
  quê, como já faz (FR-011 da 004). Não pede livros emprestados de fora.
- **Dedos perto da diagonal.** A orientação não pode tremular.
- **Dois dedos com a faixa desligada.** A faixa nasce entre eles.
- **Gesto sobre a imagem numa tela que rola.** O gesto é da faixa; a tela não
  rola.
- **Captura no meio de um gesto.** Vale a faixa do instante do toque no botão.
- **App vai para segundo plano no meio de um gesto.** O gesto é cancelado e a
  faixa fica onde estava.
- **Sessão nova depois de uma que terminou com a faixa desligada.** A faixa
  volta ligada, horizontal, no centro.
- **Diagnóstico.** A foto crua mostra a faixa e marca os livros que ela
  descartou — sem isso, "contou errado" e "a faixa cortou" parecem iguais.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O sistema MUST oferecer uma faixa de interesse, horizontal ou
  vertical, uma por vez — ou desligada.
- **FR-002**: Toda sessão MUST começar com a faixa ligada, horizontal, centrada
  e ocupando um terço da imagem.
- **FR-003**: O modelo MUST continuar lendo a imagem inteira. A faixa decide só
  o que é mostrado e contado.
- **FR-004**: Um objeto MUST contar como dentro da faixa quando a maior parte da
  sua caixa estiver dentro dela, medida no eixo em que a faixa é limitada.
- **FR-005**: Fora da faixa, a imagem MUST aparecer escurecida, e nenhum objeto
  de fora MUST ser desenhado.
- **FR-006**: A captura MUST usar só os objetos da faixa para contar, estimar a
  geometria e recortar.
- **FR-007**: A pessoa MUST poder arrastar a faixa com um dedo, só no eixo
  perpendicular a ela.
- **FR-008**: A pessoa MUST poder ajustar a espessura puxando uma borda, com a
  oposta parada.
- **FR-009**: Segurada com dois dedos, a faixa MUST acompanhá-los em posição e
  espessura, sem salto no toque inicial.
- **FR-010**: A orientação MUST seguir o eixo dos dois dedos — um acima do
  outro, horizontal; lado a lado, vertical —, trocando só depois de passar da
  diagonal com folga.
- **FR-011**: Um controle sempre visível junto à imagem MUST mostrar e trocar
  o estado: imagem toda, horizontal, vertical.
- **FR-012**: Afastar dois dedos até as bordas saírem da imagem MUST desligar a
  faixa; pinçar a imagem com ela desligada MUST criá-la entre os dedos.
- **FR-013**: Dois toques na faixa MUST devolvê-la ao centro e ao tamanho
  padrão.
- **FR-014**: A faixa MUST ficar sempre inteira dentro da imagem e acima de uma
  espessura mínima; no limite, MUST resistir ao dedo e voltar ao soltar.
- **FR-015**: Junto à faixa, o sistema MUST mostrar quantos objetos estão
  dentro dela agora, sem tremular.
- **FR-016**: Virar a orientação, ligar, desligar, voltar ao centro e encostar
  num limite MUST ter retorno tátil.
- **FR-017**: Toda mudança de estado da faixa MUST ser animada, sem salto.
  Durante o arrasto, a faixa MUST seguir o dedo sem animação no meio.
- **FR-018**: Um gesto que começa sobre a imagem MUST mexer na faixa, nunca
  rolar a tela.
- **FR-019**: Dentro de uma sessão, a faixa MUST manter o estado entre capturas,
  e ao ser desligada e religada.
- **FR-020**: Durante a transição da captura e no resultado, a faixa MUST sair
  de cena; ao voltar à câmera, MUST reaparecer como estava.
- **FR-021**: Toda ação da faixa MUST ter um caminho sem gesto de dois dedos,
  inclusive pelo leitor de tela.
- **FR-022**: O modo diagnóstico MUST mostrar a faixa sobre a foto e marcar os
  objetos descartados por ela.
- **FR-023**: Manipular a faixa MUST NOT provocar re-renderização da interface
  a cada quadro, conforme o princípio III.
- **FR-024**: Espessura padrão e mínima, folga da orientação, fração de
  pertença e aparência da faixa MUST ser ajustáveis sem rebuild nativo,
  conforme o princípio IV.

### Key Entities

- **Faixa de interesse**: estado (desligada, horizontal, vertical), centro e
  espessura, normalizados na imagem. Uma só vale para o ao vivo e para a
  captura, porque as duas passam pela mesma imagem canônica.
- **Regra de pertença**: a fração mínima da caixa que precisa estar dentro da
  faixa — hoje, a maior parte.
- **Última faixa da sessão**: o estado ao qual religar retorna. Some com a
  sessão.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Numa estante de três prateleiras, com a faixa sobre a do meio, a
  contagem da captura fica dentro de ±10% da contagem manual daquela
  prateleira.
- **SC-002**: Em 10 capturas com a faixa sobre uma prateleira, o recorte mostra
  só aquela prateleira nas 10.
- **SC-003**: Manipular a faixa sem parar por 30 s mantém câmera e inferência a
  60 fps: nenhuma janela de telemetria abaixo de 59.
- **SC-004**: Em 10 viradas de orientação pelos dedos, as 10 acontecem na
  primeira tentativa, sem tremular.
- **SC-005**: Duas de três pessoas que nunca viram o app enquadram uma
  prateleira em menos de 20 s, sem instrução.
- **SC-006**: Com a faixa desligada, o SC-004 da 004 continua valendo: a
  contagem da foto fica dentro de ±10% da mediana ao vivo na mesma cena.

## Assumptions

- **Filtro, não recorte.** Recortar a entrada do modelo à faixa não ganharia
  resolução — a faixa horizontal tem a largura da imagem inteira — e quebraria
  a regra de que o que o modelo vê é o que a tela mostra.
- **A tela mostra exatamente o que o modelo vê**, nas três transformações
  (herdado dos marcos 2 e 4). A faixa desenhada está nas coordenadas da
  detecção, e a foto passa pela mesma transformação: uma faixa só vale para
  ao vivo e captura.
- **"Volta ao centro" foi lido como: toda sessão começa com a faixa ligada.** A
  resposta do autor fala da posição; ligada é o que faz haver uma faixa para
  voltar ao centro, e é o caso de uso dele, a prateleira do meio. O terço como
  espessura inicial é a linha do meio da grade 3×3 que deu origem à ideia.
- **Só o que conta é desenhado.** Livros fora da faixa não aparecem, nem
  esmaecidos: o escurecimento já diz que eles não entram.
- **Geometria só com os livros da faixa**, por decisão do autor.
- **A experiência foi delegada pelo autor** — "a maneira mais intuitiva e
  interessante, premium e moderna". O modelo escolhido: **a faixa são as suas
  duas bordas**. Um dedo no meio move as duas; um dedo numa borda move aquela;
  dois dedos seguram uma cada. Como dois dedos definem um eixo, o eixo deles
  define a orientação — espessura e orientação saem do mesmo gesto, que é o
  "de uma maneira que faça sentido com a primeira resposta" que o autor pediu.
  O controle de três estados existe para quem não descobre o gesto e para o
  leitor de tela.
- **Fora de escopo:** mais de uma faixa, faixa em ângulo livre, região
  desenhada à mão, e a releitura da faixa endireitada — que tem spec própria.

## Decisões adiadas

- **Espessura mínima, folga da orientação, suavização da contagem e a forma das
  animações.** São números que só existem depois de sentir no aparelho.
- **Desfocar além de escurecer.** Dá mais sensação de foco — e só entra se a
  medição mostrar que não custa quadro.
- **A faixa se encaixar sozinha na prateleira mais próxima.** É a evolução
  natural, já que as fileiras são detectadas na captura, mas depende de a faixa
  manual provar que é usada.
- **O histórico registrar a faixa usada.** Segue a decisão adiada da 004 sobre o
  que mais entra no histórico.
