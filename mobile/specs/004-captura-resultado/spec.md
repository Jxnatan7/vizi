# Feature Specification: Captura e resultado endireitado

**Feature Branch**: `mobile/004-captura-resultado`

**Created**: 2026-09-17

**Status**: Draft

**Input**: User description: "Apontar para a estante, apertar um botão, e o app tira uma foto em resolução máxima, conta os livros, recorta, endireita a perspectiva e mostra a faixa de lombadas reta na tela, com as divisões e a quantidade — tudo numa animação de transição. Poder voltar ou salvar no histórico."

> **É o primeiro marco de produto.** Os três anteriores construíram o
> instrumento: o app vê, detecta, segmenta e desenha a 60 fps. Nenhum deles deu
> à pessoa algo para *fazer*. Este dá.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Capturar e saber quantos livros (Priority: P1)

A pessoa aponta para uma estante, aperta um botão, e recebe a contagem de
livros daquela foto.

**Why this priority**: é a ação que o app existe para oferecer. Tudo antes era
diagnóstico.

**Independent Test**: apontar, apertar, conferir se o número bate com a estante.

**Acceptance Scenarios**:

1. **Given** a câmera ao vivo, **When** a pessoa aperta o botão, **Then** um
   indicador de carregamento aparece e em seguida o resultado com a contagem.
2. **Given** o resultado na tela, **When** a pessoa volta, **Then** a câmera ao
   vivo retoma sem precisar reiniciar a sessão.
3. **Given** uma cena sem livros, **When** capturada, **Then** o resultado
   informa que nada foi encontrado, em vez de mostrar uma faixa vazia.

---

### User Story 2 - Ver os livros de frente, retos (Priority: P2)

A imagem capturada aparece recortada na faixa de lombadas, com a perspectiva
corrigida — como se tivesse sido fotografada de frente.

**Why this priority**: é o que transforma uma foto de estante torta numa
imagem que dá para ler e contar. Também é a parte mais difícil do marco.

**Independent Test**: fotografar uma estante de ângulo e conferir se o
resultado aparece retangular, com as lombadas paralelas.

**Acceptance Scenarios**:

1. **Given** uma estante fotografada de ângulo, **When** capturada, **Then** o
   resultado mostra as lombadas verticais e paralelas.
2. **Given** a faixa mais larga que a tela, **When** exibida, **Then** a pessoa
   pode arrastar horizontalmente para percorrer a estante.
3. **Given** uma cena em que a geometria não é confiável, **When** capturada,
   **Then** o resultado aparece **sem** endireitar, com aviso de que a
   correção não foi aplicada.

---

### User Story 3 - A transição entre a câmera e o resultado (Priority: P3)

Ao apertar o botão, a imagem ao vivo se transforma no resultado por uma
animação contínua — recorta, aproxima e endireita — em vez de trocar de tela.

**Why this priority**: é o que separa "funciona" de "é bom de usar". Fica em P3
porque depende do resultado existir, e porque um corte seco entregaria o mesmo
valor funcional.

**Independent Test**: apertar o botão e observar se a transição é contínua,
sem salto entre o que estava na tela e o que aparece.

**Acceptance Scenarios**:

1. **Given** a câmera ao vivo, **When** a pessoa aperta o botão, **Then** a
   transição começa imediatamente, sem esperar a foto ficar pronta.
2. **Given** a transição em andamento, **When** a foto em alta resolução fica
   pronta, **Then** ela substitui a imagem de trabalho sem salto visível.
3. **Given** a transição, **When** observada, **Then** ela não engasga.

---

### User Story 4 - Guardar o que foi contado (Priority: P4)

A pessoa pode salvar o resultado e revê-lo depois.

**Why this priority**: é o que faz o app acumular valor em vez de ser um
brinquedo de demonstração. Último porque o resultado já é útil sem isso.

**Acceptance Scenarios**:

1. **Given** um resultado, **When** a pessoa salva, **Then** ele aparece no
   histórico com data e contagem.
2. **Given** itens no histórico, **When** a pessoa abre um, **Then** vê a
   imagem endireitada e a contagem daquela captura.

---

### Edge Cases

- **A cena muda entre o toque e a foto.** A foto não é o frame que a pessoa
  viu. A transição precisa começar do frame visto e acomodar a diferença.
- **Poucos livros.** Com dois ou três objetos, a geometria da estante é mal
  determinada. É caso de recusar o endireitamento.
