# Feature Specification: Overlay de caixas e máscaras

**Feature Branch**: `mobile/003-overlay-mascaras`

**Created**: 2026-09-16

**Status**: Draft

**Input**: User description: "Marco 3 — desenhar sobre o preview. Caixas e também segmentação, nativo em Swift. Portão: overlay a 60 fps sem derrubar a inferência."

> **Mudança de escopo registrada.** A arquitetura original separava caixas
> (marco 3) de máscaras (marco 5). O autor fundiu os dois em 16/09/2026: as
> máscaras são o ponto do projeto, e adiar duas etapas para desenhar retângulos
> tem pouco retorno. Este marco absorve o antigo marco 5.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ver os objetos marcados na imagem (Priority: P1)

O desenvolvedor aponta o aparelho para uma estante e vê cada livro contornado
por uma caixa, sobre a imagem que o modelo recebe.

**Why this priority**: é a primeira vez que o resultado da inferência aparece
como imagem em vez de número. Também é o teste do mapeamento de coordenadas —
a caixa cair sobre o livro certo é a prova de que a geometria está correta do
sensor ao desenho.

**Independent Test**: apontar para a estante e conferir de olho se as caixas
caem sobre os livros.

**Acceptance Scenarios**:

1. **Given** a sessão rodando, **When** o desenvolvedor aponta para uma
   estante, **Then** cada objeto detectado aparece contornado.
2. **Given** objetos detectados, **When** o desenvolvedor move o aparelho,
   **Then** as caixas acompanham os objetos sem atraso perceptível.
3. **Given** uma parede vazia, **When** apontada, **Then** nenhuma caixa é
   desenhada.

---

### User Story 2 - Ver a forma dos objetos, não só a caixa (Priority: P2)

O desenvolvedor vê cada objeto preenchido pela sua silhueta, acompanhando o
contorno real em vez do retângulo que o envolve.

**Why this priority**: é o que o projeto existe para fazer. Detecção diz onde
está; segmentação diz qual é a forma — e num caso de livros lado a lado numa
estante, a diferença entre os dois é grande.

**Independent Test**: com as máscaras ligadas, conferir se a silhueta segue a
lombada do livro e não o retângulo.

**Acceptance Scenarios**:

1. **Given** objetos detectados, **When** as máscaras estão ativas, **Then**
   cada objeto aparece preenchido pela própria silhueta.
2. **Given** objetos adjacentes, **When** segmentados, **Then** cada um recebe
   cor distinta e a fronteira entre eles é visível.
3. **Given** as máscaras desligadas, **When** o desenvolvedor as reativa,
   **Then** a taxa de quadros e a latência voltam ao valor anterior.

---

### User Story 3 - Saber quanto o desenho custa (Priority: P3)

O desenvolvedor precisa saber se desenhar caixas e máscaras derrubou a taxa de
quadros ou a latência medidas no marco 2.

**Why this priority**: a arquitetura inteira se apoia em o desenho nunca
esperar a inferência. Este é o primeiro marco em que existe desenho, e portanto
o primeiro em que esse princípio pode ser violado de fato.

**Independent Test**: comparar a telemetria com e sem overlay, na mesma cena.

**Acceptance Scenarios**:

1. **Given** o overlay ativo, **When** a telemetria é lida, **Then** o custo do
   desenho aparece separado dos demais estágios.
2. **Given** a sessão com overlay, **When** comparada com a do marco 2,
   **Then** taxa de quadros e latência ponta-a-ponta permanecem equivalentes.

---

### Edge Cases

- **Nenhum objeto detectado.** Sem caixas, sem máscaras, sem custo.
- **Muitos objetos ao mesmo tempo.** O custo do desenho cresce com a contagem;
  precisa ser visível na telemetria.
- **Objeto cortado pela borda.** A caixa já é recortada aos limites; a máscara
  precisa do mesmo tratamento.
- **Máscaras sobrepostas.** Objetos adjacentes disputam os mesmos pixels; a
  regra de desempate precisa ser determinística, não dependente de ordem de
  chegada.
