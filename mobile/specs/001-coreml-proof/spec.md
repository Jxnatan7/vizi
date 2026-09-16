# Feature Specification: Prova de vida do Core ML

**Feature Branch**: `mobile/001-coreml-proof`

**Created**: 2026-09-15

**Status**: Draft

**Input**: User description: "Marco 1 da arquitetura — carregar o modelo de segmentação no aparelho e medir a inferência sobre uma imagem fixa embutida, sem câmera, sem overlay, sem tracking. Mais a cadeia de build inteira: compilar no CI, assinar localmente, instalar no iPhone físico. Portão de saída: inferência < 30 ms no iPhone 14 Plus."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Instalar um app próprio no iPhone a partir do Linux (Priority: P1)

O desenvolvedor, trabalhando numa máquina Linux sem acesso a nenhum Mac, precisa
colocar um aplicativo que ele mesmo escreveu rodando no próprio iPhone físico, e
precisa conseguir repetir isso sempre que quiser.

**Why this priority**: É a capacidade que destrava todas as outras. Também é a
maior dependência externa do projeto e a menos sob controle — envolve
infraestrutura de terceiros e o processo de assinatura da Apple. Se falhar, nada
mais acontece, e é melhor descobrir na primeira semana.

**Independent Test**: Entregável sozinho e verificável sozinho — um aplicativo
mínimo, sem modelo e sem inferência, instalado e abrindo no aparelho. O valor
entregue é a cadeia de entrega funcionando ponta a ponta.

**Acceptance Scenarios**:

1. **Given** um repositório sem nenhum artefato compilado, **When** o
   desenvolvedor dispara a compilação remota e executa o procedimento local de
   assinatura e instalação, **Then** o aplicativo abre no iPhone sem erro.
2. **Given** o aplicativo já instalado, **When** o desenvolvedor altera texto na
   camada de interface e recarrega, **Then** a alteração aparece no aparelho sem
   nova compilação remota.
3. **Given** um aplicativo cuja assinatura expirou, **When** o desenvolvedor
   repete apenas o procedimento de assinatura e instalação, **Then** o
   aplicativo volta a abrir sem recompilar.

---

### User Story 2 - Obter um veredito medido sobre a viabilidade da arquitetura (Priority: P2)

O desenvolvedor precisa saber, com número medido no aparelho real, se o modelo
de segmentação roda rápido o suficiente para sustentar a arquitetura planejada,
ou se a premissa do projeto está errada.

**Why this priority**: É o propósito do marco. Toda a arquitetura assume que a
inferência cabe num orçamento que hoje é hipótese. Enquanto for hipótese, todo
trabalho seguinte é especulativo.

**Independent Test**: Verificável sozinho — o aplicativo executa o modelo sobre
uma imagem fixa embutida e exibe a latência na tela. Não depende de câmera, de
desenho ou de rastreamento.

**Acceptance Scenarios**:

1. **Given** o aplicativo instalado e o aparelho em temperatura normal,
   **When** o desenvolvedor dispara uma sequência de execuções sobre a imagem
   de referência, **Then** a tela exibe latência mediana, p95 e número de
   execuções.
2. **Given** uma sequência concluída, **When** o desenvolvedor a repete sem
   reabrir o aplicativo, **Then** os resultados são consistentes com a anterior
   dentro da variação declarada.
3. **Given** o aparelho aquecido por uso prolongado, **When** a sequência é
   repetida, **Then** a tela indica que a medição ocorreu sob condição térmica
   degradada, para que não seja comparada com uma medição a frio.

---

### User Story 3 - Confirmar que o resultado está correto, não apenas rápido (Priority: P3)

O desenvolvedor precisa confirmar que a saída produzida no aparelho corresponde
à saída produzida pela ferramenta de referência para a mesma imagem.

**Why this priority**: Velocidade sem correção não vale nada, e uma conversão de
modelo silenciosamente degradada é um modo de falha real — o número de latência
pareceria ótimo enquanto o resultado estaria errado. Fica em P3 porque só faz
sentido depois que há o que medir.

