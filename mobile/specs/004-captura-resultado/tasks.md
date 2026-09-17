---
description: "Task list for Captura e resultado endireitado"
---

# Tasks: Captura e resultado endireitado

**Input**: Design documents from `/specs/004-captura-resultado/`

**Tests**: sem suíte automatizada. Verificação visual e medição de latência no
aparelho, **em Release**.

## Format: `[ID] [P?] [Story] Description`

## Path Conventions

Caminhos relativos a `mobile/`.

---

## Phase 1: Setup

- [x] T001 [P] Criar `src/capture/options.ts` com `CaptureOptions` — margem, limiares e duração da animação (princípio IV) — `src/capture/options.ts`; limiares de geometria são palpites até a T024
- [x] T002 [P] Acrescentar `CaptureOptions`, `CaptureResult` e `HistoryEntry` aos tipos do módulo — `CaptureOptions` e `CaptureResult` tipados
- [x] T003 Botão de captura na `CameraScreen`, ainda sem ação — botão de captura, com estado de carregamento

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: conseguir uma foto em resolução máxima e voltar ao vivo inteiro.

**⚠️ CRITICAL**: se a sessão não retomar a 60 fps, todo o resto é inútil — o app passa a degradar a cada captura.

- [x] T004 Criar `modules/vizi-vision/ios/PhotoCapture.swift`: `AVCapturePhotoOutput`, troca de formato, captura, restauração — resolve **R17** — troca de formato, captura sem compressão, restauração garantida por `defer`
- [x] T005 Congelar a última imagem ao vivo no instante do toque, antes de qualquer reconfiguração — `PreviewSink.frozen`: para de enfileirar e a última imagem permanece
- [x] T006 Expor `capture` e `dismissResult` no módulo, com erro legível — `capture` e `dismissResult` no módulo, com erro legível
- [x] T007 🚦 Medir a ida e volta da troca de formato e confirmar que a câmera retoma a **60 fps** (**SC-005**) — **passou**: queda para ~50 fps durante a captura, recuperação completa a 60 fps em seguida, sustentada por 36 s

**Checkpoint**: dá para tirar uma foto e voltar, sem degradar a sessão.

---

## Phase 3: User Story 1 - Capturar e saber quantos (Priority: P1) 🎯 MVP

**Goal**: apertar o botão e receber a contagem daquela foto.

**Independent Test**: apontar, apertar, conferir se o número bate com a estante.

- [x] T008 [US1] Inferir sobre a foto — **uma vez, sem ladrilhar** (FR-004) — uma inferência, pela **mesma** transformação do caminho ao vivo
- [ ] T009 [US1] Recortar à união das caixas com a margem do estilo (FR-007)
- [ ] T010 [US1] Estado de resultado na `PreviewView`, ainda sem endireitar nem animar
- [x] T011 [US1] Cromo do resultado em React: contagem, voltar (FR-012) — contagem, tamanho da foto, tempo e motivo da recusa
- [ ] T012 [US1] Caso sem objetos: informar, em vez de mostrar faixa vazia
- [ ] T013 [US1] 🚦 Verificar **SC-004**: contagem da foto dentro de ±10% da contagem ao vivo na mesma cena

**Checkpoint**: o app faz algo por alguém. Primeira vez no projeto.

---

## Phase 4: User Story 2 - Ver os livros retos (Priority: P2)

**Goal**: perspectiva corrigida, ou recusa honesta.

**Independent Test**: fotografar de ângulo e conferir se as lombadas ficam verticais.

