---
description: "Task list for Releitura do recorte"
---

# Tasks: Releitura do recorte

**Input**: Design documents from `/specs/006-releitura-recorte/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/reread.md](./contracts/reread.md), [quickstart.md](./quickstart.md)

**Tests**: sem suíte automatizada, como nos marcos anteriores. Verificação no
aparelho, **em Release**, pelo [quickstart](./quickstart.md).

**Organization**: por história. As peças nascem sem mudar nada na tela (fase
2); a US1 troca a fonte do resultado; a US2 põe as divisões no mesmo espaço.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode ser feita em paralelo — arquivo diferente, sem dependência pendente
- **[Story]**: a história da spec (US1, US2)
- 🚦: portão — verificação no aparelho que decide se a fase vale

## Path Conventions

Caminhos relativos a `mobile/`.

---

## Phase 1: Setup

**Purpose**: o contrato e a política em TypeScript, antes de qualquer Swift.

- [X] T001 Em `modules/vizi-vision/src/ViziVision.types.ts`: o tipo `CountSource` (`'reread' | 'photo'`); `CaptureOptions.reread` e `CaptureOptions.rereadMembership`; `CaptureResult.countSource` e `CaptureResult.rereadMs`; `HistoryEntry.countSource` opcional ("ausente nas entradas de antes da 006, que eram da foto"); e o comentário do `readyMs`, que passa a medir até o resultado na tela, antes da releitura
- [X] T002 [P] Em `src/capture/options.ts`, `reread: true` e `rereadMembership: 0.5` em `DEFAULT_CAPTURE`, cada um comentado com o que decide (data-model)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: as peças da releitura, sem nada novo na tela.

**⚠️ CRITICAL**: as duas histórias dependem destas peças.

- [X] T003 Em `modules/vizi-vision/ios/FrameTransform.swift`, o quadrado da releitura: um `CIImage` encaixado no lado pedido — a menor das duas escalas, centrado, como o `resizeAspect` —, composto sobre preto, num buffer do pool; devolve o buffer e o retângulo do conteúdo em pixels do quadrado. **Sem** a normalização de orientação do `transform` (R30)
- [X] T004 Em `modules/vizi-vision/ios/SessionCoordinator.swift`, `squareFromCutout(_:side:)`, ao lado do `squareFromPhoto`, lançando o mesmo erro quando o quadrado não sai
- [X] T005 [P] Em `modules/vizi-vision/ios/ShelfGeometry.swift`, guardar de qual instância veio cada lombada e devolver `rows[].indices` e `lying` em **índices de instância** — em todos os retornos (R33)
- [X] T006 [P] Em `modules/vizi-vision/ios/OverlayRenderer.swift`, o `ResultStore` sabe quem publicou: `publishOverriding` marca o conteúdo como resultado da captura, `publish` e `clear` desmarcam, e `read()` devolve a marca (data-model, "O que o overlay está mostrando")
- [X] T007 [P] Criar `modules/vizi-vision/ios/Reread.swift`: o resultado da leitura (instâncias, protótipos, fileiras, deitados, divisões); a regra das bordas — "área da caixa dentro do recorte sem a margem ≥ `rereadMembership` × área da caixa", com o recorte sem a margem medido pelo `PlaneRectifier` e levado ao conteúdo do quadrado (R32, T025); e as divisões de uma fileira no quadrado, normalizadas no recorte, com o `dividerEdgeMargin` (R33)
- [X] T008 [P] Em `modules/vizi-vision/ios/ViziVisionModule.swift`, `CaptureOptions.reread` e `CaptureOptions.rereadMembership`, com **defaults inválidos de propósito**: `false` e 2, que não deixa nenhuma caixa passar

**Checkpoint**: tudo compila e a captura se comporta exatamente como na 005.

---

## Phase 3: User Story 1 - O resultado é a leitura da imagem na tela (Priority: P1) 🎯 MVP

**Goal**: depois de a imagem ir para a tela, o modelo lê o quadrado, e o que ele encontra é a contagem, as caixas e as máscaras do resultado.

**Independent Test**: capturar uma prateleira e contar as caixas na tela: são o número mostrado, a ±10% da contagem manual.

- [X] T009 [US1] Em `OverlayRenderer.tick`, em `modules/vizi-vision/ios/OverlayRenderer.swift`: o conteúdo publicado pela captura é desenhado como está — sem o filtro da faixa e sem o `minConfidence` (FR-005, R31); e o `style` ganha um `didSet` que força o próximo desenho (FR-006)
- [X] T010 [US1] Em `capture`, em `modules/vizi-vision/ios/ViziVisionModule.swift`: guardar o recorte renderizado — também no diagnóstico —; medir o `readyMs` logo depois do `settle`; então montar o quadrado com `squareFromCutout`, inferir com os limiares da sessão (FR-003) e aplicar a regra das bordas; publicar as instâncias e os protótipos num bloco da thread de interface guardado pela época do resultado (T026) — lista vazia no diagnóstico (FR-010) —; e, se o quadrado não sair ou o modelo lançar erro, ficar com a leitura da foto (FR-012, R29, R34)
- [X] T011 [US1] Em `modules/vizi-vision/ios/ViziVisionModule.swift`, `dismissResult` e `endResultState` esvaziam o `ResultStore` antes de soltar a pausa (FR-011, R31)
- [X] T012 [US1] No retorno do `capture`, em `modules/vizi-vision/ios/ViziVisionModule.swift`: `count` e `instances` da leitura que valeu, `countSource`, `rereadMs` e o `readyMs` medido na T010; geometria e `outsideBandCount` continuam da foto (contrato)
- [X] T013 [P] [US1] Em `src/ui/CameraScreen.tsx`: a linha "leitura" (recorte na tela · foto) e a linha "releitura" com `rereadMs`; "Nenhum livro na faixa" só com `countSource: 'photo'`; e "A releitura não encontrou livros no recorte" quando ela der zero (R34)
- [X] T014 [P] [US1] Em `src/history/store.ts`, `countSource` na entrada salva (FR-009)
- [ ] T015 [US1] 🚦 **SC-001, SC-002 e SC-004** conforme `specs/006-releitura-recorte/quickstart.md`, itens 1 a 4: caixas sobre os livros, caixas = contagem, dez capturas a ±10% da manual, `toque → pronto` abaixo de 1,5 s e `rereadMs` abaixo de 600 ms
- [ ] T016 [US1] 🚦 **SC-003** conforme `specs/006-releitura-recorte/quickstart.md`, item 5: dez capturas da faixa vertical sobre uma coluna, nenhuma fatia contada — ajustar `rereadMembership` até passar
- [ ] T017 [US1] 🚦 **SC-007**, FR-008 e FR-010 conforme `specs/006-releitura-recorte/quickstart.md`, itens 7 a 10: a volta limpa, a parede vazia cai na foto, o diagnóstico conta igual e o histórico guarda a origem

**Checkpoint**: o resultado é a leitura da imagem na tela. Sozinho, é o pedido.

---

## Phase 4: User Story 2 - As divisões da releitura (Priority: P2)

**Goal**: fileiras e divisões saem das caixas da releitura, no espaço do recorte.

**Independent Test**: caixas e divisões ligadas; cada divisão entre duas caixas vizinhas da mesma fileira.

- [X] T018 [US2] Na releitura, em `modules/vizi-vision/ios/ViziVisionModule.swift`: `ShelfGeometry.estimate` sobre as caixas que passaram pela regra das bordas, com os protótipos da releitura, **sem gravidade**, com mínimo de um livro — o `minInstancesForGeometry` é do quadrilátero —, e as opções de geometria da captura; `shelves` pelas divisões da T007; `shelfCount` e `lyingCount` da releitura (R33)
- [X] T019 [US2] Em `capture`, em `modules/vizi-vision/ios/ViziVisionModule.swift`, as divisões saem do bloco do `settle` e são desenhadas depois da releitura, no bloco guardado pelo `imageId`: as da releitura quando ela valeu e o recorte está na tela — endireitado ou só girado (FR-007) —; senão, as da foto, só quando endireitada e fora do diagnóstico, como na 005
- [ ] T020 [US2] 🚦 **SC-005** conforme `specs/006-releitura-recorte/quickstart.md`, item 6: toda divisão entre duas caixas vizinhas da mesma fileira; fileiras próprias na faixa vertical; divisões também no recuo de só rotação

**Checkpoint**: tudo o que está sobre o resultado vem da mesma leitura.

---

## Phase 5: Polish & Cross-Cutting Concerns

- [X] T021 [P] Auditar a fronteira e o Swift em `modules/vizi-vision/ios/`: nada da releitura atravessa além de números e texto (princípio II); nenhum valor de ajuste da releitura fixo no nativo — ficam a definição do quadrado (encaixe, centro, preto), a conta da margem sobre o `cropMargin` e as guardas contra entrada degenerada (princípio IV) — **passou.** Atravessam `count`, `countSource`, `rereadMs` e as fileiras em números; o quadrado e os protótipos da releitura não saem do nativo. No Swift novo ficam só a definição do quadrado (encaixe da menor escala, centro, preto do fundo da `PreviewView`), a conta da margem `m/(1+2m)` sobre o `cropMargin`, o ponto médio das divisões, a focal que não entra na conta sem gravidade e as guardas contra caixa sem área e retângulo vazio. Os defaults de `reread` e `rereadMembership` são inválidos de propósito
- [X] T022 [P] Atualizar `mobile/README.md` e o `README.md` da raiz
- [ ] T023 🚦 **SC-006** conforme `specs/006-releitura-recorte/quickstart.md`, item 11: com a faixa desligada, a contagem do resultado a ±10% da mediana ao vivo
- [ ] T024 Registrar as medições e o valor final de `rereadMembership` em `specs/006-releitura-recorte/research.md`, fechando R29 a R33
- [X] T025 *Achado na revisão:* no recuo de só rotação, a borda da foto corta a margem do recorte, e deduzir o recorte sem a margem do `cropMargin` apertava os lados — os livros das pontas deixariam de contar. `PlaneRectifier.Output.books` passa a medir onde os livros ficam no resultado, nos dois caminhos, em `modules/vizi-vision/ios/PlaneRectifier.swift`, e a releitura usa essa medida (R32)
- [X] T026 *Achado na revisão:* a guarda pelo `imageId` deixava passar uma foto que chega depois do fim da sessão. Uma época do resultado, avançada pelo `dropResult` e conferida pelo `keepResult` e pelo bloco da releitura, em `modules/vizi-vision/ios/ViziVisionModule.swift`; o `endResultState` invalida antes de limpar (R29)

---

## Dependencies

```
Setup (T001-T002)
   └─► Foundational (T003-T008)   as peças, nada novo na tela
          └─► US1 o resultado é a releitura (T009-T017)   🚦 T015 · T016 · T017
                 └─► US2 as divisões (T018-T020)            🚦 T020
                        └─► Polish (T021-T026)                🚦 T023