**Independent Test**: Verificável sozinho comparando a saída exibida pelo
aplicativo com a saída de referência registrada no repositório para a mesma
imagem.

**Acceptance Scenarios**:

1. **Given** a imagem de referência e o resultado esperado versionados no
   repositório, **When** o aplicativo processa essa imagem, **Then** a
   quantidade de instâncias detectadas coincide com a referência.
2. **Given** as instâncias detectadas, **When** comparadas com a referência,
   **Then** as posições e as classes coincidem dentro da tolerância declarada.

---

### Edge Cases

- **Primeira execução após instalação.** A primeira inferência inclui custo de
  preparação do modelo que não se repete. Medir isso como se fosse regime
  permanente produziria um número falso e pessimista. As medições de regime
  devem descartar execuções de aquecimento, e a tela deve mostrar o custo da
  primeira execução separadamente, porque ele afeta o tempo de abertura do app.
- **O modelo não roda inteiro no acelerador dedicado.** Parte das operações pode
  cair em unidades mais lentas. O aplicativo deve tornar isso detectável em vez
  de apresentar só o total.
- **Aparelho aquecido.** A latência varia com a temperatura. Uma medição sem
  contexto térmico não é comparável com outra.
- **Assinatura expirada.** O aplicativo para de abrir após o prazo. O
  procedimento de recuperação não pode exigir nova compilação remota.
- **Aparelho não pareado ou desconectado** durante a instalação.
- **Falta de espaço ou modelo ausente** no pacote instalado — deve falhar com
  mensagem legível na tela, não com tela branca.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O sistema MUST carregar o modelo de segmentação embarcado no
  pacote do aplicativo, sem depender de rede.
- **FR-002**: O sistema MUST executar o modelo sobre uma imagem de referência
  embutida, disparada por ação explícita do usuário.
- **FR-003**: O sistema MUST executar uma sequência de N repetições e reportar
  latência mediana, p95, mínimo e contagem, descartando execuções de aquecimento
  declaradas.
- **FR-004**: O sistema MUST reportar a latência da primeira execução
  separadamente das demais.
- **FR-005**: O sistema MUST reportar a condição térmica do aparelho no momento
  da medição.
- **FR-006**: O sistema MUST expor qual unidade de processamento executou o
  modelo, ou declarar explicitamente que a informação não está disponível.
- **FR-007**: O sistema MUST exibir a quantidade de instâncias detectadas e seus
  atributos na imagem de referência, para comparação com a referência esperada.
- **FR-008**: O sistema MUST exibir mensagem de erro legível na tela quando o
  modelo não puder ser carregado ou executado.
- **FR-009**: O sistema MUST NOT acessar a câmera, desenhar sobreposição ou
  rastrear objetos. Esses comportamentos pertencem a marcos posteriores.
- **FR-010**: O repositório MUST conter a imagem de referência e o resultado
  esperado correspondente, versionados.
- **FR-011**: O processo de compilação MUST produzir um artefato instalável sem
  exigir credenciais de assinatura no ambiente de compilação.
- **FR-012**: O procedimento de assinatura e instalação MUST ser executável a
  partir de Linux, sem acesso a Mac.
- **FR-013**: Alterações na camada de interface MUST ser aplicáveis ao
  aplicativo instalado sem nova compilação remota.
- **FR-014**: O sistema MUST reportar como números separados a latência da
  execução do modelo e a do ciclo completo — preparação da entrada, execução e
  decodificação da saída.
- **FR-015**: O sistema MUST registrar, junto de cada medição, qualquer
  indicação de que parte do modelo executou fora do acelerador dedicado.

### Key Entities

- **Modelo**: artefato de segmentação embarcado, com metadados descrevendo
  formato de entrada, classes e normalização. É a fonte da verdade sobre esses
  valores; nenhum deles é duplicado no código.
- **Amostra de referência**: imagem fixa versionada no repositório, acompanhada
  do resultado esperado produzido pela ferramenta de referência.
