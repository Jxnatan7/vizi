---
description: "Task list for Prova de vida do Core ML"
---

# Tasks: Prova de vida do Core ML

**Input**: Design documents from `/specs/001-coreml-proof/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: sem tarefas de teste automatizado. A spec estabelece que não há suíte
neste marco — não é possível exercitar o acelerador dedicado num runner de CI, e
a verificação é manual no aparelho contra referência versionada.

**Organization**: agrupadas por história de usuário, em ordem de prioridade.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: paralelizável — arquivo diferente, sem dependência pendente
- **[US1/US2/US3]**: história correspondente

## Path Conventions

Caminhos relativos a `mobile/`, a raiz deste projeto no monorepo.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: colocar o projeto Expo de pé sem destruir o que já existe.

- [ ] T001 Criar projeto Expo em `mobile/`, preservando `.specify/`, `.claude/`, `README.md` e `.gitignore` já presentes
- [ ] T002 Configurar `mobile/app.config.js` com identificador de pacote, nome e o plugin do dev client
- [ ] T003 Instalar `expo-dev-client` e registrar em `mobile/package.json`
- [ ] T004 [P] Criar `mobile/.github/workflows/ios.yml` com o esqueleto do job macOS (checkout, node, prebuild)
- [ ] T005 [P] Adicionar atalhos do mobile ao `package.json` da raiz do monorepo

**Checkpoint**: `npx expo start` roda e o projeto compila localmente até onde Linux permite.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: garantir que a US1 valide o que realmente importa.

**⚠️ CRITICAL**: sem isto, a US1 passaria com um app 100% JavaScript e a US2
descobriria que o build quebra ao adicionar código nativo.

- [ ] T006 Criar o Expo Module local `mobile/modules/vizi-vision/` com `expo-module.config.json`
- [ ] T007 Criar `mobile/modules/vizi-vision/ios/ViziVisionModule.swift` expondo uma função trivial, só para exercitar o autolinking
- [ ] T008 Criar `mobile/modules/vizi-vision/src/index.ts` com a API tipada conforme `contracts/vizi-vision.md`, ainda sem implementação
- [ ] T009 Chamar a função trivial em `mobile/App.tsx` e exibir o retorno na tela

**Checkpoint**: existe código Swift próprio no binário. Agora a US1 valida a cadeia de verdade.

---

## Phase 3: User Story 1 - Instalar um app próprio no iPhone a partir do Linux (Priority: P1) 🎯 MVP

**Goal**: cadeia de entrega funcionando ponta a ponta, de `git push` ao app aberto no aparelho.

**Independent Test**: o app abre no iPhone e mostra o retorno da função nativa trivial. Sem modelo, sem inferência.

### Implementation for User Story 1

- [ ] T010 [US1] Completar `mobile/.github/workflows/ios.yml`: `pod install`, `xcodebuild` sem assinatura, empacotar em `Payload/`, publicar o `.ipa` como artefato — resolve **R4**
- [ ] T011 [US1] Instalar e validar a cadeia de ferramentas local de assinatura e instalação em Linux — resolve **R1**, o maior risco do marco
- [ ] T012 [US1] Obter certificado e perfil de provisionamento com a conta Apple gratuita
- [ ] T013 [US1] Assinar o artefato e instalar no iPhone por USB
- [ ] T014 [US1] Verificar **SC-004**: alterar texto em `mobile/App.tsx` e confirmar que aparece sem recompilar
- [ ] T015 [US1] Verificar **SC-006**: re-assinar e reinstalar o mesmo artefato sem passar pelo CI
- [ ] T016 [US1] Preencher as seções 🔬 de `specs/001-coreml-proof/quickstart.md` com o procedimento real

**Checkpoint**: 🚦 **Portão de risco.** Se T011–T013 não fecharem, parar e reavaliar antes de investir na US2. A saída é conta Apple paga.

---

## Phase 4: User Story 2 - Obter um veredito medido sobre a viabilidade (Priority: P2)

**Goal**: número medido no aparelho que aprova ou reprova a premissa da arquitetura.

**Independent Test**: o app executa o modelo sobre a imagem embarcada e exibe mediana, p95, primeira execução, condição térmica e unidade de execução.

### Implementation for User Story 2

- [x] T017 [P] [US2] Exportar o modelo no Colab conforme `quickstart.md` e commitar `mobile/models/vizi-seg.mlpackage/` — feito 15/09, `imgsz=640`, shapes em `models/vizi-seg.shapes.md`
- [x] T018 [P] [US2] Adicionar `mobile/assets/reference.jpg` do conjunto de validação — feito, 640×640, idêntico à entrada do modelo
- [ ] T019 [US2] Incluir modelo e imagem como recursos do bundle via config plugin em `mobile/app.config.js` — a pasta nativa não é versionada
- [ ] T020 [US2] Implementar carga do modelo em `mobile/modules/vizi-vision/ios/InferenceEngine.swift` — resolve **R3**
- [ ] T021 [US2] Implementar execução sobre a imagem embarcada, fora da thread de interface (princípio I)
- [ ] T022 [US2] Implementar `Decode.swift` em `mobile/modules/vizi-vision/ios/`: saída crua → instâncias, com NMS
- [ ] T023 [US2] Instrumentar latências: primeira execução isolada (**FR-004**), e execução do modelo separada do ciclo completo (**FR-014**)
- [ ] T024 [P] [US2] Reportar condição térmica do aparelho (**FR-005**)
- [ ] T025 [US2] Detectar e reportar a unidade que executou o modelo, ou declarar indisponível (**FR-006**, **FR-015**) — resolve **R2**
- [ ] T026 [P] [US2] Implementar `mobile/src/bench/stats.ts`: mediana, p95, mínimo
- [ ] T027 [US2] Implementar `mobile/src/bench/runBenchmark.ts` com a política — repetições, descarte, limiar (princípio IV: nenhuma dessas constantes no Swift)
- [ ] T028 [US2] Implementar `mobile/src/ui/BenchScreen.tsx`: botão, resultados e mensagem de erro legível na tela (**FR-008**)
- [ ] T029 [US2] Caracterizar o aquecimento: registrar as 20 primeiras latências e fixar o número de descarte — resolve **R5**
- [ ] T030 [US2] 🚦 **Medir o portão**: 100 repetições, aparelho frio, e conferir **SC-001** (mediana < 30 ms) e **SC-002** (p95 < 40 ms)

**Checkpoint**: o veredito existe. Este é o propósito do marco.

---

## Phase 5: User Story 3 - Confirmar que o resultado está correto (Priority: P3)

**Goal**: garantir que a conversão do modelo não degradou a saída silenciosamente.

**Independent Test**: as instâncias exibidas pelo app batem com o JSON de referência versionado.

### Implementation for User Story 3

- [x] T031 [US3] Gerar a saída de referência no Colab e commitar `mobile/assets/reference-expected.json` (**FR-010**) — feito, 24 instâncias, conf 0,361–0,922
- [ ] T032 [US3] Exibir as instâncias detectadas em `mobile/src/ui/BenchScreen.tsx` (**FR-007**)
- [ ] T033 [US3] Comparar com a referência e verificar **SC-003**: contagem exata, posições e classes dentro da tolerância

**Checkpoint**: rápido **e** correto. As três histórias funcionam de forma independente.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T034 [P] Registrar os números medidos em `specs/001-coreml-proof/research.md`, fechando R1–R5
- [ ] T035 [P] Confirmar **SC-005**: percurso do zero ao app aberto em menos de 30 min, seguindo apenas o `quickstart.md`
- [ ] T036 Auditar a fronteira: nenhum buffer acima de 64 KB atravessa para o JavaScript (princípio II)
- [ ] T037 Auditar o Swift: nenhuma constante de política (princípio IV)
- [ ] T038 Verificar **FR-009**: o app não acessa câmera, não desenha sobreposição e não rastreia
- [ ] T039 Atualizar `mobile/README.md` com o estado do marco e o veredito

---

## Dependencies

```
Setup (T001-T005)
   └─► Foundational (T006-T009)   ⚠️ bloqueia tudo
          └─► US1 (T010-T016)     🚦 portão de risco — R1
                 └─► US2 (T017-T030)   🚦 portão do marco — SC-001
                        └─► US3 (T031-T033)
                               └─► Polish (T034-T039)
