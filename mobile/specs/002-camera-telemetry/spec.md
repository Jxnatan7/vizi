# Feature Specification: Câmera ao vivo e telemetria

**Feature Branch**: `mobile/002-camera-telemetry`

**Created**: 2026-09-16

**Status**: Draft

**Input**: User description: "Marco 2 — frames reais da câmera entrando no modelo, inferência a cada frame, e a telemetria que torna o comportamento diagnosticável. Sem desenhar detecções. Portão: 10 minutos de inferência contínua sem sair do envelope térmico."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ver a cena sendo processada em tempo real (Priority: P1)

O desenvolvedor aponta o aparelho para uma estante e vê, na tela, a imagem da
câmera e uma contagem de objetos que muda conforme ele se move — sem nenhum
desenho sobre a imagem.

**Why this priority**: é o primeiro momento em que o sistema processa o mundo
em vez de uma imagem fixa. Também é o que revela, de olho, se o recorte da
câmera para a entrada do modelo está certo — a única coisa deste marco que não
tem como ser verificada por número.

**Independent Test**: apontar para a cena de referência e conferir se a
contagem é plausível e reage ao movimento.

**Acceptance Scenarios**:

1. **Given** o app aberto com permissão de câmera concedida, **When** o
   desenvolvedor aponta para uma estante, **Then** a imagem aparece na tela e a
   contagem de objetos é exibida como número.
2. **Given** a câmera ativa, **When** o desenvolvedor move o aparelho para uma
   parede vazia, **Then** a contagem cai para zero ou perto disso.
3. **Given** a permissão de câmera negada, **When** o app abre, **Then** a tela
   explica o que falta e como conceder, em vez de ficar preta.

---

### User Story 2 - Saber se o aparelho aguenta uso contínuo (Priority: P2)

O desenvolvedor precisa descobrir se inferir a cada frame é sustentável, ou se
o aparelho esquenta a ponto de degradar — e em quanto tempo.

**Why this priority**: é a pergunta que o marco existe para responder. A
3,1 ms a inferência cabe no orçamento com folga; **o limite deixou de ser tempo
e passou a ser calor e bateria**, e isso nunca foi medido neste projeto.

**Independent Test**: deixar o app rodando por 10 minutos apontado para uma
cena estável e ler o registro ao fim.

**Acceptance Scenarios**:

1. **Given** o aparelho em temperatura normal, **When** o app infere
   continuamente por 10 minutos, **Then** a tela mostra a evolução do estado
   térmico, da latência e da taxa de quadros ao longo do período.
2. **Given** uma sessão concluída, **When** o desenvolvedor a examina, **Then**
   consegue dizer em que minuto cada mudança de estado térmico ocorreu.
3. **Given** o aparelho entrando em estado térmico grave, **When** isso ocorre,
   **Then** o registro marca o instante — sem que o app tome nenhuma ação
   corretiva, que pertence a marco posterior.

---

### User Story 3 - Confiar que o frame da câmera vira entrada correta (Priority: P3)

O desenvolvedor precisa confirmar que a transformação do frame da câmera para o
formato de entrada do modelo reproduz a geometria em que o modelo foi treinado.

**Why this priority**: a câmera entrega 4:3 e o modelo espera 640×640 quadrado.
A transformação é uma escolha, e a escolha errada degrada em silêncio — o mesmo
modo de falha que custou duas rodadas no marco 1. Fica em P3 porque depende de
haver captura funcionando.

**Independent Test**: com as três transformações selecionáveis, apontar para a
mesma cena e comparar a contagem e a estabilidade das detecções.

**Acceptance Scenarios**:

1. **Given** as transformações disponíveis, **When** o desenvolvedor alterna
   entre elas apontando para a mesma cena, **Then** a contagem de cada uma é
   exibida para comparação.
2. **Given** a transformação que reproduz o dataset, **When** aplicada à cena
   de referência, **Then** a contagem se aproxima da obtida sobre a imagem
   embarcada no marco 1.

---

### Edge Cases

- **Permissão de câmera negada ou revogada durante o uso.**
- **App em segundo plano e retornando.** A câmera deve parar ao sair e retomar
  ao voltar; continuar inferindo em segundo plano gastaria bateria sem entregar
  nada.
- **Aparelho já quente ao iniciar.** A sessão precisa registrar o estado
  térmico inicial, ou a medição não é comparável com outra.
- **Cena sem nenhum objeto.** Contagem zero é resultado válido, não erro.
- **Modo de baixo consumo ativo.** Pode limitar desempenho; deve constar no
  registro.