- **Livros de alturas muito diferentes.** A linha dos topos deixa de ser reta.
- **Livros deitados**, fora do padrão do dataset.
- **A faixa é quase tão alta quanto larga.** O recorte deixa de fazer sentido.
- **A troca de formato da câmera falha** ou demora demais.
- **Armazenamento cheio** ao salvar no histórico.
- **A pessoa volta durante o carregamento.**

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O sistema MUST capturar uma foto na maior resolução que a câmera
  oferecer, ao toque do botão.
- **FR-002**: O sistema MUST manter a captura ao vivo em 1024×768; a mudança de
  formato acontece apenas durante a captura e é revertida.
- **FR-003**: O sistema MUST exibir indicação de carregamento entre o toque e o
  resultado.
- **FR-004**: O sistema MUST executar **uma** inferência sobre a foto, sem
  ladrilhamento.
- **FR-005**: O sistema MUST estimar a correção de perspectiva a partir das
  **máscaras** dos objetos detectados, não das caixas.
- **FR-006**: O sistema MUST declarar um critério de confiança para a correção,
  e **não aplicá-la** quando não for atingido (**FR-011**).
- **FR-007**: O sistema MUST recortar o resultado à faixa dos objetos, com
  margem.
- **FR-008**: O sistema MUST desenhar as divisões entre objetos adjacentes e a
  contagem total.
- **FR-009**: A transição MUST começar no toque, usando o último frame ao vivo,
  sem aguardar a foto.
- **FR-010**: O sistema MUST substituir a imagem de trabalho pela foto sem salto
  visível quando ela ficar pronta.
- **FR-011**: Quando a correção não for aplicada, o sistema MUST exibir o
  resultado mesmo assim, informando que não foi endireitado.
- **FR-012**: O sistema MUST permitir voltar à câmera, retomando a sessão.
- **FR-013**: O sistema MUST permitir salvar o resultado e listá-lo depois com
  data e contagem.
- **FR-014**: O sistema MUST NOT transportar pixels de foto ou máscara para o
  JavaScript, conforme o princípio II.
- **FR-015**: O sistema MUST permitir arrastar horizontalmente quando a faixa
  não couber na largura.

### Key Entities

- **Captura**: a foto em alta resolução, suas detecções e a transformação de
  perspectiva estimada.
- **Geometria da estante**: o quadrilátero derivado das máscaras, e a medida de
  confiança que decide se ele é usado.
- **Resultado**: a imagem final endireitada e recortada, a contagem, e as
  posições das divisões.
- **Entrada de histórico**: um resultado guardado, com data e contagem.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Do toque ao resultado visível passam menos de **1,5 s**.
- **SC-002**: A transição roda a 60 fps, sem quadro perdido.
- **SC-003**: Numa estante fotografada a até 30° de ângulo, as lombadas do
  resultado aparecem verticais com desvio inferior a 3°.
- **SC-004**: A contagem da foto fica dentro de ±10% da contagem mediana
  observada ao vivo na mesma cena.
- **SC-005**: Ao voltar, a câmera ao vivo retoma em menos de 500 ms e volta a
  60 fps.
- **SC-006**: O endireitamento é recusado em vez de aplicado errado: nenhuma
  captura exibe imagem visivelmente mais torta que a original.
- **SC-007**: Um resultado salvo é recuperável com a mesma imagem e contagem.

## Assumptions

- A estante é fotografada aproximadamente de frente, com inclinação moderada.
  Ângulos extremos são caso de recusa, não de correção.
- Os livros estão em pé, lado a lado — o padrão do dataset.
- A correção de perspectiva é derivada das máscaras porque **caixas alinhadas
  aos eixos não informam inclinação**. É a segmentação pagando por algo que não
  foi pedido a ela.
- A foto em alta resolução melhora a **nitidez** e, por consequência, a
  detecção — não por ter mais pixels, já que a entrada do modelo continua
  640×640, mas por não ter borrão de movimento.
- O histórico é local ao aparelho. Sincronização e nuvem estão fora de escopo.
- Identificar **quais** livros está fora de escopo, por decisão do autor.

## Decisões adiadas

- **Como a faixa é apresentada quando é muito larga.** O arrasto horizontal
  resolve o caso comum; ampliação e redução ficam para depois de ver o
  resultado real.
- **O que mais entra no histórico.** Data e contagem bastam agora. Local,
  anotação e exportação dependem de o histórico provar que é usado.