```

**As histórias são sequenciais neste marco, não paralelas.** A US2 precisa
instalar no aparelho para medir, e a US3 precisa da decodificação que a US2
constrói. A independência que a spec exige é de *verificação* — cada história é
testável sozinha depois de pronta — não de execução.

## Parallel Execution Examples

**Setup**: T004 e T005 rodam junto com T002–T003.

**US2, aquisição de artefatos**: T017 e T018 são independentes entre si e podem
acontecer enquanto T019–T021 são escritos.

**US2, instrumentação**: T024 (térmico) e T026 (estatísticas) tocam arquivos
diferentes e não dependem um do outro.

**Polish**: T034 e T035 em paralelo; T036–T038 são auditorias independentes.

## Implementation Strategy

**MVP é a US1, não a US2.** O mínimo que entrega valor é a cadeia de entrega
funcionando — ela destrava todo o resto e carrega o maior risco externo do
projeto. Um app que só imprime o retorno de uma função Swift já vale o esforço
se provar que dá para instalar no aparelho a partir de Linux.

**Dois portões, em ordem de custo.** T011–T013 custam pouco e podem matar o
marco; T030 custa caro e decide a arquitetura. Nesta ordem, um fracasso barato
evita um investimento caro.

**Cada fase é um ponto de parada honesto.** Se a US2 reprovar em T030, a US3 não
deve ser construída — a arquitetura muda primeiro.
