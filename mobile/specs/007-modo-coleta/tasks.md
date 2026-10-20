---
description: "Task list for Modo coleta"
---

# Tasks: Modo coleta

**Input**: Design documents from `/specs/007-modo-coleta/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/collection.md](./contracts/collection.md), [contracts/zip-format.md](./contracts/zip-format.md), [quickstart.md](./quickstart.md)

**Tests**: sem suíte automatizada, como nos marcos anteriores. Verificação no
aparelho, **em Release**, pelo [quickstart](./quickstart.md), e no zip real,
pelo `tools/check-zip.py` (T022) — que é instrumento de medição, não teste.

**Organization**: por história. O gravador nasce sem nada novo na tela (fase
2); a US1 grava as capturas e exporta; a US2 acrescenta as marcas; a US3 cuida
das sessões no aparelho.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode ser feita em paralelo — arquivo diferente, sem dependência pendente
- **[Story]**: a história da spec (US1, US2, US3)
- 🚦: portão — verificação no aparelho ou no zip que decide se a fase vale

## Path Conventions

Caminhos relativos a `mobile/`.

---

## Phase 1: Setup

**Purpose**: o contrato e a política em TypeScript, e o formato no bundle, antes de qualquer Swift.

- [X] T001 Em `modules/vizi-vision/src/ViziVision.types.ts`, os tipos de [contracts/collection.md](./contracts/collection.md) — `CollectionOptions`, `CollectionState`, `MarkReceipt`, `CollectionSummary` (com `endReason: 'stopped' | 'background' | 'recovered' | null`), `ExportOutcome` —, e em `CaptureResult` os campos `collectionItemId: string | null` e `collectionSkipped: 'space' | null`, comentados com as regras da tabela do contrato
- [X] T002 [P] Em `modules/vizi-vision/src/ViziVisionModule.ts`, as funções `startCollection`, `stopCollection`, `getCollectionState` (síncrona), `markFrame`, `answerItem`, `resumeLive`, `listCollections`, `renameCollection`, `deleteCollection`, `exportCollection`, e o evento `onCollectionChange` ("só em mudança discreta, nunca por quadro")
- [X] T003 [P] Criar `src/collection/policy.ts` com `DEFAULT_COLLECTION: { minScore: 0.05, minFreeBytes: 1_000_000_000, jpegQuality: 0.9 }`, cada campo comentado com o que decide (data-model, "Política da coleta") — inclusive que a gravação usa "o menor entre `minScore` e o limiar da sessão"
- [X] T004 [P] Em `plugins/withViziAssets.js`, copiar `specs/007-modo-coleta/contracts/zip-format.md` para `Resources/FORMAT.md`, falhando alto se não existir, como os outros assets; e em `modules/vizi-vision/ios/ViziVision.podspec`, `'Resources/FORMAT.md'` no `resource_bundles` — caminho explícito, como os outros (R44)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: o gravador, a escrita e o rastro, sem nada novo na tela.

**⚠️ CRITICAL**: as três histórias dependem destas peças.

- [X] T005 Em `modules/vizi-vision/ios/InferenceEngine.swift`: `RunResult.detections`, o tensor cru de detecção, devolvido junto com as instâncias — referência, sem cópia, porque o Core ML aloca saídas novas a cada predição (R38); e, na carga, o SHA-256 do arquivo de pesos do modelo compilado (CryptoKit) e os metadados `creatorDefinedKey`, guardados para o `session.json` (R45)
- [X] T006 [P] Criar `modules/vizi-vision/ios/CollectionWriter.swift` (R40, R41): JPEG pela CPU — `VTCreateCGImageFromCVPixelBuffer` e `CGImageDestination` com a qualidade recebida —; a foto e o quadro em retrato nos próprios pixels, girados 90° no sentido horário com o vImage quando mais largos que altos, sem EXIF de orientação; os protótipos `[1, 32, 160, 160]` fp32 para `float16` little-endian sem cabeçalho, respeitando os `strides` do `MLMultiArray`; JSON escrito com `.atomic`; e a escrita de um item em `items/.tmp-<id>/` com `rename` para `items/<id>/` no fim — "Gravando não existe para ninguém"
- [X] T007 [P] Criar `modules/vizi-vision/ios/CollectionTrace.swift` (R38, data-model "Detecção gravada"): a decodificação para gravar — `Decode.instances` sobre o tensor cru com o limiar `min(minScore, confidenceThreshold)` e o IoU da sessão —; a detecção gravada (`anchor`, `score`, `box`, `coef`) e as marcas `exists`, `inBand`, `shown`, `inCore`, `counted` com as regras do formato; a junção pela âncora; os rastros `MarkTrace` e `CaptureTrace` com os campos de [zip-format.md](./contracts/zip-format.md); e a serialização para `item.json`, com as chaves do formato
- [X] T008 Criar `modules/vizi-vision/ios/CollectionRecorder.swift` (R36, R41, R42, R43, R45, R46): a pasta `Documents/collection/<id>/` com o id no instante de abertura (`2026-10-19T14-03-22`); `session.json` com app, aparelho (`utsname`), sistema, modelo (T005) e as políticas como chegaram; uma fila serial utilitária para todo o disco; "Uma aberta por vez"; fechar espera a fila, grava o fim e o `endReason`, e "Sem itens não sobrevive ao fechamento nem à recuperação"; a recuperação na criação — apagar `.tmp-*`, fechar órfãs com `endReason: "recovered"` e o fim no último item, apagar as vazias —; o segundo plano por `UIApplication.didEnterBackgroundNotification`, com tarefa de segundo plano até a fila esvaziar, e **não** por `inactive`; o espaço por `volumeAvailableCapacityForImportantUsage` contra `minFreeBytes`; contadores e bytes; o item à espera — "Só o item à espera aceita resposta" — e o `truth.json` de [R43](./research.md#r43--a-contagem-real), com "inteiro ≥ 0, ou ausente quando pulou", escrito na fila depois do item; a telemetria em `telemetry.jsonl`, uma linha por amostra e por início e fim de câmera; `listCollections` lendo os `session.json`; e o estado para o evento
- [X] T009 Em `modules/vizi-vision/ios/ViziVisionModule.swift`: o gravador criado com o módulo, e a recuperação rodando na criação; as funções `startCollection` (com as opções recebidas), `stopCollection`, `getCollectionState`, `answerItem` e `listCollections`; o evento `onCollectionChange`, emitido pelo gravador em abrir, fechar, item gravado, resposta gravada e espaço cruzando o limite; o `onSample` da sessão de câmera também anexando a amostra ao gravador; as linhas de início e fim de câmera em `startSession` e `stopSession`; e `dismissResult` e `endResultState` liberando o item à espera. As recusas com o código no começo da mensagem (`"stale: …"`)
- [X] T010 [P] Criar `src/collection/useCollection.ts`: o estado inicial de `getCollectionState()` e o espelho por `onCollectionChange`; `start()` enviando `DEFAULT_COLLECTION` e, em `policies`, `DEFAULT_SESSION`, `DEFAULT_CAPTURE`, `DEFAULT_BAND`, `DEFAULT_OVERLAY` e `DEFAULT_COLLECTION` como estão; `stop()`; `answer(itemId, count | null)`; `list()`; e os erros com o código traduzido para frase

**Checkpoint**: tudo compila, e com a coleta fechada o app se comporta exatamente como na 006.

---

## Phase 3: User Story 1 - Uma sessão de capturas, com a verdade ao lado, num zip (Priority: P1) 🎯 MVP

**Goal**: com o modo ligado, cada captura grava as imagens e os dados de cada etapa e a contagem real; a sessão fechada sai num zip pelo menu de compartilhar.

**Independent Test**: abrir uma sessão, cinco capturas respondendo, fechar e exportar; o zip traz as cinco, e a checagem refaz a contagem de cada uma.

- [X] T011 [US1] Em `modules/vizi-vision/ios/Reread.swift`, o `Outcome` ganha o quadrado da releitura, `content`, `core`, `membership`, todas as instâncias antes da regra das bordas e o tensor cru; e `reread(_:books:options:)`, em `modules/vizi-vision/ios/ViziVisionModule.swift`, os preenche. A lista que conta não muda
- [X] T012 [US1] Em `capture`, em `modules/vizi-vision/ios/ViziVisionModule.swift`, o rastro da foto — **só com a coleta aberta e com espaço**, conferido no começo: a foto, o quadrado da foto, o `RunResult` da foto com o tensor cru, a faixa do toque e a fração, o modo de transformação, os limiares (confiança e IoU da sessão, aparência do `PreviewSink.shared.style`), a gravidade, a focal, o campo de visão, o horizonte, os pontos de fuga, `sourceQuad`, `books`, `fullyRectified`, as fileiras e os deitados da estimativa **convertidos para âncoras** das instâncias da faixa, as confianças, o motivo da recusa, `usedGravity`, a curva de azimute quando houver, o recorte renderizado e as opções da captura. Nenhum valor calculado muda e nada novo acontece antes do `readyMs` (FR-003)
- [X] T013 [US1] No fim de `capture`, em `modules/vizi-vision/ios/ViziVisionModule.swift`, depois do retorno montado: a releitura no rastro (T011), com fileiras e deitados em âncoras; o resultado e os tempos; o rastro entregue ao gravador, que devolve o id do item; e no retorno `collectionItemId` e `collectionSkipped` (`'space'` quando a coleta estava aberta e sem espaço). Um erro no rastro nunca derruba a captura: ela segue sem gravar
- [X] T014 [US1] O trabalho da captura no gravador, em `modules/vizi-vision/ios/CollectionRecorder.swift` e `modules/vizi-vision/ios/CollectionTrace.swift`: decodificar a 0,05 a foto e a releitura; marcar `exists`, `inBand` (foto), `inCore` e `counted`; codificar **primeiro** os dois quadrados, que vêm do pool do `FrameTransform` (R40), depois o recorte e a foto girada; os protótipos de cada leitura; o `item.json` com `recordMs`; trocar o nome da pasta; tornar o item o que espera resposta; atualizar contadores e bytes e emitir o evento
- [X] T015 [P] [US1] Criar `src/ui/TruthPrompt.tsx`: o pedido da contagem real — o número em destaque, − e + (nunca abaixo de 0), "Confirmar" e "Pular" —, preenchido pelo valor recebido, e que some depois de responder; serve à captura e à marca
- [X] T016 [P] [US1] Criar `src/ui/CollectionIndicator.tsx`: ponto de gravação, o tempo desde `startedAt` redesenhado a 1 Hz (R46), marcas, capturas e megabytes
- [X] T017 [US1] Em `src/ui/CameraScreen.tsx`: ligar e desligar o modo coleta (`useCollection`), com o `CollectionIndicator` enquanto aberto; no resultado de uma captura com `collectionItemId`, o `TruthPrompt` preenchido com `result.count`, mandando `answer(id, n)` ou `answer(id, null)`; com `collectionSkipped: 'space'`, o aviso "Captura não gravada na coleta: pouco espaço livre"; e o histórico como hoje (FR-003, FR-007)
- [X] T018 [US1] Criar `modules/vizi-vision/ios/CollectionExport.swift` (R44): conferir o espaço; copiar o `FORMAT.md` do bundle `ViziVisionAssets` para a pasta da sessão; ler a pasta por `NSFileCoordinator` com `.forUploading` e copiar o zip para `collection/<id>.zip`, substituindo o anterior; apresentar um `UIActivityViewController` na thread de interface a partir do controlador atual do Expo, com o nome sugerido `vizi-coleta-<id>[-<nome>].zip`; resolver quando o menu fecha com `{ file, bytes, shared }`; e gravar `export` no `session.json`. "Só a fechada exporta"
- [X] T019 [US1] Em `modules/vizi-vision/ios/ViziVisionModule.swift`, `exportCollection`, com as recusas `open`, `missing` e `space`; e em `src/collection/useCollection.ts`, `exportSession(id)`
- [X] T020 [P] [US1] Criar `src/ui/CollectionList.tsx`: as sessões, mais recente primeiro, com data, nome, marcas, capturas, respondidas e megabytes; a aberta como "em andamento", sem exportar; "Exportar" com "Gerando zip…" enquanto trabalha e o erro na tela
- [X] T021 [US1] Em `src/ui/BenchScreen.tsx`, a `CollectionList`, recarregada ao montar e a cada `onCollectionChange`
- [X] T022 [P] [US1] Criar `specs/007-modo-coleta/tools/check-zip.py` — Python 3 da biblioteca padrão, Pillow só para desenhar, opcional —: conferir `format: 1`; para cada item, refazer `inBand` e `inCore` a partir de `box`, `band` e `reread.core` e comparar a contagem com `result.count` (pela origem) e `frameCount` (SC-002); conferir o `truth.json` na pasta do item; as imagens que o `item.json` lista, as quatro nas capturas com recorte (SC-003); nenhuma `.tmp-*` (SC-006); desenhar as caixas `shown` das marcas sobre `square.jpg` numa pasta de saída (SC-005); resumir a telemetria — `fpsCaptured` fora dos instantes de captura e de volta a 60 depois de cada item (SC-001); e imprimir, por item com resposta, a contagem do app contra a real e quantas detecções ficaram abaixo do limiar
- [ ] T023 [US1] 🚦 **SC-004** e o comportamento conforme `specs/007-modo-coleta/quickstart.md`, itens 1, 5, 6, 8 e 11: o indicador, dez capturas com `toque → pronto` abaixo de 1,5 s, o histórico só com a salva, sair sem responder, a sessão na Medição e a exportação pelo menu de compartilhar
- [ ] T024 [US1] 🚦 **SC-002 e SC-003** com o `tools/check-zip.py` sobre o zip real da T023: toda contagem refeita igual à da tela, toda resposta no seu item, as quatro imagens em toda captura com recorte

**Checkpoint**: capturas com gabarito saem do aparelho num zip legível. Sozinho, é o pedido.

---

## Phase 4: User Story 2 - Marcar o ao vivo (Priority: P2)

**Goal**: um toque grava o próximo quadro processado — as duas imagens e as detecções dele — com a tela parada nele e a contagem real pedida.

**Independent Test**: cinco marcas com o aparelho em movimento; desenhadas sobre a imagem gravada, as caixas caem sobre os livros.

- [X] T025 [P] [US2] Em `modules/vizi-vision/ios/OverlayRenderer.swift`, no `ResultStore`, uma escrita que ignora a pausa **sem** marcar o conteúdo como da captura: o quadro parado é desenhado como o ao vivo, com a faixa e o limiar de aparência (R37) — **não foi preciso.** O congelamento acontece na fila da câmera logo depois de o quadro publicar as próprias detecções, e o preview recebeu o quadrado dele antes da inferência: congelar e pausar ali deixa na tela exatamente o quadro marcado, em modo ao vivo, sem escrita nenhuma por cima (nota em R37)
- [X] T026 [P] [US2] Em `modules/vizi-vision/ios/BandRenderer.swift`, a mediana mostrada legível de fora (`nil` quando a pílula não aparece); e em `modules/vizi-vision/ios/PreviewView.swift`, `displayedCount` e uma trava do gesto da faixa que o `BandGesture` respeita
- [X] T027 [US2] Em `modules/vizi-vision/ios/SessionCoordinator.swift`, `requestMark(_:)`: um pedido pendente atendido pelo próximo `process` **depois** de publicar o resultado do quadro — fotografar o buffer da câmera, o quadrado, o `RunResult` com o tensor cru, a faixa, a gravidade e o carimbo do quadro; congelar o preview e pausar o `ResultStore` ali, na mesma fila, para nenhum quadro seguinte entrar; e entregar a fotografia. Sem pedido, nenhum custo (R37)
- [X] T028 [US2] Em `modules/vizi-vision/ios/ViziVisionModule.swift`, `markFrame` e `resumeLive` (contrato): recusar `closed`, `camera`, `busy` (resultado pausado ou preview congelado) e `space`; ler `displayedCount` na thread de interface no toque; travar o gesto da faixa; pedir o quadro; mostrar o quadrado com `showStill` e publicar as detecções dele com a escrita da T025; entregar o rastro ao gravador; resolver com `{ itemId, displayedCount, frameCount }`. `resumeLive` limpa o `ResultStore`, solta pausa e congelamento, destrava a faixa e libera o item à espera; `stopSession` e `endResultState` fazem o mesmo com um quadro parado
- [X] T029 [US2] O trabalho da marca no gravador, em `modules/vizi-vision/ios/CollectionRecorder.swift` e `modules/vizi-vision/ios/CollectionTrace.swift`: decodificar a 0,05; marcar `exists`, `inBand`, `shown`, `counted`; `frameCount` = `exists ∧ inBand`; codificar `square.jpg` primeiro e `frame.jpg` em retrato; os protótipos; o `item.json` com `displayedCount`; trocar o nome; tornar o item o que espera resposta
- [X] T030 [US2] Em `src/collection/useCollection.ts`, `mark()` e `resume()`
- [X] T031 [US2] Em `src/ui/CameraScreen.tsx`, "Marcar" com a coleta aberta, a câmera rodando e o estado ao vivo (FR-010); o estado `'marked'`, que esconde a cápsula da faixa e o "Capturar"; o `TruthPrompt` preenchido com `displayedCount ?? frameCount`, mandando a resposta e então `resume()`; e as recusas como frase
- [ ] T032 [US2] 🚦 **SC-005** conforme `specs/007-modo-coleta/quickstart.md`, itens 2 a 4, e o `tools/check-zip.py`: o quadro parado é o da tela, dez marcas em movimento com as caixas sobre os livros, marcar indisponível onde não pode

**Checkpoint**: o ao vivo também entra no gabarito, sob demanda.

---

## Phase 5: User Story 3 - As sessões no aparelho (Priority: P3)

**Goal**: nomear, exportar de novo e apagar sessões; aba e segundo plano com o comportamento escolhido; a coleta não enche o aparelho.

**Independent Test**: três sessões; nomear uma, exportá-la duas vezes, apagar outra; a lista acompanha, e a apagada some da pasta.

- [X] T033 [US3] Em `modules/vizi-vision/ios/CollectionRecorder.swift` e `modules/vizi-vision/ios/ViziVisionModule.swift`, `renameCollection` e `deleteCollection` — "Só a fechada exporta, recebe nome e é apagada", recusando `open` e `missing` —; apagar leva a pasta e o zip
- [X] T034 [US3] Em `src/collection/useCollection.ts`, `rename(id, name)` e `remove(id)`; e em `src/ui/CollectionList.tsx`, o nome editável, "Apagar" com confirmação e "Exportar de novo"
- [X] T035 [US3] Em `src/ui/CollectionIndicator.tsx` e `src/ui/CameraScreen.tsx`, o aviso de pouco espaço quando `lowSpace`, e a recusa `space` do "Marcar" como frase (FR-020)
- [ ] T036 [US3] 🚦 **SC-006** e o ciclo de vida conforme `specs/007-modo-coleta/quickstart.md`, itens 9, 10 e 12: a aba não fecha, o segundo plano fecha, a Central de Controle não fecha, o encerramento forçado deixa a sessão fechada e sem item pela metade, e o espaço recusa como deve

**Checkpoint**: a coleta aguenta semanas de uso, sessão após sessão.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T037 [P] Auditar a fronteira e o Swift em `modules/vizi-vision/ios/`: nada da coleta atravessa além de identificadores, contagens, bytes, resumos e as políticas uma vez por sessão (princípio II); nenhum valor de ajuste fixo no nativo — ficam a definição do formato (fp16, `[32, 160, 160]`, nomes de arquivo), a regra de girar para retrato e as guardas (princípio IV) — **passou, com um conserto.** Atravessam o estado da coleta, o recibo da marca, os resumos das sessões e o resultado da exportação, todos números, textos e caminhos relativos; imagens, protótipos e tensores vão do buffer ao disco no nativo. A folga de espaço do exportar era um número fixo no Swift (`× 1,1 + 50 MB`) e passou a ser o `minFreeBytes` da política que a sessão gravou. No Swift novo sobram conversões de unidade, a cor de fundo exigida pelo giro do vImage, os nomes de arquivo e a forma dos protótipos
- [ ] T038 🚦 **SC-001** conforme `specs/007-modo-coleta/quickstart.md`, item 7: uma sessão de 5 min com pelo menos 10 marcas e 10 capturas; o resumo de telemetria do `tools/check-zip.py` com 60 fps fora das capturas e de volta a 60 depois de cada item
- [X] T039 [P] Atualizar `mobile/README.md` e o `README.md` da raiz: a 007 na tabela de estado, o que o modo faz e onde as sessões ficam
- [ ] T040 Registrar em `specs/007-modo-coleta/research.md` as medições — `recordMs` da marca e da captura, o tempo da decodificação a 0,05, o tamanho típico de uma sessão e do zip —, fechando R37 a R46
- [ ] T041 A primeira leitura do modelo com dado real: rodar o `tools/check-zip.py` sobre a sessão da T038 e registrar em `specs/007-modo-coleta/research.md` a contagem do app contra a real e o que as detecções abaixo do limiar dizem sobre os erros que se repetem — a pergunta que motivou a spec

---

## Dependencies

```
Setup (T001-T004)
   └─► Foundational (T005-T010)   o gravador, nada novo na tela
          └─► US1 capturas e zip (T011-T024)        🚦 T023 · T024
                 ├─► US2 marcas (T025-T032)           🚦 T032
                 └─► US3 sessões (T033-T036)          🚦 T036
                        └─► Polish (T037-T041)        🚦 T038
