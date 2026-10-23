---
description: "Task list for Coleta para treino e prova"
---

# Tasks: Coleta para treino e prova

**Input**: Design documents from `/specs/008-coleta-treino/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/collection.md](./contracts/collection.md), [contracts/zip-format.md](./contracts/zip-format.md), [contracts/ferramentas.md](./contracts/ferramentas.md), [quickstart.md](./quickstart.md)

**Tests**: sem suíte automatizada, como nos marcos anteriores. Verificação no
aparelho, **em Release**, pelo [quickstart](./quickstart.md); a ferramenta se
confere sozinha (SC-003) e roda nas sessões de 20/10 antes de haver sessão
nova.

**Organization**: por história. A fronteira, o armazenamento das prateleiras e
o modo rápido nascem na fase 2; a US1 é o treino até o pacote; a US2, a prova
e o relatório; a US3, o cadastro e o guia na Medição.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode ser feita em paralelo — arquivo diferente, sem dependência pendente
- **[Story]**: a história da spec (US1, US2, US3)
- 🚦: portão — verificação no aparelho, na ferramenta ou no Roboflow que decide se a fase vale

## Path Conventions

Caminhos relativos a `mobile/`.

---

## Phase 1: Setup

**Purpose**: o contrato em TypeScript, a política e o formato no bundle.

- [X] T001 Em `modules/vizi-vision/src/ViziVision.types.ts`, os tipos de [contracts/collection.md](./contracts/collection.md): `ShelfSnapshot`, `CollectionTags`, `CollectionSessionInfo`; `session` em `CollectionOptions`; `purpose` e `light` em `CollectionState` (opcionais) e em `CollectionSummary` (`null` nas sessões anteriores à 008)
- [X] T002 [P] Em `modules/vizi-vision/src/ViziVisionModule.ts`, `capture(options, tags: CollectionTags | null)` e `markFrame(tags: CollectionTags | null)`, comentados: a escolha do toque, gravada sem interpretar
- [X] T003 [P] Em `src/collection/policy.ts`, `DISTANCES` e `ANGLES` — chave do formato (`near`/`mid`/`far`, `left`/`front`/`right`), rótulo e descrição da [spec](./spec.md#assumptions) —, `LIGHTS`, `BACKGROUND_GOAL = 30` e `FAST_CAPTURE = { approachMs: 0, transitionMs: 0 }`, cada um comentado com o que decide (R48, R53)
- [X] T004 [P] Em `plugins/withViziAssets.js`, o `FORMAT.md` passa a vir de `specs/008-coleta-treino/contracts/zip-format.md` (R57)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: o nativo grava o que a sessão é e a escolha do toque; o app guarda prateleiras e guia; a captura sabe ser rápida.

**⚠️ CRITICAL**: as três histórias dependem destas peças.

- [X] T005 Em `modules/vizi-vision/ios/ViziVisionModule.swift` e `modules/vizi-vision/ios/CollectionRecorder.swift`: `CollectionOptionsRecord.session`, um dicionário gravado sem interpretar; `startCollection` o junta ao `meta`, e o `session.json` ganha `purpose`, `light` e `shelves` no topo; o estado da sessão aberta e cada sessão de `listCollections` trazem `purpose` e `light` (`NSNull` quando ausentes)
- [X] T006 Em `modules/vizi-vision/ios/ViziVisionModule.swift` e `modules/vizi-vision/ios/CollectionTrace.swift`: `capture` recebe `tags: [String: Any]?` como segundo argumento e `markFrame` como único; guardados no toque, junto com a faixa; `CollectionTrace.Mark` e `CollectionTrace.Capture` ganham `tags`, e o `item.json` os grava na chave `tags` quando vierem (R47)
- [X] T007 [P] Em `modules/vizi-vision/ios/CollectionWriter.swift`, o recorte sai composto sobre preto: pré-multiplicar pelo alfa e tornar opaco antes do JPEG, só para o `crop.jpg` — a cunha fora da foto fica preta, como a releitura a vê (R50, FR-026)
- [X] T008 [P] Criar `src/collection/shelves.ts` ([data-model](./data-model.md#o-arquivo-shelvesjson)): `Documents/shelves.json` lido pelo `expo-file-system`; sem arquivo = vazio; versão desconhecida não é sobrescrita; escrita em fila; `addShelf`, `renameShelf` (nome sem repetir), `setShelfCount`, `removeShelf` (leva o contador), `recordTrainingCapture` (célula ou fundo, por luz); e o hook `useShelves()` com a lista, o guia e as ações
- [X] T009 Em `src/collection/useCollection.ts`: `start(session)` enviando `CollectionSessionInfo` junto com a política; `mark(tags)`; e o estado com `purpose` e `light`
- [X] T010 Em `src/capture/useCapture.ts`: `capture({ tags, fast })`. Com `fast`, `DEFAULT_CAPTURE` com `FAST_CAPTURE` e sem diagnóstico, e `dismissResult` assim que o resultado chega, sem passar por `'result'`; devolve o resultado para quem chamou (R48)

**Checkpoint**: tudo compila, e com a coleta fechada ou numa sessão sem tipo o app se comporta como na 007.

---

## Phase 3: User Story 1 - Uma sessão de treino vira um pacote para o Roboflow (Priority: P1) 🎯 MVP

**Goal**: ligar como treino, escolher prateleira e célula, capturar em sequência sem resultado nem pergunta, e transformar o zip numa pasta que o Roboflow importa com os contornos.

**Independent Test**: uma sessão de treino de 20 capturas, duas sem livros, exportada e empacotada; o pacote traz o que o contrato manda, e importado no Roboflow os contornos caem sobre os livros.

- [X] T011 [P] [US1] Criar `src/ui/CollectionStart.tsx`: a escolha ao ligar — "Treino · dia", "Treino · noite", "Prova" e "Cancelar" —, um toque cada
- [X] T012 [P] [US1] Criar `src/ui/CollectionTagsBar.tsx`: as prateleiras e, no treino, "sem livros", com a escolhida em destaque; no treino com prateleira, o guia 3×3 da luz da sessão — linhas por distância, colunas por ângulo, o número de capturas em cada célula, a escolhida destacada — e a descrição da distância e do ângulo escolhidos embaixo (FR-007, FR-011); sem prateleira cadastrada, a frase que aponta para a Medição
- [X] T013 [P] [US1] Em `src/ui/CollectionIndicator.tsx`, o tipo da sessão ("treino · noite", "prova") e a nota da última captura — gravada, com item, prateleira e célula; ou o motivo de não ter sido —, com a cor de cada caso (FR-006)
- [X] T014 [US1] Em `src/ui/CameraScreen.tsx`: ligar passa pelo `CollectionStart`; a escolha na tela, persistindo entre capturas e esquecida ao fechar a sessão ([data-model](./data-model.md#a-escolha-na-câmera)); "Capturar" desligado sem a escolha que o tipo pede, com o que falta escrito (FR-003); no treino, `capture({ tags, fast: true })`, a nota no indicador e `recordTrainingCapture` quando volta com `collectionItemId`; "Marcar" mandando as `tags`; e o fluxo da 007 nas sessões sem tipo
- [X] T015 [P] [US1] Criar `tools/coleta.py` ([contracts/ferramentas.md](./contracts/ferramentas.md)): cabeçalho PEP 723 (`numpy`, `Pillow`, `opencv-python-headless`); entradas zip ou pasta, achando a pasta da sessão dentro; e o comando `pacote` — recusas (prova sempre; sem tipo sem `--sem-tipo`), a escolha do que vai (recorte sempre; foto na diagonal da luz, sem recorte, ou sem livros; uma em três pela ordem nas sem tipo — R53), a imagem do recorte no quadrado de `--lado` com a cunha refeita pela geometria (R50), a foto copiada byte a byte (R51), os contornos (máscara ampliada antes do limiar, `--confianca`, `--duplicata`, 20 px, polígono a 1% do perímetro — R52), os nomes, o `_annotations.coco.json`, a conferência de equivalência em cada imagem (SC-003) e o resumo por prateleira (FR-021)
- [X] T016 [US1] 🚦 A ferramenta nas sessões de 20/10: a de capturas e a de marcas recusadas sem `--sem-tipo`; com ele, a de capturas vira 12 recortes e 4 fotos, nenhuma recusada na conferência; os contornos desenhados sobre algumas imagens caem sobre os livros — **passou em 22/10.** Sem `--sem-tipo`, as duas recusadas, sem pasta. Com ele: 12 recortes e 4 fotos (c0001, c0004, c0007, c0010), nenhuma recusada na conferência, 362 contornos e 71 duplicatas descartadas, em 9 s; o zip e a pasta extraída dão o mesmo pacote. A de marcas sai com 1, sem pasta. Numa cópia da sessão marcada como treino de noite, com nove células e três sem livros: as fotos inteiras foram perto-direita, média-frente e longe-esquerda, e as três sem livros foram sem contorno. Nas prévias, a cunha do c0003 sai preta e os Spy x Family ficam com 16 contornos
- [ ] T017 [US1] 🚦 **SC-001** conforme o [quickstart](./quickstart.md), passos 2 e 3: 20 capturas de treino seguidas, a câmera de volta abaixo de 1,5 s em todas e a 60 fps depois de cada uma
- [ ] T018 [US1] 🚦 **SC-002** conforme o [quickstart](./quickstart.md), "No Roboflow": o pacote do treino importado sem recusa, contornos sobre os livros em 10 imagens sorteadas, e como chegaram as fotos sem livros

**Checkpoint**: uma tarde de fotos vira uma pasta para o Roboflow. Sozinho, é o pedido.

---

## Phase 4: User Story 2 - A prova, com o inventário como gabarito (Priority: P2)

**Goal**: ligar como prova, capturar cada prateleira com o inventário como resposta preenchida, e um relatório por prateleira que a ferramenta do pacote recusa empacotar.

**Independent Test**: uma prova de todas as prateleiras cadastradas, duas capturas cada; perguntas preenchidas com o inventário; relatório completo; o pacote recusa.

- [X] T019 [P] [US2] Em `src/ui/TruthPrompt.tsx`, o número do app separado do preenchido: com os dois diferentes, "Inventário: 22 · o app contou 24"; sem, o texto da 007
- [X] T020 [US2] Em `src/ui/CameraScreen.tsx`, a prova: "Capturar" só com prateleira; a captura com as `tags`, sem o modo rápido; o `TruthPrompt` preenchido com `tags.shelf.count` e mostrando `result.count` (FR-009)
- [X] T021 [P] [US2] Em `tools/coleta.py`, o comando `prova` (R55): recusa o que não for prova; por captura, prateleira, app, gabarito e inventário, e se bateu; exatas no total e por prateleira; as prateleiras de `session.shelves` sem captura
- [ ] T022 [US2] 🚦 **SC-004 e SC-005** conforme o [quickstart](./quickstart.md), passo 5 e "No Linux": a prova no aparelho, o relatório com todas as capturas e nenhuma prateleira faltando, e o pacote recusando o zip

**Checkpoint**: a régua do gate existe.

---

## Phase 5: User Story 3 - As prateleiras e o guia de variações (Priority: P3)

**Goal**: cadastrar as prateleiras na Medição e ver, por prateleira, o que falta das 18 variações e das fotos sem livros.

**Independent Test**: três prateleiras, uma sessão de treino de dia com cinco células, apagar a sessão: o guia continua com as cinco.

- [X] T023 [P] [US3] Criar `src/ui/ShelfList.tsx`: cadastrar com nome e número; renomear; mudar o número com − e +; apagar com confirmação; por prateleira, "dia 7/9 · noite 3/9"; as fotos sem livros contra `BACKGROUND_GOAL`; e o erro de leitura do arquivo, sem sobrescrever (FR-010, FR-013)
- [X] T024 [US3] Em `src/ui/BenchScreen.tsx`, a `ShelfList` acima da `CollectionList`
- [X] T025 [P] [US3] Em `src/ui/CollectionList.tsx`, o tipo e a luz de cada sessão — "treino · dia", "prova", "sem tipo" (FR-001)
- [ ] T026 [US3] 🚦 **SC-006** conforme o [quickstart](./quickstart.md), passos 1 e 4: as prateleiras sobrevivem a fechar o app, e o guia a apagar as sessões

**Checkpoint**: a variedade das fotos é garantida sem caderno.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T027 [P] Auditar o Swift e a fronteira: atravessam só `tags` e `session`, texto e números (princípio II); nada de vocabulário ou meta no nativo, que grava sem validar (princípio IV) — **passou.** O Swift novo só repassa `tags` e as três chaves de `session` para o JSON, e compõe o recorte sobre preto. O Expo entrega `null` de JavaScript como `NSNull` (`JavaScriptValue.getAny`), que o `JSONSerialization` aceita. Sem Mac, a compilação fica para a CI
- [X] T028 [P] `npx tsc --noEmit` sem erro novo
- [X] T029 [P] Atualizar `mobile/README.md` e o `README.md` da raiz: a 008 na tabela de estado, treino e prova, e como rodar `tools/coleta.py`
- [X] T032 [US1] Em `tools/coleta.py`, o contorno redesenhado pelo SAM 2.1 com a caixa de cada livro, padrão do `pacote`, e `--sem-sam` para o da máscara do app; o PyTorch de CPU declarado no cabeçalho; os pesos em `~/.cache/vizi/`; uma linha por imagem; e o Ultralytics sem gravar em `runs/` (R58) — **feita em 22/10**, depois de o autor achar ruins os contornos do primeiro pacote no Roboflow. As 16 imagens de 20/10 em 2,5 min, com lombadas e topos justos nas prévias
- [X] T033 [US1] Em `tools/coleta.py`, `--so-imagens`: o pacote sem contorno nem COCO, para a IA do Roboflow marcar (R59) — **feita em 22/10**, a pedido do autor; as 16 imagens de 20/10 em 4 s, todas passando na conferência
- [ ] T030 🚦 **SC-007** conforme o [quickstart](./quickstart.md), passo 6: fora do modo, o resultado como antes, abaixo de 1,5 s, e o histórico funcionando
- [ ] T031 Registrar em `specs/008-coleta-treino/research.md` as medições do aparelho — a volta do modo rápido, o tamanho de uma sessão de treino, como o Roboflow tratou as fotos sem livros —, fechando R48 e R54

---

## Dependencies

```
Setup (T001-T004)
   └─► Foundational (T005-T010)   fronteira, prateleiras, modo rápido
          ├─► US1 treino e pacote (T011-T018)      🚦 T016 · T017 · T018
          ├─► US2 prova e relatório (T019-T022)    🚦 T022
          └─► US3 cadastro e guia (T023-T026)      🚦 T026
                 └─► Polish (T027-T031)            🚦 T030