```

**A US1 vem inteira antes das divisões.** Contagem, caixas e máscaras da
releitura já são o pedido. Até a US2, as divisões da foto continuam sendo
desenhadas como na 005 — só quando endireitada —, e podem ficar desencontradas
das caixas: é o que a US2 resolve.

**A T005 é pré-requisito da US2**, mas vai na fase 2 porque também corrige as
divisões da foto, que continuam existindo quando a releitura não vale.

## Parallel Execution Examples

- **Setup**: depois da T001, a T002.
- **Foundational**: a T005 (`ShelfGeometry`), a T006 (`OverlayRenderer`), a T007 (`Reread`, novo) e a T008 (`ViziVisionModule`) não se tocam; a T004 espera a T003.
- **US1**: a T013 e a T014 (TypeScript) andam junto com as T009 a T012 (Swift).

## Implementation Strategy

**O MVP é a US1**, e vale sozinha: a contagem e as caixas passam a ser as da
imagem na tela.

**Cinco portões.**

- **T015 é o mais importante.** É o pedido medido: caixa na tela é caixa
  contada, e a contagem acerta.
- **T016** protege a contagem das bordas, onde a margem mostra o que não é da
  faixa.
- **T017** protege o ao vivo: nada do resultado pode sobrar na volta.
- **T020** fecha a coerência da tela: divisões e caixas da mesma leitura.
- **T023** mantém a promessa da 004 — a captura concorda com o ao vivo.

**Um build nativo** cobre a fase 2, a US1 e a US2: mexem em poucos arquivos, e a
US2 só estende a função da US1.

**Medir em Release.**