```

**A US2 e a US3 dependem da US1 só pela tela e pela checagem.** O
`TruthPrompt`, o indicador, a lista e o `check-zip.py` nascem na US1. No
nativo, as marcas (US2) e o nome e o apagar (US3) não se tocam e podem andar
juntos.

**A 006 ainda não teve build.** O primeiro build desta branch compila as duas;
um erro de compilação da 006 aparece aqui, e se resolve aqui.

## Parallel Execution Examples

- **Setup**: depois da T001, a T002, a T003 e a T004.
- **Foundational**: a T006 (`CollectionWriter`, novo), a T007 (`CollectionTrace`, novo) e a T010 (TypeScript) andam juntas, depois da T005; a T008 espera a T006 e a T007; a T009 espera a T008.
- **US1**: a T015, a T016, a T020 e a T022 andam junto com o Swift das T011 a T014; a T018 (`CollectionExport`, novo) também.
- **US2**: a T025 e a T026 andam juntas; a T027 e a T028 esperam as duas.
- **US2 e US3**: as T025–T029 e as T033 tocam arquivos em comum só no `ViziVisionModule.swift` e no `CollectionRecorder.swift` — juntas, uma de cada vez nesses dois.

## Implementation Strategy

**O MVP é a US1**, e vale sozinha: capturas com a contagem real, num zip que a
checagem lê e confere.

**Seis portões.**

- **T024 é o mais importante.** É a promessa do zip: os dados reproduzem cada
  contagem da tela. Se falhar, o gabarito não vale nada.
- **T023** prova que a coleta não muda o app — o tempo e o histórico iguais.
- **T032** fecha a marca: imagem e caixas do mesmo quadro.
- **T036** protege as sessões do segundo plano, do encerramento forçado e do
  disco cheio.
- **T038** prova que gravar não custa quadros.
- **T041 não é portão**, mas é o motivo da spec: a primeira medida do modelo
  com dado real.

**Um build nativo** cobre a fase 2 e a US1; a US2 e a US3 cabem num segundo, ou
no mesmo, se forem feitas antes do primeiro.

**Medir em Release.**
