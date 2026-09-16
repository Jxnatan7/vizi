---
description: "Task list for Câmera ao vivo e telemetria"
---

# Tasks: Câmera ao vivo e telemetria

**Input**: Design documents from `/specs/002-camera-telemetry/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: sem tarefas de teste automatizado, pelo mesmo motivo do marco 1 —
nem câmera nem acelerador existem num runner de CI. A verificação é a sessão no
aparelho.

**Organization**: agrupadas por história de usuário, em ordem de prioridade.

## Format: `[ID] [P?] [Story] Description`

## Path Conventions

Caminhos relativos a `mobile/`.

---

## Phase 1: Setup

- [x] T001 Declarar `NSCameraUsageDescription` em `mobile/app.config.js` — sem isso o iOS encerra o app na primeira tentativa de acesso, sem diálogo — `infoPlist` em `app.config.js`; sem isso o iOS encerra o app sem diálogo
- [x] T002 [P] Instalar `expo-clipboard` para a exportação do registro (FR-013) — `expo-clipboard ~57.0.2`
- [x] T003 [P] Criar `mobile/src/ui/CameraScreen.tsx` vazio e alternância entre ele e a `BenchScreen` — as duas telas convivem — abas Câmera/Medição em `App.tsx`; `parts.tsx` extraído para as duas telas

**Checkpoint**: o app abre e alterna entre as duas telas.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: frames reais chegando ao Swift, antes de qualquer transformação ou inferência.

**⚠️ CRITICAL**: se a captura não estiver sólida, todo problema posterior vai parecer de inferência.

- [x] T004 Criar `modules/vizi-vision/ios/CameraSession.swift`: `AVCaptureSession`, escolha explícita de dispositivo e formato, delegate em fila dedicada — resolve **R6** — menor formato com ambos os lados ≥ 640, BGRA, rotação 90° para retrato
- [x] T005 Criar `modules/vizi-vision/ios/FrameGate.swift`: profundidade 1, descarte do mais antigo, contadores de recebidos e descartados — profundidade 1, contadores de recebidos/descartados/processados
- [x] T006 Expor `startSession` / `stopSession` em `ViziVisionModule.swift`, com verificação de permissão e erro legível na tela (FR-011) — `startSession`/`stopSession`/permissão, e `OnDestroy` desliga a câmera
- [x] T007 Verificar frames chegando: emitir só a contagem de capturados, sem transformação e sem inferência — evento `onTelemetry` a 2 Hz com taxas da janela

**Checkpoint**: a contagem de frames sobe na tela. A captura está viva.

---

## Phase 3: User Story 1 - Ver a cena sendo processada em tempo real (Priority: P1) 🎯 MVP

**Goal**: apontar o aparelho e ver a imagem que o modelo recebe, com contagem reagindo ao movimento.

**Independent Test**: apontar para uma estante e depois para uma parede vazia; a contagem sobe e cai.

### Implementation for User Story 1

- [x] T008 [US1] Criar `modules/vizi-vision/ios/FrameTransform.swift`: as três transformações sobre `CVPixelBufferPool` reutilizado — resolve **R7** — Core Image sobre Metal, `CVPixelBufferPool` reutilizado, cinza 114 no letterbox
- [x] T009 [US1] Criar `modules/vizi-vision/ios/PreviewView.swift`: Expo Module View com `AVSampleBufferDisplayLayer` — `AVSampleBufferDisplayLayer`, exibição imediata
- [x] T010 [US1] Ligar o preview ao buffer **transformado**, com retenção explícita nos dois caminhos — resolve **R8**; se o pool esvaziar, a captura trava — preview e inferência recebem o MESMO buffer transformado; pool com 6 de folga
- [ ] T011 [US1] 🚦 Verificar orientação olhando o preview — resolve **R9**. Imagem deitada invalida toda medição posterior
- [x] T012 [US1] Adaptar `InferenceEngine.runOnce` para aceitar buffer externo em vez do de referência — `InferenceEngine.run(on:)`, com `decodeMs` separado
- [x] T013 [US1] Emitir `onTelemetry` a ~2 Hz com a contagem — **nunca por frame** (princípios II e III) — contagem e medianas da janela no evento de 2 Hz
- [x] T014 [US1] Montar `CameraScreen.tsx`: preview, contagem, iniciar e parar — preview quadrado, seletor de transformação e tempos por estágio
- [x] T015 [US1] Estado de permissão negada, explicando como conceder (FR-011) — mensagem explicando como conceder em Ajustes

**Checkpoint**: o app processa o mundo. Primeira vez no projeto.

---

## Phase 4: User Story 2 - Saber se o aparelho aguenta uso contínuo (Priority: P2)

**Goal**: o número que substituiu "cabe no tempo?" — quanto custa em calor e bateria.

**Independent Test**: 10 minutos apontado para cena estável; ler o registro ao fim.

### Implementation for User Story 2

- [ ] T016 [US2] Criar `modules/vizi-vision/ios/Telemetry.swift`: buffer circular limitado, com aviso de truncamento
- [ ] T017 [US2] Medir latência ponta-a-ponta a partir do `presentationTimeStamp` do frame (**FR-009**) — não do início do processamento
- [ ] T018 [US2] [P] Registrar estado térmico, bateria e o instante de cada transição térmica (**FR-007**)
- [ ] T019 [US2] Separar os tempos de transformação, inferência e decodificação — é o que responde se a R7 virou problema
- [ ] T020 [US2] Montar a `Session` e devolvê-la em `stopSession`, com condições iniciais
- [ ] T021 [US2] [P] Criar `mobile/src/telemetry/exportSession.ts`: sessão → JSON → área de transferência
- [ ] T022 [US2] Exibir a sessão em andamento na `CameraScreen`
- [ ] T023 [US2] Parar captura e inferência ao sair de primeiro plano, retomar ao voltar (**FR-010**)
- [ ] T024 [US2] 🚦 **Rodar a sessão de 10 minutos** conforme o protocolo do `quickstart.md` e conferir SC-001 a SC-005, SC-007

**Checkpoint**: existe resposta sobre sustentação. É o propósito do marco.

---

## Phase 5: User Story 3 - Confiar que o frame vira entrada correta (Priority: P3)

**Goal**: descobrir qual transformação reproduz o dataset, medindo em vez de supor.

**Independent Test**: três sessões curtas na mesma cena, uma por transformação, comparando contagem.

### Implementation for User Story 3

- [x] T025 [US3] Seletor de transformação na `CameraScreen`, trocável com a sessão rodando (**FR-005**) — seletor trocável com a sessão rodando
- [ ] T026 [US3] Três sessões de 1 minuto, mesma cena e mesmo apoio, comparando contagem e estabilidade
- [ ] T027 [US3] Confirmar no Roboflow qual Resize foi usado e fixar o padrão — **confirmação e medição precisam concordar**; se discordarem, a causa merece investigação, não escolha arbitrária

**Checkpoint**: a geometria deixou de ser suposição.

---

## Phase 6: Polish & Cross-Cutting

- [ ] T028 [P] Registrar as medições em `specs/002-camera-telemetry/research.md`, fechando R6–R9
- [ ] T029 Auditar a fronteira: nenhum pixel atravessa; `TelemetrySample` pequena; evento a ~2 Hz e não por frame
- [ ] T030 Auditar o Swift: nenhuma constante de política (a T037 do marco 1 reprovou nesta mesma verificação)
- [ ] T031 Verificar **FR-002**: nenhuma marcação desenhada sobre a imagem
- [ ] T032 Atualizar `mobile/README.md` com o veredito do marco

---

## Dependencies

```
Setup (T001-T003)
   └─► Foundational (T004-T007)   ⚠️ captura sólida antes de tudo
          └─► US1 (T008-T015)      🚦 T011: orientação
                 └─► US2 (T016-T024)   🚦 T024: o portão do marco
                        └─► US3 (T025-T027)
                               └─► Polish (T028-T032)
```

**A US3 poderia vir antes da US2**, e há um argumento para isso: medir 10
minutos com a transformação errada desperdiça 10 minutos. Fica depois mesmo
assim porque o portão do marco é térmico, e o térmico não depende de qual
transformação está ativa — o custo por frame é o mesmo nas três.

## Parallel Execution Examples

- **Setup**: T002 e T003 em paralelo com T001.
- **US2**: T018 (térmico/bateria) e T021 (exportação) não se tocam.
- **Polish**: T029, T030 e T031 são auditorias independentes.

## Implementation Strategy

**O MVP é a US1**, e ela vale por si: um app que mostra o que o modelo vê e
conta objetos em tempo real já é a primeira vez que o projeto processa o mundo.

**Dois portões, em ordem de custo.** T011 (orientação) custa um segundo de olhar
e invalida tudo que vem depois se estiver errado. T024 (térmico) custa 10
minutos e decide a cadência do app.

**Se o térmico estourar em T024, o marco não falhou** — respondeu. A decisão
adiada sobre inferir todo frame se resolve com número, e limitar a cadência é
barato de acrescentar.
