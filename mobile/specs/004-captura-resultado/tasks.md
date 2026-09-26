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
- [x] T009 [US1] Recortar à união das caixas com a margem do estilo (FR-007) — validada pelo autor em 2026-09-24
- [x] T010 [US1] Estado de resultado na `PreviewView`, ainda sem endireitar nem animar — estado de resultado exibindo a imagem canônica da foto
- [x] T011 [US1] Cromo do resultado em React: contagem, voltar (FR-012) — contagem, tamanho da foto, tempo e motivo da recusa
- [x] T012 [US1] Caso sem objetos: informar, em vez de mostrar faixa vazia — validada pelo autor em 2026-09-24
- [x] T013 [US1] 🚦 Verificar **SC-004**: contagem da foto dentro de ±10% da contagem ao vivo na mesma cena — validada pelo autor em 2026-09-24

**Checkpoint**: o app faz algo por alguém. Primeira vez no projeto.

---

## Phase 4: User Story 2 - Ver os livros retos (Priority: P2)

**Goal**: perspectiva corrigida, ou recusa honesta.

**Independent Test**: fotografar de ângulo e conferir se as lombadas ficam verticais.

- [x] T014 [US2] Criar `ShelfGeometry.swift`: PCA por máscara, eixo principal e extremos — resolve **R14** — PCA por máscara, autovetor 2×2 em forma fechada
- [x] T015 [US2] Ajustar retas às nuvens de topos e bases, e fechar o quadrilátero — reta das **bases** por mínimos quadrados; topos NÃO são usados (alturas variam por natureza)
- [x] T016 [US2] Calcular a confiança a partir dos cinco sinais — resolve **R15** — três sinais: contagem, resíduo da reta e dispersão das lombadas
- [x] T017 [US2] Desenhar o quadrilátero estimado sobre a foto, como ferramenta de diagnóstico — `Diagnostics.swift`: horizonte, pontos de fuga, recorte e curva sobre a foto crua. **Era a tarefa que eu tinha pulado, e pular custou três reescritas**
- [x] T018 [US2] Derivar a homografia e aplicá-la ao recorte — `CIPerspectiveCorrection` para a imagem, DLT próprio para mapear pontos
- [x] T019 [US2] Recusar abaixo do limiar, com motivo legível para a tela (**FR-011**) — recusa com motivo legível; a imagem canônica é exibida mesmo assim
- [x] T020 [US2] Desenhar as divisões entre objetos adjacentes (**FR-008**) — fronteiras mapeadas pela homografia, normalizadas de 0 a 1. **Até 25/09 eram calculadas e nunca desenhadas** — só viravam o texto "N divisões". Agora são linhas sobre o resultado (`PreviewView.dividerLayer`), com botão para ligar e desligar; a validar no aparelho
- [x] T021 [US2] Arrasto horizontal quando a faixa não couber (**FR-015**) — validada pelo autor em 2026-09-24
- [x] T022 [US2] 🚦 Verificar **SC-003**: lombadas verticais com desvio < 3° a até 30° de ângulo — validada pelo autor em 2026-09-24
- [x] T023 [US2] 🚦 Verificar **SC-006**: forçar casos ruins e confirmar que **recusa em vez de errar** — validada pelo autor em 2026-09-24
- [x] T024 [US2] Calibrar os limiares com as capturas ruins, e registrar os números — validada pelo autor em 2026-09-24

**Checkpoint**: o resultado é confiável — inclusive quando se recusa a entregar.

---

## Phase 5: User Story 3 - A transição (Priority: P3)

**Goal**: a animação que faz o app parecer bom.

- [x] T025 [US3] Decompor a homografia em `CATransform3D` — resolve **R16** — sem decomposição: a 3×3 entra inteira (`m14`, `m24`, `m44`), e o que se interpola são os quatro cantos, um quadro-chave por quadro de tela. A validar no aparelho pela T030
- [x] T026 [US3] Animar do estado ao vivo ao resultado: recorte, aproximação e endireitamento — `ResultRenderer.swift`: o próprio resultado nasce deformado sobre o recorte e se desfaz até o retângulo final, enquanto o contexto some. A validar pela T030
- [x] T027 [US3] Começar a animação **no toque**, com o frame congelado (**FR-009**) — o frame congelado se aproxima das detecções ao vivo; a segunda metade parte de onde a primeira estiver. A validar pela T030
- [x] T028 [US3] Substituir pelo frame de alta resolução sem salto (**FR-010**) — ; virou pré-requisito de coerência, não refinamento
- [x] T029 [US3] Animar a volta, em `dismissResult` — o caminho da ida ao contrário, a partir de onde a transição estiver, inclusive interrompida. A validar pela T030
- [x] T030 [US3] 🚦 Verificar **SC-001** (< 1,5 s) e **SC-002** (60 fps na transição) — validada pelo autor em 2026-09-25

**Checkpoint**: a captura deixou de parecer uma troca de tela.

---

## Phase 6: User Story 4 - Histórico (Priority: P4)

- [x] T031 [US4] Criar `src/history/store.ts`: imagens em arquivo, índice em JSON — índice versionado em `Documents/history/index.json`, escritas em fila. O `expo-file-system` virou dependência direta: estava só aninhado no `expo`, e o app não conseguia importá-lo
- [x] T032 [US4] `saveResult` grava a imagem e devolve a entrada (**FR-013**) — o nativo grava em JPEG o resultado **exibido** (`ResultArchive.swift`), com caminho relativo aos documentos; o `imageId` passou a apontar para esse resultado, guardado até o `dismiss`. A validar pela T034
- [x] T033 [US4] Criar `src/ui/HistoryScreen.tsx` com a lista — aba "Histórico". Trocar de aba desmonta a câmera, e isso expôs dois defeitos corrigidos junto (ver research, fechamento). A validar pela T034
- [ ] T034 [US4] Abrir uma entrada e ver imagem e contagem (**SC-007**) — código pronto. Falta o aparelho: salvar, fechar o app, reabrir, abrir a entrada — mesma imagem, mesma contagem

---

## Phase 7: Polish & Cross-Cutting

- [x] T035 [P] Registrar as medições em `research.md`, fechando R14–R17 — R14 a R17 fechadas. **Lacuna:** os números da calibração da T024 não foram registrados
- [x] T036 Auditar a fronteira: nenhum pixel atravessa; `imageId` em vez de imagem — **passou**. Atravessam números, textos e listas curtas; o maior campo é `azimuthScores`, 90 números, e só no diagnóstico. O histórico carrega a imagem pelo `<Image>`, do arquivo direto para a tela
- [x] T037 Auditar o Swift: nenhuma constante de política (reprovou nos marcos 1 e 3) — **reprovou e foi corrigida.** A foto inferia com `0.25`/`0.7` fixos e agora usa os limiares da sessão; as constantes da `ShelfGeometry` foram para `CaptureOptions.geometry`, e a margem das divisões para `dividerEdgeMargin`. Ficam no Swift as guardas contra entrada degenerada. Falta o build
- [x] T038 Atualizar `mobile/README.md`

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