```

**Os portões no aparelho da US1 e da US2 pedem prateleiras cadastradas**, que
a tela da US3 cadastra. O código das três anda separado; a validação no
aparelho começa pela T023 e T024.

**A ferramenta não depende do app.** A T015 e a T021 rodam já nas sessões de
20/10 — a T016 é o primeiro portão, antes de qualquer build.

## Parallel Execution Examples

- **Setup**: depois da T001, a T002, a T003 e a T004.
- **Foundational**: a T007 (Swift, `CollectionWriter`) e a T008 (TypeScript, novo) andam com a T005 e a T006, que tocam os mesmos dois arquivos Swift e vão uma depois da outra; a T009 e a T010 depois da T001 e da T002.
- **US1**: a T011, a T012 e a T013 juntas, e a T015 (Python) em paralelo com toda a tela; a T014 espera as três.
- **US2 e US3**: a T019, a T021, a T023 e a T025 juntas.

## Implementation Strategy

**O MVP é a US1**, e vale sozinha: fotos de treino viram um pacote para o
Roboflow.

**Cinco portões.**

- **T016 vem primeiro e não precisa de build**: prova que a ferramenta gera o
  que o modelo lê, nas capturas que já existem.
- **T018 é o mais importante.** É a promessa da spec: o Roboflow aceita o
  pacote e os contornos poupam o desenho.
- **T017** prova que o modo rápido é rápido.
- **T022** fecha a régua do gate.
- **T030** prova que nada mudou fora do modo.

**Um build nativo** cobre tudo: o Swift é só da fase 2.

**Medir em Release.**
