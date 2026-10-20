# Implementation Plan: Modo coleta

**Branch**: `mobile/007-modo-coleta` | **Date**: 2026-10-19 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/007-modo-coleta/spec.md`

## Summary

Um gravador nativo que, com o modo ligado, guarda cada marca do ao vivo e cada
captura — imagens, detecções, máscaras, geometria, tempos e a contagem real —
numa pasta por sessão, e exporta a pasta como zip pelo menu de compartilhar.

O app já calcula tudo o que precisa ser guardado. O plano cuida de três coisas:
**não mudar nada do que ele calcula** (a gravação decodifica de novo, em
segundo plano, o tensor que a inferência já devolveu — R38); **não custar um
quadro** (fila própria, JPEG pela CPU, nada antes do resultado aparecer —
R40); e **não mentir** (imagem e detecções do mesmo quadro por construção, item
inteiro ou nada, um formato descrito dentro do próprio zip — R37, R41, R44).

## Technical Context

**Language/Version**: Swift 5.9+ no nativo; TypeScript 6 na política e na tela.

**Primary Dependencies**: Core ML, Core Video, Accelerate (vImage), ImageIO,
VideoToolbox, CryptoKit e Foundation (`NSFileCoordinator`), todos do sistema.
**Nenhuma dependência nova.**

**Storage**: arquivos em `Documents/collection/`, uma pasta por sessão,
exposta no app Arquivos como o histórico. O formato está em
[contracts/zip-format.md](./contracts/zip-format.md). O histórico não muda.

**Testing**: verificação no aparelho, em Release, pelo
[quickstart](./quickstart.md), e um script de checagem que lê o zip real e
recalcula cada contagem (SC-002, SC-003).

**Target Platform**: iOS, iPhone 14 Plus, iOS 26.5.

**Project Type**: app móvel — Expo com módulo nativo local.

**Performance Goals**: 60 fps com o modo ligado fora dos instantes de captura,
e de volta a 60 fps depois de cada captura e marca (SC-001); o resultado em
menos de 1,5 s do toque, como sem o modo (SC-004).

**Constraints**: nenhum pixel atravessa (princípio II); limiar mínimo, limite
de espaço e qualidade em TS (princípio IV); o display nunca espera a coleta
(princípio I); a contagem, as caixas e o histórico iguais com o modo ligado ou
desligado (FR-003).

**Scale/Scope**: ~650 linhas de Swift — quatro arquivos novos, sete tocados —,
~300 de TypeScript e um script de checagem de ~120 linhas.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio | Aplicabilidade | Veredito |
|-----------|----------------|----------|
| **I. O desenho nunca espera a inferência** | A gravação roda numa fila utilitária própria. Marcar é um sinal que o laço da câmera atende no quadro seguinte; o congelamento usa o `showStill` e a publicação que a captura já usa. O display não consulta a coleta. | ✅ |
| **II. Dado grande não cruza a fronteira** | Imagens, protótipos e o tensor cru ficam no nativo, do buffer ao disco. Atravessam identificadores, contagens, bytes, resumos das sessões e, uma vez por sessão, as políticas em vigor. | ✅ |
| **III. Zero re-render de React no caminho quente** | O evento da coleta é discreto — item gravado, resposta, abrir, fechar. O tempo da sessão é redesenhado a 1 Hz, num componente pequeno: é cromo, não caminho quente. | ✅ |
| **IV. Substrato nativo, política em JavaScript** | `minScore`, `minFreeBytes` e `jpegQuality` em `src/collection/policy.ts`. No Swift fica só definição de formato. | ✅ |
| **V. Portão mensurável** | SC-001 a SC-006 são numéricos. | ✅ |

**Nenhuma violação.** Revisto depois da fase 1, no fim de
[research.md](./research.md).

**A restrição do modelo continua intacta.** O mesmo `.mlpackage`, a mesma
entrada, os mesmos limiares. A coleta só lê.

**A stack declarada na constituição** cita `react-native-vision-camera`, Skia e
Reanimated, que o projeto substituiu por câmera e overlay nativos desde a 002.
Nada aqui muda isso.

## Project Structure

### Documentation (this feature)

```text
specs/007-modo-coleta/
├── spec.md
├── plan.md              # este arquivo
├── research.md          # R36–R46
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── collection.md    # a fronteira: funções, evento, tipos e o que muda na captura
│   └── zip-format.md    # o formato do zip — é este arquivo que vai dentro dele
├── tools/
│   └── check-zip.py     # recalcula cada contagem a partir do zip (SC-002, SC-003)
├── checklists/
│   └── requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code

