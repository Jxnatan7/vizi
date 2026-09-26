# vizi mobile

App React Native + Expo de detecção e segmentação em tempo real, on-device.

## Estado

| spec | | |
|---|---|---|
| **001 · Prova de vida do Core ML** | ✅ concluído | 36 de 36 |
| **002 · Câmera ao vivo e telemetria** | ✅ concluído | 32 de 32 |
| **003 · Caixas e máscaras** | ✅ portão atingido | 26 de 29 |
| **004 · Captura e resultado** | 🟡 código completo, falta o aparelho | 37 de 38 |
| Acabamento e adaptação | — | |
| Android | — | |

A sequência se afastou da tabela de marcos da constituição, e cada desvio foi
registrado na spec que o fez. As máscaras (antigo marco 5) entraram na 003. Os
três relógios (antigo marco 4) foram descartados em 16/09: a 60 fps não sobra
intervalo entre detecções para disfarçar. A 004 é o primeiro marco de produto,
e não estava na tabela.

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

Essa primeira sessão foi em **Debug**, e a bateria não se moveu em 3,6 min. O
marco fechou em 17/09 com uma sessão de 5,6 min em **Release**, já com 22
capturas no meio: 19321 de 19321 frames, 60 fps do começo ao fim, térmico
`nominal`. E a bateria, enfim medida: **~53 pontos por hora**. É o primeiro
argumento concreto para limitar a cadência.

### Marco 3 — caixas e máscaras, sem perder um quadro

Sessão de 31 s, Release, caixas e máscaras ligadas
([medição](specs/003-overlay-mascaras/medicoes/)):

| | |
|---|---|
| frames | **1842 de 1842** |
| taxa | **60 fps** |
| ponta-a-ponta | **36,43 ms** — abaixo da linha de base do marco 2 |
| desenho | 2,02 ms, no `CADisplayLink`, fora do orçamento do frame |

As máscaras são compostas com Accelerate na resolução dos protótipos (160×160),
e o compositor amplia. A rota Metal ficou disponível e não precisou ser paga.

### Marco 4 — apontar, apertar, contar

O primeiro marco que faz algo por alguém. Um toque tira uma foto de 12 MP,
conta os livros, endireita a estante e mostra a faixa de lombadas reta, com as
divisões, numa transição contínua a partir do que estava na tela.

- **A retificação é do plano, não dos objetos.** A gravidade dá a vertical; a
  reta das bases dos livros, cruzada com o horizonte, dá a horizontal.
- **Recusar é um desfecho válido.** Quando a geometria não merece confiança, o
  resultado sai sem endireitar e diz por quê.
- **A foto não degrada a sessão:** a câmera volta a 60 fps depois de cada uma
  das 22 capturas medidas.
- **O histórico guarda a faixa** em JPEG na pasta de documentos, exposta no app
  Arquivos para levar ao Colab.

**Falta o aparelho.** A revisão de fechamento (25/09) corrigiu sete desvios
entre código e spec e acrescentou o histórico — tudo escrito e ainda sem
build. A T034 (SC-007) valida o histórico e, junto, o resto.

### O que a medição mudou na arquitetura

A premissa era inferência em ≤ 25 ms, e o desenho dos
[três relógios](specs/001-coreml-proof/) existia para tornar convincente o
intervalo entre detecções. **A 3,1 ms cabem cinco inferências num frame de
60 Hz** — o intervalo praticamente sumiu.

O gargalo deixou de ser o modelo. Passou a ser composição de máscara e render,
e o marco 3 mediu os dois: **2,02 ms**, fora do orçamento do frame.

### Limitações conhecidas

- **`dropped` e `queueDepth` não medem nada.** O delegate da câmera é serial na
  mesma fila da inferência, então o `FrameGate` nunca vê "ocupado". O sinal real
  de descarte é `fpsCaptured` caindo abaixo de 60.
- **A carga do modelo custa ~720 ms**, o que aparece como abertura lenta.
- **`executionUnit` reporta o que foi pedido**, não o que rodou. Perdeu urgência:
  3,1 ms só é possível no acelerador dedicado.
- **Reassinatura após 7 dias** ainda não verificada.
- **Com o resultado na tela, a inferência ao vivo continua rodando.** O que
  pausa é a publicação, não o modelo: bateria gasta enquanto a pessoa olha a
  faixa.
- **A confiança da geometria não tem calibração registrada.** Os limiares
  foram validados olhando recusas, e até 25/09 o número na tela era outro
  (ver [research da 004](specs/004-captura-resultado/research.md)).

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

## Estrutura

```
App.tsx                 abas: câmera, histórico, medição
src/ui/                 telas
src/camera/             sessão de câmera e sua política
src/capture/            captura e sua política — inclusive a da geometria
src/history/            índice do histórico
src/overlay/            aparência do overlay
src/telemetry/          exportação e portão da sessão
src/bench/              medição controlada do marco 1
modules/vizi-vision/    Expo Module nativo — câmera, Core ML, overlay,
                        captura, retificação, transição
models/                 .mlpackage + shapes verificados
plugins/                config plugins
```

Limiares, estilo e tempos vêm de `src/`; o Swift executa (princípio IV).

`ios/` e `android/` **não são versionados**: com Continuous Native Generation
eles são gerados por `expo prebuild` a partir dos config plugins em
`app.config.js`. Sem Mac, editar um projeto Xcode à mão não é uma opção.