- [ ] T014 [US2] Criar `ShelfGeometry.swift`: PCA por máscara, eixo principal e extremos — resolve **R14**
- [ ] T015 [US2] Ajustar retas às nuvens de topos e bases, e fechar o quadrilátero
- [ ] T016 [US2] Calcular a confiança a partir dos cinco sinais — resolve **R15**
- [ ] T017 [US2] Desenhar o quadrilátero estimado sobre a foto, como ferramenta de diagnóstico
- [ ] T018 [US2] Derivar a homografia e aplicá-la ao recorte
- [ ] T019 [US2] Recusar abaixo do limiar, com motivo legível para a tela (**FR-011**)
- [ ] T020 [US2] Desenhar as divisões entre objetos adjacentes (**FR-008**)
- [ ] T021 [US2] Arrasto horizontal quando a faixa não couber (**FR-015**)
- [ ] T022 [US2] 🚦 Verificar **SC-003**: lombadas verticais com desvio < 3° a até 30° de ângulo
- [ ] T023 [US2] 🚦 Verificar **SC-006**: forçar casos ruins e confirmar que **recusa em vez de errar**
- [ ] T024 [US2] Calibrar os limiares com as capturas ruins, e registrar os números

**Checkpoint**: o resultado é confiável — inclusive quando se recusa a entregar.

---

## Phase 5: User Story 3 - A transição (Priority: P3)

**Goal**: a animação que faz o app parecer bom.

- [ ] T025 [US3] Decompor a homografia em `CATransform3D` — resolve **R16**
- [ ] T026 [US3] Animar do estado ao vivo ao resultado: recorte, aproximação e endireitamento
- [ ] T027 [US3] Começar a animação **no toque**, com o frame congelado (**FR-009**)
- [ ] T028 [US3] Substituir pelo frame de alta resolução sem salto (**FR-010**)
- [ ] T029 [US3] Animar a volta, em `dismissResult`
- [ ] T030 [US3] 🚦 Verificar **SC-001** (< 1,5 s) e **SC-002** (60 fps na transição)

**Checkpoint**: a captura deixou de parecer uma troca de tela.

---

## Phase 6: User Story 4 - Histórico (Priority: P4)

- [ ] T031 [US4] Criar `src/history/store.ts`: imagens em arquivo, índice em JSON
- [ ] T032 [US4] `saveResult` grava a imagem e devolve a entrada (**FR-013**)
- [ ] T033 [US4] Criar `src/ui/HistoryScreen.tsx` com a lista
- [ ] T034 [US4] Abrir uma entrada e ver imagem e contagem (**SC-007**)

---

## Phase 7: Polish & Cross-Cutting

- [ ] T035 [P] Registrar as medições em `research.md`, fechando R14–R17
- [ ] T036 Auditar a fronteira: nenhum pixel atravessa; `imageId` em vez de imagem
- [ ] T037 Auditar o Swift: nenhuma constante de política (reprovou nos marcos 1 e 3)
- [ ] T038 Atualizar `mobile/README.md`

---

## Dependencies

```
Setup (T001-T003)
   └─► Foundational (T004-T007)   🚦 T007: a câmera volta inteira?
          └─► US1 contagem (T008-T013)     🚦 T013
                 └─► US2 endireitar (T014-T024)   🚦 T022 · T023
                        └─► US3 transição (T025-T030)   🚦 T030
                               └─► US4 histórico (T031-T034)
                                      └─► Polish
```

**A transição vem depois do endireitamento**, e não antes, porque ela **anima a
homografia**. Animar antes de saber que a homografia está certa seria animar um
destino errado — e um destino errado animado com suavidade continua errado.

**A T017 existe só para depurar.** Desenhar o quadrilátero estimado sobre a foto
é o que transforma "o endireitamento saiu torto" em "a reta dos topos pegou o
livro errado". Sem ela, a fase 4 vira adivinhação.

## Parallel Execution Examples

- **Setup**: T001 e T002 são independentes.
- **US2**: T020 (divisões) e T021 (arrasto) não dependem uma da outra.
- **Polish**: T036 e T037 são auditorias independentes.

## Implementation Strategy

**O MVP é a US1**, e ela vale sozinha: apontar, apertar, saber quantos. Sem
endireitar e sem animação, ainda é a primeira coisa que o app faz por alguém.

**Quatro portões.** T007 protege a sessão ao vivo. T013 valida a contagem. T023
é o mais importante: **confirmar que o app recusa em vez de errar** — uma
captura que deveria ter sido recusada e não foi é o defeito mais grave que este
marco pode ter. T030 mede a experiência.

**Medir em Release.** Vale para todos os marcos deste projeto, e aqui também.
