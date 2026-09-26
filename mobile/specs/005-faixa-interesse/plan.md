# Implementation Plan: Faixa de interesse

**Branch**: `mobile/005-faixa-interesse` | **Date**: 2026-09-25 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/005-faixa-interesse/spec.md`

## Summary

Uma faixa que decide o que conta, manipulada com os dedos a 60 fps.

O filtro é a parte barata: uma regra de pertença — a maior parte da caixa
dentro da faixa — aplicada onde as detecções são consumidas. O trabalho está
na manipulação. Para a faixa seguir o dedo sem re-render de React (princípio
III), gesto, desenho, animação, contagem e retorno tátil vivem no nativo, como
a transição da 004. O React só fica sabendo da faixa quando o estado muda de
verdade, e desenha a cápsula de três estados.

## Technical Context

**Language/Version**: Swift 5.9+ no nativo; TypeScript 6 na política e no controle.

**Primary Dependencies**: UIKit (reconhecedores de gesto, retorno tátil,
acessibilidade) e Core Animation. **Nenhuma dependência nova** — Reanimated e
Gesture Handler foram considerados e descartados (R18).

**Storage**: nenhum. A faixa vive na sessão e recomeça no centro (FR-002).

**Testing**: verificação no aparelho, em Release. Fluidez pela telemetria
(SC-003); intuição por um teste com três pessoas (SC-005).

**Target Platform**: iOS, iPhone 14 Plus, iOS 26.5.

**Project Type**: app móvel — Expo com módulo nativo local.

**Performance Goals**: câmera e inferência a 60 fps durante a manipulação
(SC-003); a borda da faixa no quadro do dedo.

**Constraints**: nenhum `setState` por quadro durante o gesto (princípio III);
toda política em TS (princípio IV); o preview hoje mora dentro de uma
`ScrollView`, que disputaria o arrasto (R19).

**Scale/Scope**: ~550 linhas de Swift — três arquivos novos, seis tocados — e
~220 de TypeScript.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio | Aplicabilidade | Veredito |
|-----------|----------------|----------|
| **I. O desenho nunca espera a inferência** | A faixa é desenhada no relógio do display a partir do próprio estado. O filtro lê o último resultado publicado; nada espera inferência. | ✅ |
| **II. Dado grande não cruza a fronteira** | Atravessa o estado da faixa — modo, centro, espessura —, e só quando muda. | ✅ |
| **III. Zero re-render de React no caminho quente** | É o princípio que desenha este plano. Gesto, desenho, animação, contagem e háptico no nativo; o React troca de estado só em mudanças discretas: fim de gesto, troca de modo. | ✅ decide a arquitetura |
| **IV. Substrato nativo, política em JavaScript** | Comportamento da faixa em `SessionOptions.band`, aparência no `OverlayStyle`. O Swift executa a mecânica do gesto e nada decide sozinho. | ✅ |
| **V. Portão mensurável** | SC-001 a SC-006 são numéricos. | ✅ |

**Nenhuma violação.** Revisto depois da fase 1: o desenho continua sem violar
nada — ver o fim de [research.md](./research.md).

**Uma restrição técnica desatualizada, não uma violação.** A constituição fixa
`react-native-vision-camera`, Skia e Reanimated na stack. Nenhum dos três existe
no projeto desde o marco 2: a captura é AVFoundation própria, por causa do
princípio II, e o overlay é Core Animation. Este plano segue o caminho real, e
**recomenda emendar a seção "Stack fixa"** — fora do escopo desta spec.

## Project Structure

### Documentation (this feature)

```text
specs/005-faixa-interesse/
├── spec.md
├── plan.md              # este arquivo
├── research.md          # R18–R28
├── data-model.md
├── quickstart.md
├── contracts/
│   └── band.md          # superfície do módulo e contrato de gestos
├── checklists/
│   └── requirements.md
└── tasks.md             # /speckit-tasks — ainda não existe
```

### Source Code

```text
mobile/modules/vizi-vision/ios/
├── Band.swift               # novo — estado, política, regra de pertença, retângulos
├── BandGesture.swift        # novo — um reconhecedor para um e dois dedos
├── BandRenderer.swift       # novo — escurecimento, bordas, alças, contagem,
│                            #        retorno tátil, acessibilidade
├── PreviewView.swift        # hospeda a faixa; esconde e desliga na captura
├── OverlayRenderer.swift    # filtra no desenho; redesenha quando a faixa muda
├── SessionCoordinator.swift # contagem da telemetria filtrada
├── ResultRenderer.swift     # avisa quando a volta termina
├── Diagnostics.swift        # desenha a faixa e os descartados
└── ViziVisionModule.swift   # SessionOptions.band, setBandMode, onBandChange,
                             # captura filtrada, outsideBandCount

mobile/src/
├── band/
│   ├── policy.ts            # novo — DEFAULT_BAND
│   └── useBand.ts           # novo — espelha o estado nativo
├── ui/
│   ├── BandControl.tsx      # novo — a cápsula de três estados
│   └── CameraScreen.tsx     # preview fora da ScrollView; cápsula; "nenhum livro na faixa"
├── overlay/style.ts         # aparência da faixa
└── camera/useSession.ts     # a política da faixa vai junto com a sessão
```

**Structure Decision**: a faixa é mais uma camada da `PreviewView`, como o
overlay e a transição — não uma view do React por cima. É a mesma decisão da
004, pelo mesmo motivo: o que se move no ritmo do dedo precisa estar no mesmo
lugar que o pixel. Três arquivos novos em vez de um porque estado, gesto e
desenho mudam por motivos diferentes: a regra de pertença é usada por quem
nunca vê um toque (telemetria, captura), e o gesto não sabe desenhar.

## Quatro decisões técnicas que o plano fixa

**Um reconhecedor, não três.** Um `UIGestureRecognizer` próprio acompanha um ou
dois toques numa máquina de estados, e um reconhecedor de dois toques volta ao
centro. Reconhecedores separados de arrasto e pinça trocariam de dono no
instante em que o segundo dedo pousa — e esse instante é o gesto principal
desta spec (R18).

**Filtrar onde se consome, não onde se publica.** O `ResultStore` continua com
todas as detecções. O overlay filtra no desenho, no thread principal, com o
estado da faixa que o gesto acabou de escrever no mesmo thread: a caixa troca
no quadro em que a borda passa por ela. Telemetria, foco da aproximação e
captura aplicam a mesma função. As descartadas continuam à mão para o
diagnóstico (R21).

**O preview sai da `ScrollView`.** Fixo no topo, com os cartões rolando
abaixo. O FR-018 passa a valer por construção, em vez de por disputa entre
reconhecedores (R19).

**A faixa é um retângulo que se anima.** O escurecimento é um único caminho
par-ímpar — a moldura menos a faixa. Virar, ligar, desligar, voltar ao centro e
soltar no limite são todos a mesma coisa: uma mola levando um retângulo a
outro. Desligar é a faixa se abrindo até a moldura, e é por isso que "a faixa do
tamanho da imagem é a imagem toda" funciona como gesto (R20).

## Complexity Tracking

> Sem violações da constituição. Nada a justificar.
