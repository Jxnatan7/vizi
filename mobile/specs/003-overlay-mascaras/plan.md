# Implementation Plan: Overlay de caixas e máscaras

**Branch**: `mobile/003-overlay-mascaras` | **Date**: 2026-09-16 | **Spec**: [spec.md](./spec.md)

## Summary

Desenhar sobre o preview o que a inferência já produz: caixas e silhuetas.
Nativo em Swift, sem Skia e sem Reanimated.

O marco 2 entregou 60 fps com **5,19 ms de folga** por frame. Este marco gasta
parte dessa folga em desenho, e o portão é justamente não gastar demais.

## Technical Context

**Language/Version**: Swift 5.9+; TypeScript 5.x apenas para o estilo.

**Primary Dependencies**: Core Animation, Accelerate e Core Graphics — todos do
sistema. **Nenhuma dependência nova**, como no marco 2.

**Storage**: N/A.

**Testing**: verificação visual no aparelho e comparação de telemetria com e sem
overlay.

**Target Platform**: iOS, iPhone 14 Plus, iOS 26.5.

**Performance Goals**: 60 fps mantidos; e2e não cresce mais de 15% sobre os
39,6 ms do marco 2; custo do desenho reportado à parte.

**Constraints**: o desenho não pode entrar no caminho crítico da inferência.

**Scale/Scope**: ~400 linhas de Swift, ~100 de TypeScript.

## Constitution Check

| Princípio | Aplicabilidade | Veredito |
|-----------|----------------|----------|
| **I. O desenho nunca espera a inferência** | **Primeiro marco em que existe desenho.** O princípio deixa de ser precaução e passa a ser testável. | ✅ por desenho: o overlay lê o último resultado publicado, nunca aguarda um novo |
| **II. Dado grande não cruza a fronteira** | Protótipos `[1,32,160,160]` e pixels de máscara ficam no nativo. | ✅ reforçado |
| **III. Zero re-render de React no caminho quente** | O overlay é uma camada nativa. React não participa do desenho. | ✅ trivialmente |
| **IV. Substrato nativo, política em JS** | ⚠️ **Tensão real.** Desenhar em Swift põe aparência em código nativo. | ⚠️ mitigado — ver abaixo |
| **V. Portão mensurável** | SC-001, SC-002 e SC-006 são numéricos. | ✅ |

**Sobre o princípio IV.** A decisão de desenhar nativo contraria a letra do
princípio: cor, espessura e opacidade são ajustes finos, e ajuste fino pertence
ao TypeScript. A mitigação é o **FR-010**: o estilo é um objeto enviado do TS e
aplicado no nativo, que não tem opinião sobre ele. O nativo executa o desenho;
o TypeScript decide como.

Isso é exceção pontual e registrada, como o princípio IV permite: se o ajuste
de aparência em Swift incomodar, a rota é Skia — e o custo dessa troca fica
conhecido de antemão.

**Nenhuma violação não justificada.**

## Project Structure

```text
mobile/modules/vizi-vision/ios/
├── MaskCompose.swift      # coeficientes × protótipos → bitmap 160×160 RGBA
├── OverlayRenderer.swift  # camadas de máscara e de caixas
├── PreviewView.swift      # (existe) ganha as camadas do overlay
├── Decode.swift           # (existe) passa a extrair os 32 coeficientes
└── SessionCoordinator.swift # (existe) publica o resultado e cronometra o desenho

mobile/src/
├── overlay/style.ts       # espessura, opacidade, paleta — o FR-010
└── ui/CameraScreen.tsx    # (existe) controles de ligar/desligar
```

**Structure Decision**: três camadas do Core Animation empilhadas na
`PreviewView`, em vez de reescrever o preview em Metal:

```
CAShapeLayer          caixas          caminho reconstruído por frame
CALayer               máscaras        CGImage 160×160, ampliado pelo compositor
AVSampleBufferDisplayLayer  câmera    (já existe)
```

**Por que não Metal.** A composição da máscara na resolução dos protótipos
produz um bitmap de **102 KB** — 16× menor que a resolução do preview. A 60 Hz
são ~6 MB/s de envio, que o Core Animation absorve sem esforço, e a ampliação
de 160 para 640 é feita pelo compositor de graça.

O Ultralytics compõe nessa mesma resolução e amplia depois, então **não há perda
de qualidade em relação à referência**. Metal continua sendo a rota se a
medição mostrar custo alto — e o custo aparece na telemetria por construção
(FR-006).

## Complexity Tracking

| Violação | Por que é necessária | Alternativa rejeitada porque |
|---|---|---|
| Estilo do overlay definido em Swift (princípio IV) | Desenhar nativo evita duas dependências pesadas e mantém o desenho sincronizado com o frame que o gerou | Skia + Reanimated traria o estilo para TS, ao custo de dois módulos nativos novos e da travessia das instâncias a 60 Hz. Mitigado pelo FR-010: o estilo é dado, não código |