- **Aparelho degradando termicamente.** Se a cadência cair, o overlay continua
  desenhando o último resultado — nunca some.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O sistema MUST desenhar uma caixa por objeto detectado, sobre a
  imagem que o modelo recebe.
- **FR-002**: O sistema MUST desenhar a máscara de segmentação de cada objeto,
  acompanhando sua silhueta.
- **FR-003**: O sistema MUST permitir ligar e desligar caixas e máscaras
  independentemente, em execução.
- **FR-004**: O sistema MUST atribuir cor distinta a objetos adjacentes, de
  forma determinística.
- **FR-005**: O sistema MUST recortar as máscaras aos limites da imagem, como
  já faz com as caixas.
- **FR-006**: O sistema MUST reportar o custo do desenho como estágio separado
  na telemetria.
- **FR-007**: O desenho MUST NOT bloquear nem atrasar a inferência.
- **FR-008**: O sistema MUST NOT transportar pixels de máscara para o
  JavaScript, conforme o princípio II.
- **FR-009**: O sistema MUST continuar exibindo o último resultado quando uma
  inferência falhar ou demorar, em vez de apagar o overlay.
- **FR-010**: A aparência do overlay MUST ser ajustável sem recompilar o módulo
  nativo — espessura, opacidade e paleta vêm do TypeScript.

### Key Entities

- **Instância desenhável**: uma detecção com caixa, classe, confiança e os
  coeficientes de máscara que a descrevem.
- **Protótipos de máscara**: a saída `[1, 32, 160, 160]` do modelo. Combinada
  com os coeficientes de uma instância, produz sua silhueta. **Nunca atravessa
  a fronteira.**
- **Estilo do overlay**: espessura, opacidade, paleta e o que está visível.
  Vive em TypeScript.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Com overlay completo ativo, a taxa de quadros processados
  permanece em 60 fps, igual à medida sem overlay.
- **SC-002**: A latência ponta-a-ponta mediana não cresce mais de 15% em
  relação aos 39,6 ms medidos no marco 2.
- **SC-003**: O custo do desenho aparece na telemetria como valor próprio.
- **SC-004**: As caixas caem visivelmente sobre os objetos, sem deslocamento
  sistemático.
- **SC-005**: As máscaras seguem a silhueta dos objetos, distinguíveis da caixa
  que os envolve.
- **SC-006**: Ligar e desligar o overlay altera a telemetria de forma
  consistente com o custo reportado.

## Assumptions

- O preview mostra o buffer transformado 640×640, então as coordenadas do
  modelo mapeiam **1 para 1** na área de desenho. Nenhuma conversão de
  geometria é necessária — consequência direta da decisão de preview do
  marco 2.
- O desenho é nativo, em Swift, sobre a `PreviewView` existente. Skia e
  Reanimated permanecem fora do projeto.
- As máscaras podem ser compostas na resolução dos protótipos (160×160) e
  ampliadas na exibição: é o que o Ultralytics faz, então não há perda em
  relação à referência.
- Suavização, rastreamento e identidade estável **não** pertencem a este marco.
  Com inferência a 60 fps, o overlay cru pode já parecer fluido — e essa é a
  observação que decide o futuro do marco 4.

## Decisões adiadas

- **O futuro do marco 4.** A arquitetura previa tracker, Kalman e compensação
  de movimento para tornar convincente o intervalo entre detecções. A 60 fps
  esse intervalo é de um frame. Este marco entrega o overlay **sem suavização
  nenhuma**, de propósito: se parecer fluido, o marco 4 encolhe para rede de
  segurança térmica. A decisão é visual e não vale antecipar.
- **Como as máscaras são compostas.** Multiplicação de matriz com Accelerate na
  resolução dos protótipos, ou shader de computação em Metal. A primeira é
  muito mais barata de construir; a segunda é o que a arquitetura previa.
  Começar pela primeira e medir.
