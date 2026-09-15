# Implementation Plan: Prova de vida do Core ML

**Branch**: `mobile/001-coreml-proof` | **Date**: 2026-09-15 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-coreml-proof/spec.md`

## Summary

Entregar duas coisas que se validam juntas: uma cadeia de entrega que leva
código de uma máquina Linux até um app rodando num iPhone físico, e um veredito
medido sobre se o modelo de segmentação cabe no orçamento de latência que a
arquitetura assume.

O app é deliberadamente mínimo: uma tela, um botão, nenhuma câmera. Todo o risco
do marco está fora da interface — está em conseguir assinar e instalar sem Mac,
e em descobrir se o Neural Engine executa o grafo de segmentação.

## Technical Context

**Language/Version**: TypeScript 5.x na camada de aplicação; Swift 5.9+ no
módulo nativo. Python roda apenas no Colab, fora deste repositório.

**Primary Dependencies**: Expo SDK com `expo-dev-client`, `expo-modules-core`
para o módulo nativo, e Core ML do próprio sistema. **Sem** câmera, Skia ou
Reanimated neste marco — entram nos marcos 2 e 3.

**Storage**: N/A. O modelo e a imagem de referência são recursos embarcados no
pacote do app. Nada é persistido entre execuções.

**Testing**: sem suíte automatizada neste marco. O CI valida que o app compila;
a correção é verificada no aparelho comparando a saída com o resultado esperado
versionado. Não há como exercitar o Neural Engine num runner de CI, então teste
de desempenho automatizado é impossível por construção.

**Target Platform**: iOS, iPhone 14 Plus (A15) com a versão mais recente do
sistema. Android está fora do escopo.

**Project Type**: aplicativo móvel com módulo nativo local.

**Performance Goals**: mediana da execução do modelo < 30 ms, p95 < 40 ms, sobre
100 repetições com o aparelho em temperatura normal.

**Constraints**: sem Mac e sem ferramenta de profiling do fabricante; assinatura
com conta Apple gratuita, válida por 7 dias; o app funciona sem rede.

**Scale/Scope**: uma tela, um módulo nativo, um modelo, uma imagem de
referência. Cerca de 400 linhas de TypeScript e 300 de Swift.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio | Aplicabilidade neste marco | Veredito |
|-----------|----------------------------|----------|
| **I. O desenho nunca espera a inferência** | Não há loop de desenho ainda. Mas a medição **não pode** bloquear a thread de interface, para não estabelecer o precedente que o marco 4 teria de desfazer. | ✅ por desenho: a execução roda fora da thread de interface e reporta por callback |
| **II. Dado grande não cruza a fronteira** | Aplica integralmente. A imagem de referência e os tensores de saída ficam no lado nativo; para o JavaScript vai apenas o resumo — latências e instâncias já decodificadas. | ✅ por desenho, ver `contracts/` |
| **III. Zero re-render de React no caminho quente** | Não há caminho quente a 60 Hz. O resultado chega uma vez ao fim da sequência, e um `useState` aqui é legítimo. | ✅ não aplicável |
| **IV. Substrato nativo, política em JS** | Aplica. Número de repetições, quantidade de execuções de aquecimento e limiar de confiança vivem em TypeScript. O Swift recebe esses valores como parâmetro. | ✅ por desenho |
| **V. Portão de saída mensurável** | SC-001 e SC-002 são numéricos e verificados no aparelho. | ✅ |

**Nenhuma violação.** A seção Complexity Tracking fica vazia.

## Project Structure

### Documentation (this feature)

```text
specs/001-coreml-proof/
├── plan.md              # Este arquivo
├── research.md          # Fase 0 — as cinco incógnitas
├── data-model.md        # Fase 1 — entidades
├── quickstart.md        # Fase 1 — o procedimento repetível
├── contracts/
│   └── vizi-vision.md   # Fase 1 — contrato do módulo nativo
└── tasks.md             # Fase 2 — criado por /speckit-tasks
```

### Source Code (repository root)

```text
mobile/
├── app.config.js                   # config plugins — fonte da verdade do nativo
├── App.tsx                         # uma tela; Expo Router entra no marco 3
├── assets/
│   ├── reference.jpg               # imagem fixa do conjunto de validação
│   └── reference-expected.json     # saída esperada, gerada no Colab
├── models/
│   └── vizi-seg.mlpackage/         # versionado — o CI compila a partir do repo
├── src/
│   ├── bench/
│   │   ├── runBenchmark.ts         # política: repetições, aquecimento, agregação
│   │   └── stats.ts                # mediana, p95, mínimo
│   └── ui/
│       └── BenchScreen.tsx         # botão, resultados, erro legível
├── modules/vizi-vision/
│   ├── expo-module.config.json
│   ├── src/index.ts                # API tipada — a fronteira
│   └── ios/
│       ├── ViziVisionModule.swift  # superfície exposta ao JS
│       ├── InferenceEngine.swift   # carga, aquecimento, execução, cronometragem
│       └── Decode.swift            # saída crua → instâncias
└── .github/workflows/ios.yml       # prebuild → pods → xcodebuild sem assinatura
```

**Structure Decision**: estrutura de aplicativo móvel com módulo nativo local,
conforme a arquitetura. Três desvios conscientes em relação ao alvo final, todos
por serem prematuros neste marco:

- **Sem Expo Router.** Uma tela não justifica navegação. Entra no marco 3,
  quando houver a segunda tela.
- **`src/vision/` ainda não existe.** Não há pipeline, tracker nem render. O que
  existe é `src/bench/`, que morre no marco 2 quando a telemetria de verdade
  nascer.
- **`tools/` fora do repositório.** O export roda no Colab, onde vivem o dataset
  e os pesos. O repositório recebe o artefato exportado, e o procedimento de
  export é documentado em `quickstart.md`.

O `.gitignore` foi corrigido neste marco: `models/*.mlpackage/` estava sendo
ignorado, o que teria quebrado o build no CI — o modelo precisa entrar no bundle
e o runner compila a partir do repositório.

## Complexity Tracking

> Sem violações da constituição. Nada a justificar.
