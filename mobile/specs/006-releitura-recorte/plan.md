# Implementation Plan: Releitura do recorte

**Branch**: `mobile/006-releitura-recorte` | **Date**: 2026-09-27 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/006-releitura-recorte/spec.md`

## Summary

Uma segunda inferência, no fim da captura, sobre o recorte encaixado no
quadrado como a tela o mostra — e o que ela encontra passa a ser o resultado.

A parte que parece difícil já está pronta. O preview é quadrado, a entrada do
modelo também, e o recorte aparece centrado nele: um quadrado montado com o
mesmo encaixe é a entrada da releitura **e** o espaço em que o overlay já
desenha. Caixas e máscaras caem no lugar sem conversão nenhuma (R30, R31).

O trabalho está nas bordas do fluxo: não girar o recorte ao montar o quadrado,
não deixar a margem contar, não esconder caixa que conta, recalcular as
divisões no espaço do recorte, e não deixar nada do resultado vazar para o ao
vivo na volta.

## Technical Context

**Language/Version**: Swift 5.9+ no nativo; TypeScript 6 na política e na tela.

**Primary Dependencies**: Core ML, Core Image e Core Animation, já no projeto.
**Nenhuma dependência nova.**

**Storage**: o índice do histórico ganha um campo — de qual leitura veio a
contagem. Entradas antigas não o têm, e eram da foto.

**Testing**: verificação no aparelho, em Release, pelo
[quickstart](./quickstart.md). Contagem manual do autor (SC-001), contagem das
caixas na tela (SC-002, SC-003) e os tempos que o próprio resultado mostra
(SC-004).

**Target Platform**: iOS, iPhone 14 Plus, iOS 26.5.

**Project Type**: app móvel — Expo com módulo nativo local.

**Performance Goals**: a releitura cabe dentro da transição de 600 ms — as
caixas aparecem quando ela termina, sem espera a mais (SC-004).

**Constraints**: nenhum pixel atravessa (princípio II); limiares e frações em
TS (princípio IV); o desenho continua lendo o último resultado publicado, sem
esperar inferência (princípio I).

**Scale/Scope**: ~260 linhas de Swift — um arquivo novo, seis tocados — e ~50
de TypeScript.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio | Aplicabilidade | Veredito |
|-----------|----------------|----------|
| **I. O desenho nunca espera a inferência** | A releitura roda na thread da captura, depois de a imagem ir para a tela. O overlay continua lendo o que foi publicado; enquanto a releitura não termina, ele segue emprestado à transição e não desenha nada novo. | ✅ |
| **II. Dado grande não cruza a fronteira** | O quadrado, os protótipos e as máscaras da releitura nascem e morrem no nativo. Atravessam números: contagem, fileiras, divisões, a origem e um tempo. | ✅ |
| **III. Zero re-render de React no caminho quente** | Uma leitura por captura, fora de qualquer caminho de 60 Hz. O React recebe o resultado uma vez, como hoje. | ✅ |
| **IV. Substrato nativo, política em JavaScript** | `reread` e `rereadMembership` em `CaptureOptions`. A regra das bordas usa a margem que já vem do TS. O preto não é ajuste: é a definição da entrada — o fundo da `PreviewView`, o que a tela mostra em volta do recorte. | ✅ |
| **V. Portão mensurável** | SC-001 a SC-007 são numéricos. | ✅ |

**Nenhuma violação.** Revisto depois da fase 1, no fim de
[research.md](./research.md).

**A restrição do modelo continua intacta.** A releitura usa o mesmo
`.mlpackage`, com a mesma entrada 640×640. Nada muda no export.

**Uma revogação, registrada na spec:** o FR-004 da 004 ("uma inferência, sem
ladrilhamento") passa a ter duas inferências. A 004 foi anotada.

## Project Structure

### Documentation (this feature)

```text
specs/006-releitura-recorte/
├── spec.md
├── plan.md              # este arquivo
├── research.md          # R29–R35
├── data-model.md
├── quickstart.md
├── contracts/
│   └── reread.md        # o que muda em CaptureOptions, CaptureResult e HistoryEntry
├── checklists/
│   └── requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code

```text
mobile/modules/vizi-vision/ios/
├── Reread.swift             # novo — regra das bordas, fileiras e divisões no
│                            #        espaço do recorte, o resultado da leitura
├── FrameTransform.swift     # o quadrado da releitura: encaixe, centro, preto,
│                            # sem a normalização de orientação
├── SessionCoordinator.swift # squareFromCutout, ao lado do squareFromPhoto
├── OverlayRenderer.swift    # resultado desenhado como foi contado; estilo
│                            # redesenha; o store limpa sem deixar rastro
├── PlaneRectifier.swift     # onde os livros ficam no recorte, medido
├── ShelfGeometry.swift      # fileiras em índices de instância, não de lombada
└── ViziVisionModule.swift   # CaptureOptions.reread e rereadMembership; a
                             # releitura no fim da captura; a época do
                             # resultado; a volta limpa

mobile/modules/vizi-vision/src/
└── ViziVision.types.ts      # CountSource; campos novos nas opções, no
                             # resultado e na entrada do histórico

mobile/src/
├── capture/options.ts       # reread, rereadMembership
├── history/store.ts         # a origem da contagem vai para o índice
└── ui/CameraScreen.tsx      # de onde veio a contagem e quanto a releitura custou
```

**Structure Decision**: a releitura mora na captura, onde a foto já é lida, e
usa as mesmas peças: o `FrameTransform` monta o quadrado, o `InferenceEngine`
roda, a `ShelfGeometry` agrupa as fileiras e o overlay desenha. O único arquivo
novo guarda o que só a releitura precisa: a conta entre o quadrado e o recorte.

## Cinco decisões técnicas que o plano fixa

**A releitura roda depois de a imagem ir para a tela.** A transição começa, e a
releitura corre por baixo dela. O `readyMs` para no instante em que o resultado
aparece, como antes; o custo da releitura vai num campo próprio, `rereadMs`.
Enquanto a transição anima, o overlay está emprestado e não desenha, então as
caixas aparecem quando ela termina — desde que a releitura caiba em 600 ms
(R29).

**O quadrado não passa pelo `transform`.** Ele gira toda imagem mais larga que
alta, porque supõe o sensor deitado. Um recorte horizontal entraria com os
livros deitados. O quadrado tem caminho próprio no `FrameTransform`: mesmo pool,
mesmo contexto, o encaixe do `resizeAspect` e o preto em volta (R30).

**O resultado é desenhado exatamente como foi contado.** O que a captura publica
passa pelo overlay sem o filtro da faixa — que está nas coordenadas do frame ao
vivo, não do recorte — e sem o limiar de aparência, que esconderia caixas que
contam. Trocar o estilo redesenha na hora, porque no resultado não chegam frames
para redesenhar por ele (R31).

**Conta quem está dentro do recorte sem a margem.** O `PlaneRectifier` mede
onde os livros ficam no recorte — não dá para deduzir da margem, porque no
recuo de só rotação a borda da foto corta o recorte. Uma caixa conta quando a
maior parte da sua área está lá dentro (R32).

**As fileiras vêm da `ShelfGeometry`, sem gravidade.** Numa imagem reta, o eixo
médio das lombadas é a vertical, e é isso que ela usa quando não recebe
gravidade. A leitura do código achou um defeito no caminho: as fileiras
guardavam índices de lombada, não de instância, e trocavam de livro quando uma
máscara pequena demais ficava sem lombada. Corrigido junto (R33).

## Complexity Tracking

> Sem violações da constituição. Nada a justificar.
