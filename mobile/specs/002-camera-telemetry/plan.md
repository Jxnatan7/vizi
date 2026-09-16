# Implementation Plan: Câmera ao vivo e telemetria

**Branch**: `mobile/002-camera-telemetry` | **Date**: 2026-09-16 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-camera-telemetry/spec.md`

## Summary

Trocar a imagem fixa do marco 1 por frames reais da câmera, inferir a cada
frame, e construir a telemetria que torna o comportamento diagnosticável.

O marco 1 provou que a inferência custa 3,1 ms. **Este marco existe para
descobrir o que isso custa em calor e bateria quando repetido 60 vezes por
segundo por 10 minutos** — a pergunta que substituiu "cabe no tempo?".

Sem desenhar detecções. O preview mostra exatamente o que o modelo recebe.

## Technical Context

**Language/Version**: Swift 5.9+ no módulo nativo; TypeScript 5.x na aplicação.

**Primary Dependencies**: AVFoundation, CoreImage e Core ML — todos do sistema.
`expo-clipboard` para exportar o registro. **Nenhuma dependência nativa de
terceiros.**

**Storage**: N/A. A sessão vive em memória e sai por cópia para a área de
transferência.

**Testing**: sem suíte automatizada. A verificação é a sessão de 10 minutos no
aparelho, e a comparação visual das três transformações.

**Target Platform**: iOS, iPhone 14 Plus (A15), iOS 26.5.

**Project Type**: aplicativo móvel com módulo nativo local.

**Performance Goals**: térmico não ultrapassa `fair` em 10 minutos; latência
ponta-a-ponta mediana < 80 ms; taxa de quadros sem queda sustentada > 20%.

**Constraints**: sem Mac e sem profiling do fabricante; a telemetria construída
aqui é a única visibilidade que existirá.

**Scale/Scope**: uma tela, uma sessão de câmera, três transformações. Cerca de
600 linhas de Swift e 300 de TypeScript.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio | Aplicabilidade | Veredito |
|-----------|----------------|----------|
| **I. O desenho nunca espera a inferência** | Não há overlay ainda, mas o preview é um caminho de vídeo contínuo que **não pode** ser bloqueado pela inferência. A regra passa a valer de fato. | ✅ por desenho: preview e inferência consomem o mesmo frame em caminhos separados |
| **II. Dado grande não cruza a fronteira** | **O motivo da escolha de AVCaptureSession próprio.** Frames nascem e morrem em Swift; o JavaScript recebe contagem e telemetria. | ✅ reforçado |
| **III. Zero re-render de React no caminho quente** | Contagem e latência mudam a cada frame. Escrever isso em `useState` a 60 Hz seria violação direta. | ⚠️ exige atenção — ver decisão abaixo |
| **IV. Substrato nativo, política em JS** | Transformação escolhida, intervalo de amostragem e limiar vivem em TypeScript. | ✅ |
| **V. Portão mensurável** | SC-001 a SC-007, todos numéricos. | ✅ |

**Decisão sobre o princípio III.** A tela precisa mostrar números que mudam a
60 Hz. A solução é **não** atualizar a 60 Hz: o nativo agrega e emite um evento
a cada ~500 ms. A contagem exibida é uma amostra, não um espelho. Isso mantém o
React fora do caminho quente sem precisar de Reanimated neste marco.

**Nenhuma violação.** Complexity Tracking vazio.

## Project Structure

### Documentation (this feature)

```text
specs/002-camera-telemetry/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── camera-session.md
└── tasks.md          # criado por /speckit-tasks
```

### Source Code

```text
mobile/
├── modules/vizi-vision/ios/
│   ├── CameraSession.swift       # AVCaptureSession, delegate, formato
│   ├── FrameGate.swift           # fila de profundidade 1, descarte do mais antigo
│   ├── FrameTransform.swift      # esticar / recortar / letterbox → 640×640
│   ├── PreviewView.swift         # Expo Module View: mostra o buffer transformado
│   ├── Telemetry.swift           # buffer circular de amostras
│   ├── InferenceEngine.swift     # (existe) ganha runOnce sobre buffer externo
│   └── ViziVisionModule.swift    # (existe) ganha start/stop e o evento periódico
├── src/
│   ├── camera/
│   │   ├── useSession.ts         # assina o evento, mantém o estado da sessão
│   │   └── transforms.ts         # as três opções, tipadas
│   ├── telemetry/
│   │   └── exportSession.ts      # sessão → JSON → área de transferência
│   └── ui/
│       ├── CameraScreen.tsx      # preview + números + seletor de transformação
│       └── BenchScreen.tsx       # (existe) permanece, acessível
```

**Structure Decision**: o módulo nativo cresce e passa a ser dono da câmera.
Duas telas convivem — a do marco 1 continua útil como medição controlada sobre
entrada fixa, que é justamente o que a câmera não oferece.

## Complexity Tracking

> Sem violações da constituição. Nada a justificar.
