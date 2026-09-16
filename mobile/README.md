# vizi mobile

App React Native + Expo de detecção e segmentação em tempo real, on-device.

## Estado

| marco | | |
|---|---|---|
| **1 · Prova de vida do Core ML** | ✅ concluído | 36 de 36 |
| **2 · Câmera ao vivo e telemetria** | 🟡 implementado, medido parcialmente | 30 de 32 |
| 3 · Caixas na tela | — | |
| 4 · Os três relógios | — | |
| 5 · Máscaras em shader | — | |
| 6 · Acabamento e adaptação | — | |
| 7 · Android | — | |

### Marco 1 — a inferência cabe, com folga de uma ordem de grandeza

Existia para responder se a premissa da arquitetura se sustenta. Sustenta.

| | portão | medido no iPhone 14 Plus |
|---|---|---|
| inferência · mediana | < 30 ms | **3,1 ms** |
| inferência · p95 | < 40 ms | **4,9 ms** |
| correção | 24 instâncias | **24 de 24, 0 classes divergentes** |

O protótipo em [`../web`](../web) fazia o mesmo trabalho em **279 ms** no mesmo
aparelho, no caminho wasm/CPU do Safari. São **90×**.

Também entregou a cadeia de entrega do Linux ao iPhone, sem Mac e sem conta
Apple paga — GitHub Actions compila sem assinatura, AltServer-Linux assina com
Apple ID gratuito, instalação por USB.

### Marco 2 — o app processa o mundo a 60 fps

Câmera ao vivo, inferência a cada frame, telemetria. Nada é desenhado sobre a
imagem ainda — isso é o marco 3.

Sessão de 3,6 min, `stretch`, build Debug
([medição](specs/002-camera-telemetry/medicoes/2026-09-16-stretch-debug.json)):

| | |
|---|---|
| frames | **13091 de 13092** processados |
| taxa | **60 fps sustentados** |
| térmico | `nominal` → `nominal`, nenhuma transição |
| ponta-a-ponta | **39,6 ms** (limite 80) |
| trabalho por frame | 11,48 ms de um orçamento de 16,67 |

Degradação entre o começo e o fim: inferência −0,9%, fps 0,0%.

**Por que "medido parcialmente":** a sessão foi em **Debug**, com Swift em
`-Onone` — a decodificação custou ~35× o que custa em Release. E a bateria não
se moveu em 3,6 min, então o SC-007 segue sem resposta. Repetir em Release e por
mais tempo antes de declarar fechado.

### O que a medição mudou na arquitetura

A premissa era inferência em ≤ 25 ms, e o desenho dos
[três relógios](specs/001-coreml-proof/) existia para tornar convincente o
intervalo entre detecções. **A 3,1 ms cabem cinco inferências num frame de
60 Hz** — o intervalo praticamente sumiu.

O gargalo deixou de ser o modelo. Passa a ser composição de máscara e render,
e **nada disso tem número ainda**.

### Limitações conhecidas

- **`dropped` e `queueDepth` não medem nada.** O delegate da câmera é serial na
  mesma fila da inferência, então o `FrameGate` nunca vê "ocupado". O sinal real
  de descarte é `fpsCaptured` caindo abaixo de 60.
- **A carga do modelo custa ~720 ms**, o que aparece como abertura lenta.
- **`executionUnit` reporta o que foi pedido**, não o que rodou. Perdeu urgência:
  3,1 ms só é possível no acelerador dedicado.
- **Reassinatura após 7 dias** ainda não verificada.

## Desenvolvimento dirigido por spec

O projeto usa [GitHub Spec Kit](https://github.com/github/spec-kit). Nada é
implementado sem passar pelo ciclo.

```
/speckit-specify    o quê e por quê          → specs/mobile-NNN-slug/spec.md
/speckit-clarify    de-riscar ambiguidade    (obrigatório no caminho quente)
/speckit-plan       como                     → plan.md
/speckit-tasks      passos acionáveis        → tasks.md
/speckit-implement  executa
```

Complementares: `/speckit-analyze` (consistência entre artefatos),
`/speckit-checklist` (completude de requisitos), `/speckit-converge` (avalia o
código e acrescenta o que falta).

### Rodando os comandos

As skills vivem em `mobile/.claude/skills/`. Abra o Claude Code **dentro de
`mobile/`**:

```bash
cd mobile && claude
```

Para rodar da raiz do monorepo sem `cd`, exporte o override que o Spec Kit
oferece para exatamente este caso:

```bash
export SPECIFY_INIT_DIR=mobile
```

Os scripts resolvem a raiz do projeto pelo `.specify/` mais próximo, então
`specs/` fica em `mobile/specs/` — nunca na raiz do git.

## A constituição

[`.specify/memory/constitution.md`](.specify/memory/constitution.md) é a fonte
da verdade. Três princípios são **não-negociáveis** e uma violação é motivo de
rejeição, não de discussão:

1. **O desenho nunca espera a inferência** — três relógios independentes.
2. **Dado grande não cruza a fronteira** — nada acima de 64 KB por frame vai
   para o JS.
3. **Zero re-render de React no caminho quente** — o que se move a 60 Hz vive
   em `SharedValue` ou no nativo.

## Marcos

| # | Marco | Portão de saída |
|---|-------|-----------------|
| 1 | Prova de vida do Core ML | inferência < 30 ms no iPhone 14 Plus |
| 2 | Telemetria e câmera ao vivo | `queueDepth` ≤ 1 por 10 min contínuos |
| 3 | Caixas, sem suavização | desenho a 60 fps medido |
| 4 | Os três relógios | overlay fluido com inferência limitada a 10 Hz |
| 5 | Máscaras em shader | composição ≤ 1 ms, sem regressão de e2e |
| 6 | Acabamento e adaptação | 20 min de uso sem degradação perceptível |
| 7 | Android | paridade funcional |

Uma spec por marco. Os marcos 1 e 2 podem matar o projeto e custam poucos dias
— nada de valor é construído antes de eles passarem.

## Git

Branch por feature, nomeada `mobile/{número}-{slug}` — o prefixo existe porque
o repositório é compartilhado com `web/`. Criada pela extensão git do Spec Kit
(`/speckit-git-feature`). Auto-commit está desligado.

## Estrutura planejada

```
app/                    telas (Expo Router)
src/vision/             pipeline, tracker, render, controle adaptativo
modules/vizi-vision/    Expo Module nativo — Core ML (iOS) / LiteRT (Android)
models/                 .mlpackage + manifest
tools/                  export e avaliação do modelo (Python)
```

`ios/` e `android/` **não são versionados**: com Continuous Native Generation
eles são gerados por `expo prebuild` a partir dos config plugins em
`app.config.js`. Sem Mac, editar um projeto Xcode à mão não é uma opção.