- **A câmera entrega frames mais rápido do que a inferência consome.** Frames
  não consumidos são descartados, nunca enfileirados.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O sistema MUST exibir a imagem da câmera traseira em tempo real.
- **FR-002**: O sistema MUST NOT desenhar caixas, máscaras ou qualquer marcação
  sobre a imagem. Isso pertence ao marco 3.
- **FR-003**: O sistema MUST executar o modelo sobre os frames capturados, sem
  limitar artificialmente a cadência.
- **FR-004**: O sistema MUST descartar frames não consumidos em vez de
  enfileirá-los, mantendo no máximo um frame pendente.
- **FR-005**: O sistema MUST oferecer, como opção selecionável, as três
  transformações de frame para a entrada do modelo: esticar, recortar no centro
  e letterbox.
- **FR-006**: O sistema MUST registrar, ao longo da sessão: latência de
  inferência, latência ponta-a-ponta, taxa de quadros capturados, taxa de
  frames descartados, estado térmico e nível de bateria.
- **FR-007**: O sistema MUST registrar o instante de cada mudança de estado
  térmico.
- **FR-008**: O sistema MUST exibir a contagem de objetos detectados, como
  número, atualizada continuamente.
- **FR-009**: O sistema MUST medir a latência ponta-a-ponta a partir do
  timestamp de apresentação do próprio frame, não do momento em que o
  processamento começou.
- **FR-010**: O sistema MUST interromper captura e inferência quando o app sai
  de primeiro plano, e retomar ao voltar.
- **FR-011**: O sistema MUST exibir mensagem legível quando a permissão de
  câmera estiver ausente, incluindo como concedê-la.
- **FR-012**: O sistema MUST NOT transportar frames, tensores ou máscaras para
  o JavaScript, conforme o princípio II.
- **FR-013**: O sistema MUST permitir exportar o registro da sessão como texto,
  para que uma medição possa ser versionada.

### Key Entities

- **Frame**: imagem capturada, com o timestamp de apresentação que a acompanha
  por todo o percurso. É o que torna a latência ponta-a-ponta mensurável em vez
  de estimada.
- **Transformação de entrada**: a regra que converte o frame no formato que o
  modelo espera. Esticar, recortar no centro ou letterbox.
- **Amostra de telemetria**: uma leitura periódica do estado do sistema —
  latências, taxas, térmico, bateria — com o instante em que foi tomada.
- **Sessão**: a série de amostras de uma execução contínua, com as condições
  iniciais que a tornam comparável com outra.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Após 10 minutos de inferência contínua com o aparelho começando
  em temperatura normal, o estado térmico não ultrapassa `fair`.
- **SC-002**: Ao longo desses 10 minutos, a latência mediana de inferência não
  cresce mais de 50% em relação aos primeiros 30 segundos.
- **SC-003**: A taxa de quadros processados se mantém estável, sem queda
  sustentada superior a 20% em relação ao primeiro minuto.
- **SC-004**: A profundidade da fila de frames permanece em no máximo 1 durante
  toda a sessão.
- **SC-005**: A latência ponta-a-ponta mediana fica abaixo de 80 ms.
- **SC-006**: Apontado para a cena de referência, a transformação escolhida
  produz contagem dentro de ±20% da obtida sobre a imagem embarcada no marco 1.
- **SC-007**: O consumo de bateria em 10 minutos de uso contínuo é registrado em
  pontos percentuais.

## Assumptions

- O aparelho de teste é o iPhone 14 Plus com iOS 26.5. Android permanece fora de
  escopo.
- A câmera traseira padrão, sem zoom, é a mesma usada para construir o dataset —
  logo o campo de visão é comparável.
- O dataset foi construído no Roboflow a partir de fotos desse aparelho, com
  aumento de dados. **A opção de redimensionamento usada no Roboflow ainda não
  foi confirmada**; por isso as três transformações são implementadas e
  comparadas no aparelho, em vez de uma ser escolhida por suposição.
- Nenhuma ação corretiva automática é esperada neste marco. O controlador
  adaptativo pertence ao marco 6; aqui só se mede.
- Desenhar detecções está fora de escopo por decisão, não por limitação.
- O registro da sessão não é persistido entre aberturas do app; exportar como
  texto é suficiente.

## Decisões adiadas

- **Se vale inferir a cada frame em produção.** Este marco mede o custo de
  fazê-lo. A decisão depende do número que ele produzir, e a alternativa —
  limitar a cadência ou disparar por movimento — é barata de acrescentar depois.
- **Qual transformação de entrada fica como padrão.** Depende da comparação no
  aparelho e da confirmação do Roboflow. O marco entrega as três e o dado; a
  escolha se fixa quando houver ambos.