```text
mobile/modules/vizi-vision/ios/
├── CollectionRecorder.swift  # novo — a sessão: pastas, fila, abrir e fechar,
│                             #        segundo plano, recuperação, espaço,
│                             #        o item à espera de resposta, o evento
├── CollectionTrace.swift     # novo — o que uma marca e uma captura guardam,
│                             #        a decodificação a 0,05 e o JSON deles
├── CollectionWriter.swift    # novo — JPEG pela CPU, foto em retrato,
│                             #        protótipos em fp16, escrita atômica
├── CollectionExport.swift    # novo — zip do sistema e menu de compartilhar
├── InferenceEngine.swift     # RunResult carrega o tensor cru; SHA-256 dos pesos
├── SessionCoordinator.swift  # marca: o próximo quadro processado; telemetria
│                             # para a sessão
├── OverlayRenderer.swift     # ResultStore: publicar sobre a pausa sem virar
│                             # "da captura"
├── BandRenderer.swift        # a mediana mostrada, legível de fora
├── PreviewView.swift         # a contagem mostrada, lida no toque; trava do
│                             # gesto da faixa
├── Reread.swift              # Outcome ganha o quadrado, o núcleo e as
│                             # detecções antes da regra das bordas
└── ViziVisionModule.swift    # funções e evento da coleta; o rastro da
                              # captura; resumeLive

mobile/modules/vizi-vision/
├── ios/ViziVision.podspec    # FORMAT.md no bundle de recursos
└── src/
    ├── ViziVision.types.ts   # Collection*, campos novos em CaptureResult
    └── ViziVisionModule.ts   # funções e evento

mobile/plugins/withViziAssets.js  # copia contracts/zip-format.md para Resources/FORMAT.md

mobile/src/
├── collection/
│   ├── policy.ts             # novo — DEFAULT_COLLECTION
│   └── useCollection.ts      # novo — espelho do estado e as ações
└── ui/
    ├── CameraScreen.tsx      # ligar, indicador, marcar, estado 'marked'
    ├── TruthPrompt.tsx       # novo — a contagem real: +/−, confirmar, pular
    ├── CollectionList.tsx    # novo — as sessões: nome, exportar, apagar
    └── BenchScreen.tsx       # a lista, na Medição
```

**Structure Decision**: a coleta é um substrato novo ao lado do histórico, e
não dentro dele: o histórico guarda o que a pessoa escolhe, a coleta guarda
tudo, e os dois não se misturam (decisão do autor). Ela não calcula nada
próprio — lê do laço do ao vivo e do fim do `capture`, que já têm todos os
valores à mão —, por isso o resto do nativo só ganha pontos de leitura.

## Cinco decisões técnicas que o plano fixa

**A marca é o próximo quadro processado.** O toque liga um sinal; o laço da
câmera fotografa do quadro seguinte a imagem, o quadrado, o resultado e a
faixa, e a tela congela nesse quadro com as caixas dele. Imagem e detecções do
mesmo instante por construção, e custo zero quando ninguém marca (R37).

**A gravação decodifica de novo, e a contagem não muda.** O app decodifica com
o limiar da sessão, como sempre. A coleta decodifica o mesmo tensor a 0,05, em
segundo plano. Como o NMS é guloso por confiança, filtrar a lista de 0,05 pelo
limiar da sessão devolve exatamente as detecções do app — é o que torna o
SC-002 verificável. A junção é pela âncora (R38).

**Nada da gravação acontece antes do resultado aparecer.** O trabalho da
captura vai para a fila no fim do `capture`, depois da releitura. JPEG pela CPU,
para não disputar a GPU com a transição; a foto girada em retrato nos próprios
pixels (R40).

**Item inteiro ou nada.** Pasta temporária e troca de nome. Uma sessão que o
app não fechou é fechada na abertura seguinte, sem item pela metade (R41).

**O formato vai dentro do zip.** O contrato `zip-format.md` é copiado pelo
config plugin para o bundle e, ao exportar, para a pasta da sessão. Um zip lido
daqui a seis meses diz sozinho o que cada campo significa (R44, FR-017).

## Complexity Tracking

> Sem violações da constituição. Nada a justificar.
