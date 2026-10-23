# Implementation Plan: Coleta para treino e prova

**Branch**: `mobile/008-coleta-treino` | **Date**: 2026-10-22 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/008-coleta-treino/spec.md`

## Summary

A sessão de coleta passa a saber o que é — treino de dia, treino de noite ou
prova —, cada item passa a saber de que prateleira e de que variação é, e uma
ferramenta no Linux transforma uma sessão de treino numa pasta que o Roboflow
importa com os contornos prontos.

Quase tudo é TypeScript e Python. O nativo ganha pouco: gravar sem interpretar
o que a sessão é e a escolha do toque (R47), e gravar o recorte com a cunha
preta, como a releitura o vê (R50). O modo rápido não precisa de nativo novo:
são durações zero que o `ResultRenderer` já trata (R48).

A decisão central é de **fidelidade**: o que vai para o treino tem de ser a
imagem que o modelo lê no app. As medições de 20/10 mostraram que o recorte
gravado não era — a cunha saía branca, e a releitura a vê preta — e que, com a
cunha refeita, recorte e foto reproduzem o que o modelo leu, com correlação de
0,98 ou mais (R50, R51). A ferramenta confere isso em cada imagem que gera.

## Technical Context

**Language/Version**: Swift 5.9+ no nativo; TypeScript 6 na política e na
tela; Python 3.10+ na ferramenta.

**Primary Dependencies**: no app, nenhuma nova — `expo-file-system`, já usado
pelo histórico, guarda as prateleiras. Na ferramenta, `numpy`, `Pillow` e
`opencv-python-headless`, declarados no próprio arquivo (PEP 723) e
instalados pelo `uv` na primeira execução.

**Storage**: `Documents/shelves.json` para prateleiras e guia
([data-model](./data-model.md)); o zip da 007 com campos novos
([formato](./contracts/zip-format.md)); a pasta do pacote, fora do app.

**Testing**: no aparelho, em Release, pelo [quickstart](./quickstart.md). A
ferramenta se confere sozinha (SC-003) e roda nas sessões de 20/10 antes de
haver sessão nova: a de capturas com `--sem-tipo`, e as duas recusadas sem ele.

**Target Platform**: iOS, iPhone 14 Plus, iOS 26.5; a ferramenta, no Linux do
autor.

**Project Type**: app móvel — Expo com módulo nativo local — e uma ferramenta
de linha de comando.

**Performance Goals**: no treino, a câmera de volta ao vivo em menos de 1,5 s
do toque, e a 60 fps depois de cada captura (SC-001). Fora do treino, nada muda
(SC-007). A ferramenta não tem meta: 0,1 a 0,6 s por imagem na medição de R52.

**Constraints**: nenhum pixel atravessa (princípio II); vocabulário, metas e o
modo rápido em TS (princípio IV); a contagem do app não muda (FR-023); a
ferramenta nunca empacota uma prova (FR-020).

**Scale/Scope**: ~80 linhas de Swift em quatro arquivos; ~600 de TypeScript —
três componentes novos, um armazenamento, a tela da câmera e a Medição —; a
ferramenta, ~400 linhas de Python.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio | Aplicabilidade | Veredito |
|-----------|----------------|----------|
| **I. O desenho nunca espera a inferência** | O modo rápido zera durações de transição e chama a volta que já existe; nada passa a esperar a gravação nem a inferência. | ✅ |
| **II. Dado grande não cruza a fronteira** | Atravessam `tags` e `session` — texto e números, centenas de bytes por captura. As imagens do pacote saem do zip, no Linux. | ✅ |
| **III. Zero re-render de React no caminho quente** | Escolha, guia e nota do indicador mudam por toque ou por captura. Nada por quadro. | ✅ |
| **IV. Substrato nativo, política em JavaScript** | Distâncias, ângulos, descrições, meta de fotos sem livros e `FAST_CAPTURE` em `src/collection/policy.ts`. O nativo grava `tags` e `session` sem validar. | ✅ |
| **V. Portão mensurável** | SC-001 a SC-007 são numéricos; o SC-003 é conferido em toda imagem pela ferramenta. | ✅ |

**Nenhuma violação.** Revisto depois da fase 1, no fim de
[research.md](./research.md).

**A restrição do modelo continua intacta.** O mesmo `.mlpackage`, os mesmos
limiares, a mesma contagem. A spec prepara o próximo treino; não troca o
modelo.

## Project Structure

### Documentation (this feature)

```text
specs/008-coleta-treino/
├── spec.md
├── plan.md              # este arquivo
├── research.md          # R47–R57
├── data-model.md        # prateleira, guia, shelves.json, escolha, estados
├── quickstart.md
├── contracts/
│   ├── collection.md    # o que muda na fronteira: tags, session, estado, lista
│   ├── zip-format.md    # o formato do zip — passa a ser o que vai em todo zip (R57)
│   └── ferramentas.md   # pacote e prova: entradas, saídas, recusas, nomes, COCO
├── checklists/
│   └── requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code

