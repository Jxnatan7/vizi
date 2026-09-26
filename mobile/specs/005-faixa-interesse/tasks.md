---
description: "Task list for Faixa de interesse"
---

# Tasks: Faixa de interesse

**Input**: Design documents from `/specs/005-faixa-interesse/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/band.md](./contracts/band.md), [quickstart.md](./quickstart.md)

**Tests**: sem suíte automatizada, como nos marcos anteriores. Verificação no
aparelho, **em Release**, pelo [quickstart](./quickstart.md).

**Organization**: por história. A faixa nasce como estado, sem nada na tela
(fase 2); fica visível e útil na US1; ganha modos, dedos e orientação nas
seguintes.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode ser feita em paralelo — arquivo diferente, sem dependência pendente
- **[Story]**: a história da spec (US1 a US4)
- 🚦: portão — verificação no aparelho que decide se a fase vale

## Path Conventions

Caminhos relativos a `mobile/`.

---

## Phase 1: Setup

**Purpose**: o contrato e a política em TypeScript, antes de qualquer Swift.

- [X] T001 Acrescentar a `modules/vizi-vision/src/ViziVision.types.ts` os tipos `BandMode` (`'off' | 'horizontal' | 'vertical'`), `BandState` (`mode`, `center`, `thickness`) e `BandPolicy` (os doze campos do data-model), e os campos novos: `SessionOptions.band`, a aparência da faixa em `OverlayStyle` (`bandDimOpacity`, `bandEdgeColor`, `bandEdgeWidth`, `bandHandleLength`, `bandHandleThickness`, `bandCountFontSize`) e `CaptureResult.outsideBandCount`
- [X] T002 [P] Declarar `setBandMode(mode: BandMode): Promise<void>` e o evento `onBandChange(state: BandState)` em `modules/vizi-vision/src/ViziVisionModule.ts`
- [X] T003 [P] Criar `src/band/policy.ts` com `DEFAULT_BAND: BandPolicy` — os doze valores iniciais do data-model, cada um comentado com o que decide — e enviá-lo como `band` em `DEFAULT_SESSION`, em `src/camera/useSession.ts`
- [X] T004 [P] Acrescentar a aparência da faixa a `DEFAULT_OVERLAY` em `src/overlay/style.ts`, com os valores do data-model

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: a faixa existe como estado no nativo, reiniciada a cada sessão e espelhada no JavaScript.

**⚠️ CRITICAL**: toda história lê e escreve este estado. Nada aparece na tela ainda.

- [X] T005 Criar `modules/vizi-vision/ios/Band.swift` com `BandMode`, `Band` (modo; centro e espessura normalizados; `lower` e `upper`; o retângulo dentro do retângulo da imagem, nas duas orientações; desligada é a moldura inteira), `BandPolicy` (os doze campos) e a regra de pertença como função pura: "sobreposição entre a caixa e a faixa, no eixo limitado, ≥ `membership` × extensão da caixa nesse eixo"; desligada, tudo pertence
- [X] T006 Acrescentar `BandModel` a `modules/vizi-vision/ios/Band.swift`: estado com trava; geração incrementada a cada escrita; `write` silencioso, para o gesto; `commit`, que notifica só se o estado mudou desde o último; última faixa ligada; `reset(policy)` para horizontal, centro e `defaultThickness`; e `setMode` com as transições do contrato — desligada → orientação volta à última ligada, virando se preciso; orientação → a outra mantém centro e espessura; → `off` guarda a última
- [X] T007 Em `modules/vizi-vision/ios/ViziVisionModule.swift`: `BandPolicyRecord` com os doze campos e **defaults inválidos de propósito** (zerados, a faixa nasce sem espessura), como campo `band` de `SessionOptions`, e a conversão para `BandPolicy`; os seis campos de aparência em `OverlayStyleRecord`, mapeados para o `OverlayStyle` de `modules/vizi-vision/ios/OverlayRenderer.swift`; `Events("onTelemetry", "onBandChange")`
- [X] T008 Em `modules/vizi-vision/ios/SessionCoordinator.swift`, `let band = BandModel()`, reiniciado em `start` com a política da sessão; em `startSession`, em `modules/vizi-vision/ios/ViziVisionModule.swift`, ligar `band.onChange` ao evento `onBandChange` e fazer `commit` do estado inicial, para o JavaScript espelhar desde o primeiro frame
- [X] T009 Em `modules/vizi-vision/ios/PreviewView.swift`, `PreviewSink.band` — guardado como o `store` — e repassado à view e ao overlay em `configure()`

**Checkpoint**: a sessão nasce com a faixa no centro, como estado. A tela não mudou.

---

## Phase 3: User Story 1 - Contar só a prateleira que interessa (Priority: P1) 🎯 MVP

**Goal**: a faixa padrão aparece, anda com um dedo e limita a contagem — ao vivo e na captura.

**Independent Test**: estante de três prateleiras, faixa sobre a do meio: a contagem e o recorte são só dela.

- [X] T010 [P] [US1] Criar `modules/vizi-vision/ios/BandRenderer.swift`: escurecimento (um `CAShapeLayer` com preenchimento par-ímpar, a moldura menos a faixa); bordas (duas linhas) e alças (dois segmentos curtos com ponta redonda, que desenham as cápsulas); pílula da contagem presa à ponta de uma borda; as duas orientações; toda a aparência vinda do `OverlayStyle`; `apply(band, animated:)` com `CASpringAnimation` no caminho, partindo da camada de apresentação, com a mola convertida de `springResponse` e `springDamping`; `setVisible(_:animated:)`; e `BandFeedback` — seleção e impacto leve, respeitando `haptics` (R20, R24)
- [X] T011 [US1] Em `modules/vizi-vision/ios/PreviewView.swift`, hospedar o `BandRenderer` na ordem vídeo → escurecimento → máscaras e caixas → divisões → bordas, alças e contagem → transição; `reclaimOverlay` passa a devolver o overlay **acima do escurecimento**, não do vídeo; `imageRect`, o quadrado da imagem canônica dentro da view; `setBandVisible(_:)`
- [X] T012 [US1] Em `modules/vizi-vision/ios/OverlayRenderer.swift`, filtrar no desenho: membros da faixa pela regra de pertença, desenhados se `score ≥ minConfidence`; redesenhar quando muda o resultado **ou** a geração da faixa; repassar ao `BandRenderer` a contagem de membros a cada desenho (R21)
- [X] T013 [US1] Em `modules/vizi-vision/ios/BandRenderer.swift`, a contagem pela mediana numa janela de `countWindowMs`, com o texto trocado só quando a mediana muda (FR-015, R23)
- [X] T014 [P] [US1] Em `SessionCoordinator.process`, em `modules/vizi-vision/ios/SessionCoordinator.swift`, a contagem da telemetria passa a ser a dos membros da faixa, com a faixa lida sob trava
- [X] T015 [US1] Criar `modules/vizi-vision/ios/BandGesture.swift`: reconhecedor próprio (`UIGestureRecognizerSubclass`) que só começa depois de `startSlopPoints` de movimento; com um dedo em qualquer ponto da imagem, move a faixa no eixo livre, presa dentro da imagem, escrevendo no `BandModel` sem notificar e aplicando no `BandRenderer` sem animação; `commit` ao soltar (FR-007, R18)
- [X] T016 [US1] Registrar o reconhecedor em `modules/vizi-vision/ios/PreviewView.swift`, desligado enquanto a sessão não roda e durante captura e resultado
- [X] T017 [P] [US1] Em `src/ui/CameraScreen.tsx`, o preview fixo no topo, fora da `ScrollView`, com os cartões rolando abaixo (FR-018, R19)
- [X] T018 [US1] Em `capture`, em `modules/vizi-vision/ios/ViziVisionModule.swift`: ler a faixa no toque; esconder a faixa e desligar o reconhecedor; foco da aproximação só com os membros; filtrar as detecções da foto **antes** da geometria e usar o conjunto filtrado em todo o resto — geometria, região, divisões, contagem e overlay; `outsideBandCount` no resultado; em caso de erro, a faixa volta (FR-006, FR-020)
- [X] T019 [US1] Em `modules/vizi-vision/ios/ResultRenderer.swift`, avisar a `PreviewView` no fim do `dismiss`; ela mostra a faixa como estava e religa o reconhecedor (R27) — também quando o `dismiss` não tem transição a desfazer (captura sem frame congelado), senão a faixa ficaria escondida para sempre
- [X] T020 [US1] Em `src/ui/CameraScreen.tsx`, a linha "fora da faixa" no resultado, e "Nenhum livro na faixa" quando `count` é zero e `outsideBandCount` não é (cenário 5 da US1)
- [ ] T021 [US1] 🚦 **SC-001 e SC-002** no aparelho, conforme `specs/005-faixa-interesse/quickstart.md`, itens 1, 3 e 7: a faixa abre no centro; a caixa troca na hora certa; contagem manual da prateleira do meio × captura, dentro de ±10%; dez recortes, só a do meio
- [ ] T022 [US1] 🚦 **SC-003** conforme `specs/005-faixa-interesse/quickstart.md`, itens 2 e 8: a borda cola no dedo, a tela não rola, e trinta segundos de arrasto contínuo sem nenhuma janela abaixo de 59 fps; registrar `drawMs` com e sem movimento

**Checkpoint**: a faixa conta uma prateleira. Sozinho, é o pedido original — a linha do meio.

---

## Phase 4: User Story 2 - Voltar à imagem toda (Priority: P2)

**Goal**: desligar e religar a faixa pela cápsula.

**Independent Test**: desligar a faixa e conferir que caixas, contagem e captura voltam a considerar a imagem toda.

- [ ] T023 [US2] Em `modules/vizi-vision/ios/BandRenderer.swift`: desligar é a faixa se abrindo até a moldura, com bordas, alças e contagem sumindo; ligar é a moldura se fechando até a faixa (FR-017, R20)
- [ ] T024 [US2] `AsyncFunction("setBandMode")` em `modules/vizi-vision/ios/ViziVisionModule.swift`: transição por `BandModel.setMode`, animada pelo `BandRenderer` na thread de interface, com retorno tátil, e `onBandChange` ao terminar — tabela do `setBandMode` em `contracts/band.md`
- [ ] T025 [P] [US2] Criar `src/band/useBand.ts`: espelha `onBandChange` num estado de React, escrito só em mudança discreta, e expõe `setMode`
- [ ] T026 [P] [US2] Criar `src/ui/BandControl.tsx`: cápsula com três botões — imagem toda · horizontal · vertical —, destaque que desliza com `Animated` e driver nativo, e rótulo e estado para o leitor de tela (FR-011, FR-021)
- [ ] T027 [US2] Em `src/ui/CameraScreen.tsx`, a cápsula logo abaixo do preview, fora da `ScrollView`, escondida durante captura e resultado
- [ ] T028 [US2] 🚦 **SC-006** conforme `specs/005-faixa-interesse/quickstart.md`, item 9: com a faixa desligada, a contagem da foto fica dentro de ±10% da mediana ao vivo, na mesma cena

**Checkpoint**: dá para voltar à imagem toda e religar onde estava.

---

## Phase 5: User Story 3 - Enquadrar a prateleira com os dedos (Priority: P3)

**Goal**: espessura pelas bordas — um dedo numa, ou dois dedos nas duas.

**Independent Test**: ajustar a faixa a uma prateleira baixa e a uma alta; cada uma coberta, sem invadir a vizinha.

- [ ] T029 [US3] Em `modules/vizi-vision/ios/BandGesture.swift`, agarrar uma borda — área de `edgeGrabPoints` para cada lado da linha — move só aquela borda, respeitando `minThickness` (FR-008)
- [ ] T030 [US3] Em `modules/vizi-vision/ios/BandGesture.swift`, dois dedos: pinça em torno do ponto médio — espessura escala com a distância, centro acompanha o ponto médio —, sem salto no toque; passagens de um para dois dedos e de dois para um refazem a referência, também sem salto (FR-009, R22)
- [ ] T031 [US3] Em `modules/vizi-vision/ios/BandGesture.swift`, elástico além dos limites (`rubberBand`), mola de volta ao soltar, e impacto leve na primeira vez que encosta num limite ou na espessura mínima (FR-014, FR-016)
- [ ] T032 [US3] Em `modules/vizi-vision/ios/PreviewView.swift`, dois toques dentro da faixa a devolvem ao centro e à `defaultThickness`, na mesma orientação, com mola e retorno tátil (FR-013)
- [ ] T033 [US3] Em `modules/vizi-vision/ios/BandGesture.swift`, dois dedos com a faixa desligada a criam entre eles, orientada pelo eixo; as duas bordas além da imagem por mais de `offMargin` a desligam, e voltar os dedos no mesmo gesto a faz renascer (FR-012 — os cenários 2 e 3 da US2)
- [ ] T034 [US3] 🚦 Conforme `specs/005-faixa-interesse/quickstart.md`, itens 4 e 5: o segundo dedo pousa sem salto, espessura e posição andam juntas, abrir desliga, pinçar cria

**Checkpoint**: a faixa se ajusta a qualquer prateleira.

---

## Phase 6: User Story 4 - Virar a faixa (Priority: P4)

**Goal**: a faixa vertical, pelo eixo dos dedos.

**Independent Test**: virar a faixa sobre uma coluna e capturar só aquela coluna.

- [ ] T035 [US4] Em `modules/vizi-vision/ios/BandGesture.swift`, a orientação pelo ângulo entre os dedos: acima de 45° + `flipHysteresisDegrees`, horizontal; abaixo de 45° menos a folga, vertical; entre os dois, mantém. Ao virar, a faixa se refaz entre os dedos no novo eixo, numa mola com retorno tátil, e a pinça recomeça dali (FR-010, R22)
- [ ] T036 [US4] 🚦 **SC-004** conforme `specs/005-faixa-interesse/quickstart.md`, item 4: dez viradas pelos dedos, dez na primeira tentativa, sem tremular — ajustar `flipHysteresisDegrees` até passar
- [ ] T037 [US4] 🚦 Faixa vertical sobre uma coluna, conforme `specs/005-faixa-interesse/quickstart.md`, item 7: a captura conta, endireita e recorta só a coluna (cenário 4 da US4)

**Checkpoint**: as duas orientações, pelo gesto e pela cápsula.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T038 [P] Em `modules/vizi-vision/ios/BandRenderer.swift`, a faixa como elemento de acessibilidade ajustável — deslizar move um passo de `minThickness` — com as ações virar, engrossar, afinar, voltar ao centro e desligar (FR-021, R25)
- [ ] T039 [P] Em `modules/vizi-vision/ios/Diagnostics.swift`, e na chamada em `capture`, desenhar a faixa e os livros descartados sobre a foto crua (FR-022)
- [ ] T040 🚦 **SC-005**: o teste de uso com três pessoas, conforme `specs/005-faixa-interesse/quickstart.md`; anotar onde cada uma hesitou
- [ ] T041 Registrar as medições e os valores ajustados em `specs/005-faixa-interesse/research.md`, fechando R18 a R27 — R28 segue adiada
- [ ] T042 Auditar a fronteira em `modules/vizi-vision/ios/ViziVisionModule.swift` e `src/band/useBand.ts`: `onBandChange` só em mudança discreta, nada atravessa durante o arrasto (princípio III)
- [ ] T043 Auditar o Swift em `modules/vizi-vision/ios/`: nenhum valor da faixa fixo no nativo, e as guardas classificadas como na T037 da 004
- [ ] T044 Atualizar `mobile/README.md`

---

## Dependencies

```
Setup (T001-T004)
   └─► Foundational (T005-T009)   a faixa como estado, nada na tela
          └─► US1 contar a prateleira (T010-T022)   🚦 T021 · T022
                 ├─► US2 imagem toda (T023-T028)    🚦 T028
                 └─► US3 os dedos (T029-T034)       🚦 T034
                        └─► US4 virar (T035-T037)   🚦 T036 · T037
                               └─► Polish (T038-T044)   🚦 T040