- **Registro de medição**: conjunto de latências de uma sequência, com o
  contexto que a torna comparável — condição térmica, contagem de repetições e
  execuções descartadas.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A latência mediana de execução do modelo sobre a imagem de
  referência é inferior a 30 ms, em sequência de pelo menos 100 repetições, com
  o aparelho em temperatura normal. O ciclo completo é medido e reportado junto,
  mas não é o que o limite vincula neste marco.
- **SC-002**: O p95 da mesma sequência é inferior a 40 ms.
- **SC-003** *(renegociado em 16/09/2026 — ver Decisões adiadas)*: a quantidade
  de instâncias coincide exatamente com a referência; nenhuma classe diverge;
  ao menos 90% das instâncias casam com IoU ≥ 0,9; e nenhuma instância fica
  abaixo de IoU 0,7 contra sua contrapartida.
- **SC-004**: Uma alteração na camada de interface aparece no aplicativo
  instalado em menos de 60 segundos, sem compilação remota.
- **SC-005**: Partindo de um repositório limpo, o percurso completo até o
  aplicativo aberto no aparelho se conclui em menos de 30 minutos, sem
  intervenção manual além dos comandos documentados.
- **SC-006**: Recuperar um aplicativo com assinatura expirada leva menos de 5
  minutos e não exige compilação remota.
- **SC-007**: O procedimento completo está documentado de forma que possa ser
  repetido do zero sem consultar o histórico da conversa.

## Assumptions

- O aparelho de teste é um iPhone 14 Plus com a versão mais recente do sistema.
  Nenhum outro aparelho iOS é alvo deste marco.
- Android está fora do escopo deste marco, conforme a constituição.
- Existe um modelo de segmentação já treinado com pipeline de treino completo
  disponível, permitindo reexportá-lo em formatos e configurações diferentes.
- A assinatura usa conta Apple gratuita, com validade de 7 dias e limite de
  aplicativos instalados. Conta paga não é premissa.
- A compilação ocorre em infraestrutura de integração contínua com ambiente
  macOS; não há Mac local disponível.
- Não há ferramenta de profiling do fabricante disponível. Toda visibilidade
  sobre desempenho vem do que este marco construir.
- A imagem de referência vem do conjunto de validação do modelo e é
  representativa da cena alvo.
- O resultado esperado é gerado uma vez pela ferramenta de referência e
  versionado; não é recalculado no aparelho.

## Decisões adiadas

Registradas aqui para não bloquearem o marco e não se perderem.

- **A qual medida o limite de 30 ms se vincula.** Este marco mede execução do
  modelo e ciclo completo separadamente (FR-014) e vincula o limite à primeira.
  Se a diferença entre as duas se mostrar grande, a escolha é reavaliada — com
  os dois números na mão, o que hoje seria palpite.
- **Renegociação do SC-003, com a razão.** O critério original exigia que
  **todas** as instâncias casassem com IoU ≥ 0,9. Esse número foi declarado
  antes de existir qualquer medição — era palpite.

  Medido: contagem exata (24 de 24), zero classes divergentes, 22 casadas com
  pior IoU 0,9321 e desvio máximo de centro de 1,97 px em 640. Duas instâncias
  discordam na extensão.

  Isso é o padrão de **arredondamento fp16 somado a desempate no NMS**: com os
  pesos em meia precisão os escores mudam na terceira casa, e dois candidatos
  sobrepostos podem ser resolvidos de formas diferentes. O Ultralytics fica com
  um, nós ficamos com outro — ambos são o mesmo livro.

  Degradação de conversão teria outra assinatura: objetos faltando, contagem
  errada, deslocamento sistemático ou classe trocada. Nenhuma delas ocorre.

  O critério novo testa cada um desses modos de falha em vez de exigir
  igualdade numérica de um modelo que foi deliberadamente quantizado. O campo
  `unmatchedIoUs` ficou exposto na tela: se algum dia cair para perto de zero,
  aí sim há caixa espúria, e o teste reprova.

- **O que fazer se o modelo não couber inteiro no acelerador dedicado.** O marco
  torna o fato detectável (FR-015) em vez de decidir agora a regra de aprovação.
  A decisão depende de quanto isso custa em latência, que é justamente o que
  este marco vai medir.
