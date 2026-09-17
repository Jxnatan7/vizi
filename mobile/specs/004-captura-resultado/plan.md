# Implementation Plan: Captura e resultado endireitado

**Branch**: `mobile/004-captura-resultado` | **Date**: 2026-09-17 | **Spec**: [spec.md](./spec.md)

## Summary

Transformar o instrumento em produto: um botão que captura, conta, endireita e
apresenta — com a transição sendo parte do resultado, não enfeite.

O marco 3 deixou **8,45 ms de folga** por frame e um pipeline que não perde
quadros. Este marco gasta pouco do orçamento contínuo e muito de um instante: a
captura é um evento, não um laço.

## Technical Context

**Language/Version**: Swift 5.9+ no nativo; TypeScript 5.x na aplicação e no
histórico.

**Primary Dependencies**: AVFoundation, Core Animation, Core Image, Accelerate
e `expo-file-system` (já presente). **Nenhuma dependência nova.**

**Storage**: histórico local — imagens em arquivo, índice em JSON.

**Testing**: verificação visual e medição de latência do toque ao resultado.

**Target Platform**: iOS, iPhone 14 Plus, iOS 26.5.

**Performance Goals**: toque → resultado < 1,5 s; transição a 60 fps; retomada
da câmera < 500 ms.

**Scale/Scope**: ~700 linhas de Swift, ~400 de TypeScript. É o maior marco até
aqui.

## Constitution Check

| Princípio | Aplicabilidade | Veredito |
|-----------|----------------|----------|
| **I. O desenho nunca espera a inferência** | A transição começa antes de a foto existir (FR-009) — é o princípio aplicado a um evento em vez de a um laço. | ✅ |
| **II. Dado grande não cruza a fronteira** | A foto em alta resolução é o maior dado que o app já manipulou. Fica inteira no nativo; o JS recebe contagem e um identificador. | ✅ reforçado |
| **III. Zero re-render de React no caminho quente** | A transição é animação nativa. React troca de estado **uma vez**, no toque. | ✅ |
| **IV. Substrato nativo, política em JS** | Limiares de confiança, margem do recorte e duração da animação vivem em TS. | ✅ |
| **V. Portão mensurável** | SC-001 a SC-005 são numéricos. | ✅ |

**Nenhuma violação.** Complexity Tracking vazio.

## Project Structure

```text
mobile/modules/vizi-vision/ios/
├── PhotoCapture.swift      # troca de formato, foto, restauração
├── ShelfGeometry.swift     # máscaras → quadrilátero → homografia
├── ResultRenderer.swift    # estado de resultado da PreviewView, animação
├── PreviewView.swift       # (existe) passa a ter dois estados
└── ViziVisionModule.swift  # (existe) ganha capture/dismiss

mobile/src/
├── capture/useCapture.ts   # estados: ao vivo, capturando, resultado
├── history/store.ts        # índice JSON + arquivos
└── ui/
    ├── CameraScreen.tsx    # (existe) botão e cromo do resultado
    └── HistoryScreen.tsx   # lista de capturas
```

**Structure Decision**: **uma view nativa com dois estados**, não duas telas.

A `PreviewView` já possui a imagem ao vivo e o overlay. Em vez de empurrar um
resultado para outra tela e animar entre elas, ela ganha um estado de resultado
e **transforma-se**. A animação deixa de ser transição entre telas e vira o
próprio comportamento da view.

React troca de estado uma única vez, no toque, e renderiza o cromo — contagem,
botões, aviso de não-endireitado. O pixel é todo nativo.

## Três decisões técnicas que o plano fixa

**A homografia é animada com `CATransform3D`, não redesenhada.**
Uma correção de perspectiva é projetiva, e o Core Animation não anima matrizes
3×3. Mas um plano no espaço 3D *é* uma projeção: a homografia se decompõe numa
`CATransform3D` com o termo de perspectiva, e aí o Core Animation interpola e a
GPU faz o mapeamento. Redesenhar o warp por frame em Core Image custaria muito
mais, sobretudo na resolução da foto.

**A geometria sai das máscaras, por PCA.**
Para cada silhueta, o eixo principal dá a inclinação da lombada. Os extremos
superior e inferior de cada máscara dão duas nuvens de pontos; uma reta ajustada
a cada nuvem dá as bordas superior e inferior da estante. Com as verticais dos
livros das pontas, fecha-se o quadrilátero.

**A confiança é medida, não presumida.**
Resíduo do ajuste das duas retas, número de objetos, e sanidade do quadrilátero
resultante — convexo, sem cruzamento, proporção plausível. Abaixo do limiar, o
resultado sai sem endireitar e avisa (FR-011).

## Complexity Tracking

> Sem violações da constituição. Nada a justificar.
