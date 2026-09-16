---
description: "Task list for Overlay de caixas e máscaras"
---

# Tasks: Overlay de caixas e máscaras

**Input**: Design documents from `/specs/003-overlay-mascaras/`

**Tests**: sem suíte automatizada. A verificação é visual no aparelho mais a
comparação de telemetria com e sem overlay.

## Format: `[ID] [P?] [Story] Description`

## Path Conventions

Caminhos relativos a `mobile/`.

---

## Phase 1: Setup

- [x] T001 [P] Criar `src/overlay/style.ts` com o `OverlayStyle` padrão — espessura, opacidade, paleta e `minConfidence` (FR-010) — `src/overlay/style.ts`
- [x] T002 [P] Acrescentar `OverlayStyle` aos tipos do módulo e `setOverlayStyle` à superfície nativa — `OverlayStyle` tipado e `setOverlayStyle` no módulo
- [x] T003 Controles de ligar e desligar caixas e máscaras na `CameraScreen` (FR-003) — alternância de caixas e máscaras na tela

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: o resultado precisa estar disponível ao desenho sem que o desenho espere por ele.

**⚠️ CRITICAL**: é aqui que o princípio I pode cair. Se o overlay puxar o resultado da fila da câmera, inferência e desenho passam a se bloquear.

- [x] T004 `Decode.swift` passa a extrair os **32 coeficientes de máscara** de cada instância sobrevivente — hoje são lidos e descartados — extraídos **depois** do NMS, só para os sobreviventes
- [x] T005 `InferenceEngine` passa a reter a saída de protótipos `[1,32,160,160]`, resolvida por forma como as demais — `RunResult.protos`, resolvida por forma
- [x] T006 Publicar o último resultado em `SessionCoordinator`, com leitura sem bloqueio — resolve **R12** — `ResultStore`: a inferência publica, o desenho lê — **R12 resolvida**
- [x] T007 Criar `OverlayRenderer.swift` e empilhar as camadas na `PreviewView`, ainda sem desenhar nada — `OverlayRenderer` com `CADisplayLink`, camadas empilhadas na `PreviewView`

**Checkpoint**: as camadas existem e a inferência continua a 60 fps. Nada mudou na tela.

---

## Phase 3: User Story 1 - Ver os objetos marcados (Priority: P1) 🎯 MVP

**Goal**: cada objeto detectado contornado, sobre a imagem que o modelo recebe.

**Independent Test**: apontar para a estante; as caixas caem sobre os livros.

- [x] T008 [US1] Desenhar as caixas numa `CAShapeLayer`, caminho reconstruído por frame — pool de `CAShapeLayer`, uma por caixa
- [x] T009 [US1] Aplicar `boxWidth` em pixels de imagem, não de tela — a view muda de tamanho, o espaço do modelo não — espessura em pixels de imagem, escalada pela view
- [x] T010 [US1] Cor determinística pela posição quantizada do centro — resolve **R11**; cor por índice piscaria a cada frame — cor por posição quantizada — **R11 resolvida**
- [x] T011 [US1] Respeitar `minConfidence` do estilo, separado do limiar de detecção — `minConfidence` separado do limiar de detecção
- [x] T012 [US1] 🚦 **SC-004 confirmado**: caixas nos lugares exatos, cores distintas entre vizinhos
- [x] T013 [US1] 🚦 **Fluido o tempo todo, na mão.** O marco 4 deixa de ser necessário para fluidez — ver `research.md`

**Checkpoint**: o resultado da inferência virou imagem. Primeira vez no projeto.

---

## Phase 4: User Story 2 - Ver a forma dos objetos (Priority: P2)

**Goal**: cada objeto preenchido pela própria silhueta. É o que o projeto existe para fazer.

**Independent Test**: a silhueta segue a lombada do livro, não o retângulo.