```text
mobile/modules/vizi-vision/ios/
├── ViziVisionModule.swift    # capture(options, tags) e markFrame(tags);
│                             # CollectionOptionsRecord.session; tags no rastro
├── CollectionTrace.swift     # Mark e Capture ganham `tags`; item.json as grava
├── CollectionRecorder.swift  # purpose, light e shelves no session.json, no
│                             # estado e na lista
└── CollectionWriter.swift    # o recorte composto sobre preto antes do JPEG

mobile/modules/vizi-vision/src/
├── ViziVision.types.ts       # CollectionTags, CollectionSessionInfo,
│                             # ShelfSnapshot; campos novos no estado e na lista
└── ViziVisionModule.ts       # as assinaturas novas

mobile/plugins/withViziAssets.js  # FORMAT.md passa a vir da 008 (R57)

mobile/src/
├── collection/
│   ├── policy.ts             # DISTANCES, ANGLES, LIGHTS, BACKGROUND_GOAL,
│   │                         # FAST_CAPTURE
│   ├── shelves.ts            # novo — shelves.json: ler, gravar em fila,
│   │                         # cadastrar, renomear, número, apagar, contar
│   ├── selection.ts          # novo — a escolha da câmera: o que vira `tags`
│   │                         # e o que falta para capturar (FR-003)
│   └── useCollection.ts      # start(session), tags na marca, estado com o tipo
├── capture/
│   └── useCapture.ts         # capture({ tags, fast }): o modo rápido
└── ui/
    ├── CameraScreen.tsx      # escolher o tipo ao ligar; o seletor; capturar
    │                         # só com escolha; treino sem resultado; a nota
    ├── CollectionStart.tsx   # novo — treino de dia, de noite, prova
    ├── CollectionTagsBar.tsx # novo — prateleiras, "sem livros" e o guia 3×3
    ├── ShelfList.tsx         # novo — a Medição: cadastro e o guia por prateleira
    ├── TruthPrompt.tsx       # o número do app separado do preenchido
    ├── CollectionIndicator.tsx # o tipo da sessão e a nota da última captura
    ├── CollectionList.tsx    # o tipo e a luz de cada sessão
    └── BenchScreen.tsx       # a lista de prateleiras, acima das sessões

mobile/tools/
└── coleta.py                 # novo — `pacote` e `prova`
```

**Structure Decision**: a prateleira é do app, não da sessão, e por isso vive no
JavaScript, ao lado do histórico, e não no gravador nativo, que só registra o
que recebe. A ferramenta fica em `mobile/tools/`, e não na pasta da spec como o
verificador da 007: ela é usada a cada rodada de treino (R56).

## Quatro decisões técnicas que o plano fixa

**A escolha viaja com o toque.** `capture` e `markFrame` recebem `tags` como
argumento, e o item grava o que chegou. Não há uma prateleira guardada no
nativo para ficar velha depois de um recarregamento do JavaScript (R47).

**O modo rápido é política.** Aproximação e transição em zero, sem
diagnóstico, e a volta assim que o resultado chega. A captura roda inteira e é
gravada igual; só a tela do resultado é pulada (R48).

**O treino vê o que o app dá ao modelo.** O recorte vai encaixado num quadrado
de 2048 com preto em volta, que o Roboflow reduz a 640 sem distorcer; a foto
vai como está, e o Roboflow a estica como o app. A cunha fora da foto sai preta
— no app daqui em diante, e refeita pela geometria nas sessões antigas. Cada
imagem é conferida contra o quadrado que o modelo leu (R50, R51).

**Os contornos são o que o app achou, sem duplicata.** Toda detecção da imagem
acima do limiar, com a máscara ampliada antes do limiar e simplificada a
poucos vértices, descartando a que está 80% dentro de uma mais forte. A pessoa
corrige em vez de desenhar (R52).

## Complexity Tracking

> Sem violações da constituição. Nada a justificar.