```

**A US1 vem inteira antes de qualquer gesto de dois dedos.** Um dedo e a faixa
padrão já entregam o pedido original, e já exercitam o que decide a
arquitetura: seguir o dedo a 60 fps sem React. Se a T022 falhar, o problema é
de fundação, e é melhor saber antes de somar pinça e orientação por cima.

**US2 antes de US3**, porque a faixa começa ligada: desligar tem de existir
desde cedo. A exceção é a T033 — criar pinçando e desligar abrindo são gestos
de dois dedos, dependem da T030 e da animação da T023, e por isso moram na US3.

**US4 depende da pinça da US3**: virar é uma decisão tomada no meio do gesto de
dois dedos.

## Parallel Execution Examples

- **Setup**: depois da T001, a T002, a T003 e a T004 não se tocam.
- **US1**: a T010 (desenho, Swift), a T014 (telemetria, Swift) e a T017 (tela, TypeScript) são arquivos diferentes.
- **US2**: a T025 e a T026 (TypeScript) andam junto com a T023 e a T024 (Swift).
- **Polish**: a T038 e a T039 são independentes.

## Implementation Strategy

**O MVP é a US1**, e ela vale sozinha: uma faixa no terço do meio, que anda
com um dedo e conta só o que está dentro. É a grade 3×3 original, com a linha
do meio selecionada — só que arrastável.

**Sete portões.**

- **T022 é o mais importante.** É o princípio III medido. Tudo o que é premium
  nesta spec depende de a faixa seguir o dedo sem custar quadro.
- **T021 e T037** confirmam o valor: a contagem certa, só da prateleira — ou
  da coluna — escolhida.
- **T028** protege a 004: desligada, a faixa não pode ter mudado nada.
- **T034 e T036** calibram a sensação dos dedos, e são onde os números
  adiados da spec ganham valor.
- **T040** é o único portão com pessoas. Se duas de três não enquadrarem uma
  prateleira em 20 s, o problema é de descoberta, não de código.

**Um build nativo por fase**, pelo menos. A fase 2 e a US1 inteira cabem num só
se a T015 sair certa de primeira; a US3 e a US4 mexem no mesmo arquivo e
merecem o aparelho entre uma e outra.

**Medir em Release.** Vale para todos os marcos deste projeto, e aqui também.