- [x] T014 [US2] Criar `MaskCompose.swift`: `cblas_sgemm` de `[N,32] × [32,25600]` — resolve **R10** — `cblas_sgemm`, memória reaproveitada entre frames
- [x] T015 [US2] Aplicar sigmoide e limiar, produzindo a silhueta por instância — limiar em `logit > 0`, equivalente a `sigmoid > 0.5`, sem 600 mil exponenciais
- [x] T016 [US2] Recortar cada máscara à sua caixa (**FR-005**) — fora da caixa, a resposta do protótipo é ruído — recorte à caixa; fora dela o protótipo é ruído
- [x] T017 [US2] Compor as instâncias num único bitmap 160×160 RGBA, desempate por confiança — resolve **R13** — desempate por confiança, escrita em ordem crescente — **R13 resolvida**
- [x] T018 [US2] Publicar o bitmap como `CGImage` na camada de máscara, com ampliação linear até 640 — `CGImage` 160×160 na camada, ampliação linear pelo compositor
- [x] T019 [US2] Aplicar `maskOpacity` e a paleta do estilo — opacidade e paleta do estilo
- [ ] T020 [US2] 🚦 Verificar **SC-005**: a silhueta segue o objeto e se distingue da caixa

**Checkpoint**: o app segmenta. É o marco que a arquitetura chamava de 5.

---

## Phase 5: User Story 3 - Saber quanto o desenho custa (Priority: P3)

- [x] T021 [US3] Cronometrar composição e desenho como estágios próprios na telemetria (**FR-006**) — `drawMs` já na telemetria desde o diagnóstico do overlay
- [x] T022 [US3] Garantir que o overlay mantém o último resultado quando uma inferência falha (**FR-009**) — o `ResultStore` mantém o último resultado; o overlay nunca apaga
- [ ] T023 [US3] 🚦 Três sessões na mesma cena — sem overlay, só caixas, caixas e máscaras — **em Release**
- [ ] T024 [US3] Conferir **SC-001** (60 fps mantidos) e **SC-002** (e2e não mais que 15% acima dos 39,6 ms)

**Checkpoint**: o custo do desenho é conhecido, não presumido.

---

## Phase 6: Polish & Cross-Cutting

- [ ] T025 [P] Registrar as medições em `research.md`, fechando R10–R13
- [ ] T026 Auditar a fronteira: nenhum pixel de máscara atravessa; o estilo é dado, não código
- [ ] T027 Auditar o Swift: nenhuma constante de aparência fora do `OverlayStyle`
- [x] T028 Decidir o futuro do marco 4 a partir do T013, e registrar na arquitetura — **marco 4 descartado** por decisão do autor em 16/09. Um rastreador simples pode voltar depois, se a cor piscando incomodar
- [ ] T029 Atualizar `mobile/README.md`

---

## Dependencies

```
Setup (T001-T003)
   └─► Foundational (T004-T007)   ⚠️ princípio I em risco
          └─► US1 caixas (T008-T013)     🚦 T012 geometria · T013 fluidez
                 └─► US2 máscaras (T014-T020)   🚦 T020
                        └─► US3 custo (T021-T024)   🚦 T024: o portão
                               └─► Polish (T025-T029)
```

**As caixas antes das máscaras, e não juntas.** Se o mapeamento de coordenadas
estiver errado, a caixa errada é óbvia e a máscara errada é ambígua — pode ser
geometria, composição, limiar ou recorte. Depurar uma coisa de cada vez custa
menos que depurar duas ao mesmo tempo.

## Parallel Execution Examples

- **Setup**: T001 e T002 são independentes.
- **US2**: T014 (composição) e T019 (estilo) tocam arquivos diferentes.
- **Polish**: T026 e T027 são auditorias independentes.

## Implementation Strategy

**O MVP é a US1.** Caixas sobre a imagem já provam que a geometria atravessa
o sistema inteiro corretamente, do sensor ao pixel desenhado.

**Dois portões.** T013 custa um olhar e **decide se o marco 4 existe**. T024
custa três sessões curtas e diz se o desenho cabe na folga de 5,19 ms que o
marco 2 deixou.

**Medir em Release.** O marco 2 mostrou Debug inflando laço apertado em ~35×, e
a composição de máscara é exatamente esse tipo de código. Medir em Debug levaria
a trocar para Metal sem necessidade.
