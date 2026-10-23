# Contrato — as ferramentas fora do app

`mobile/tools/coleta.py`, com as dependências no próprio arquivo (R56):

```bash
uv run mobile/tools/coleta.py pacote <zip ou pasta>… --saida <pasta> [opções]
uv run mobile/tools/coleta.py prova  <zip ou pasta>…
```

Cada entrada é um zip exportado pelo app ou a pasta dele já extraída. Uma pasta
que contém outra pasta de sessão (`vizi-coleta-…/2026-…/`) também vale.

## `pacote`

| Opção | Padrão | O quê |
|---|---|---|
| `--saida` | obrigatória | pasta a criar; recusa se já existir e não estiver vazia |
| `--sem-tipo` | desligada | aceita sessões anteriores à 008, como treino |
| `--lado` | 2048 | lado, em pixels, da imagem do recorte |
| `--confianca` | o limiar gravado no item | confiança mínima de um contorno |
| `--duplicata` | 0,8 | fração da máscara dentro de uma mais forte que a descarta |
| `--previa` | desligada | pasta para cópias reduzidas com os contornos desenhados, para conferir antes de subir; fora da pasta do pacote |
| `--so-imagens` | desligada | só as imagens, sem contorno nem `_annotations.coco.json`: quem marca é a IA do Roboflow (R59). A conferência continua |
| `--sem-sam` | desligada | contornos da máscara do app, sem redesenhar pelo SAM: rápido, grosseiro no topo dos livros (R58) |

**Recusa** — sai com 2, sem gerar nada — quando alguma entrada é de prova,
ou sem tipo sem `--sem-tipo` (FR-020), ou quando `--saida` existe e não está
vazia. Sem nenhuma imagem a gerar — só marcas, ou tudo recusado na
conferência —, sai com 1 e não deixa pasta.

**O que vai** (FR-016, FR-017, R53), por captura de treino:

| Captura | Recorte | Foto inteira |
|---|---|---|
| com livros e recorte | sempre | quando a célula está na diagonal da luz |
| com livros, sem recorte | — | sempre |
| sem livros | — | sempre, sem contorno |

Marcas nunca vão.

**A pasta:**

```
<saida>/
├── _annotations.coco.json
├── 2026-10-23T19-02-11_c0001_sala-1_perto-frente-noite_recorte.jpg
├── 2026-10-23T19-02-11_c0001_sala-1_perto-frente-noite_foto.jpg
├── 2026-10-23T19-02-11_c0017_sem-livros_noite_foto.jpg
└── …
```

O nome: `<sessão>_<item>_<prateleira>_<distância>-<ângulo>-<luz>_<recorte|foto>.jpg`,
com a prateleira em minúsculas, sem acento, espaços em hífen. Sem livros:
`<sessão>_<item>_sem-livros_<luz>_foto.jpg`. Sessão sem tipo:
`<sessão>_<item>_<recorte|foto>.jpg`.

**`_annotations.coco.json`** — COCO de segmentação:

```json
{
  "info": { "description": "vizi — pacote da coleta", "date_created": "2026-10-23T21:40:00" },
  "categories": [ { "id": 1, "name": "book", "supercategory": "none" } ],
  "images": [
    { "id": 1, "file_name": "…_recorte.jpg", "width": 2048, "height": 2048 }
  ],
  "annotations": [
    { "id": 1, "image_id": 1, "category_id": 1,
      "segmentation": [[x1, y1, x2, y2, "…"]],
      "bbox": [x, y, largura, altura], "area": 1234.5, "iscrowd": 0 }
  ]
}
```

Coordenadas em pixels da imagem do pacote. Uma imagem sem livros está em
`images` e em nenhuma anotação.

**A conferência** (SC-003), em toda imagem, antes de gravar:

- recorte: o retângulo do conteúdo é `reread.content` × `lado / 640`, e a
  imagem reduzida a 640 tem correlação ≥ 0,97 com o `reread-square.jpg`;
- foto: esticada a 640, correlação ≥ 0,97 com o `photo-square.jpg`.

Uma imagem que falha não entra, e o motivo sai no resumo.

**O contorno** sai da máscara do app — que decide quais livros entram e
descarta as duplicatas — e é redesenhado pelo SAM 2.1 com a caixa de cada um
(R58). Os pesos ficam em `~/.cache/vizi/sam2.1_b.pt`, baixados na primeira
vez. Cada imagem imprime uma linha ao terminar: são de 6 a 12 s na CPU.

**O resumo** (FR-021), ao terminar: por prateleira, quantas imagens de recorte,
de foto e sem livros, quantos contornos e quantos descartados como duplicata;
e as imagens recusadas, com o motivo.

## `prova`

Recusa o que não for prova (R55). Imprime:

```
prova 2026-10-24T10-12-40 · modelo 3bcc958e8b77 · 26 capturas

prateleira            item    app  gabarito  inventário
sala 1                c0001    22        22          22   ✓
sala 1                c0002    23        22          22   ✗ +1
quarto, branca, cima  c0003    16        16          16   ✓
…

exatas: 19 de 26 (73%)
por prateleira: sala 1 1/2 · quarto, branca, cima 2/2 · …
sem captura: escritório 2
```

O gabarito é o `truth.json`; capturas puladas ou sem resposta aparecem como
"sem gabarito" e não entram na conta. `inventário` é o número gravado em
`tags.shelf.count`; quando difere do gabarito, a linha diz.

Sai com 0 sempre que leu: o relatório informa, não julga. O gate — exata em
todas, em duas provas novas seguidas — é lido por quem roda.
