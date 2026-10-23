# Formato da coleta — versão 1

Este arquivo vai dentro de todo zip exportado pelo modo coleta do vizi, como
`FORMAT.md`. Ele basta para ler os dados sem o código do app.

Uma sessão é o intervalo entre ligar e desligar o modo. Ela tem **marcas** —
quadros do ao vivo gravados quando a pessoa tocou em "marcar" — e
**capturas** — fotos de 12 MP lidas pelo pipeline inteiro. Cada item traz as
imagens que o modelo leu, todas as detecções até uma confiança mínima, as
máscaras, e a contagem real que a pessoa digitou, quando digitou.

## Pastas

```
<id>/                          o instante de abertura: 2026-10-19T14-03-22
├── FORMAT.md                  este arquivo
├── session.json               a sessão
├── telemetry.jsonl            uma linha por amostra, ~2 Hz
└── items/
    ├── m0001/                 marca — o número é a ordem na sessão
    │   ├── item.json
    │   ├── square.jpg
    │   ├── frame.jpg
    │   ├── square.protos.f16
    │   └── truth.json         só quando a pessoa respondeu ou pulou
    └── c0002/                 captura
        ├── item.json
        ├── photo.jpg
        ├── photo-square.jpg
        ├── photo-square.protos.f16
        ├── crop.jpg           só quando houve recorte
        ├── reread-square.jpg  só quando houve releitura
        ├── reread-square.protos.f16
        └── truth.json
```

Uma pasta em `items/` está sempre completa: o app escreve em `.tmp-<id>/` e
troca o nome no fim. Se aparecer uma `.tmp-*`, ignore.

Todos os tempos são milissegundos. `at` é desde a época (UTC); `t` é desde o
início da sessão.

## Os espaços de coordenadas

| Espaço | O que é | Onde aparece |
|---|---|---|
| `square` | o quadrado 640×640 que o modelo leu, origem no topo esquerdo, em pixels | toda caixa de detecção |
| `photo` | a foto em retrato, em pixels | a geometria da captura |
| `crop` | o recorte endireitado, normalizado de 0 a 1 | `books`, `shelves` |
| eixo da faixa | de 0 a 1, no eixo em que a faixa anda (y na horizontal, x na vertical) | `band` |

**Do `square` para a imagem de origem** — `frame.jpg` na marca, `photo.jpg` na
captura —, com `W × H` o tamanho da origem e `transform` o modo do item:

| `transform` | x na origem | y na origem |
|---|---|---|
| `stretch` (padrão) | `x · W / 640` | `y · H / 640` |
| `centerCrop` | `x · s / 640 + (W − s) / 2` | `y · s / 640 + (H − s) / 2` — com `s = min(W, H)` |
| `letterbox` | `(x − (640 − W·k) / 2) / k` | `(y − (640 − H·k) / 2) / k` — com `k = min(640/W, 640/H)` |

`frame.jpg` e `photo.jpg` já estão em retrato nos próprios pixels, sem EXIF de
orientação: a imagem de origem que entrou mais larga que alta foi girada 90° no
sentido horário, a mesma regra que o app aplica antes de montar o quadrado.

**Do quadrado da releitura para o recorte:** o recorte foi encaixado no
quadrado, centrado, com preto em volta. `reread.content` é o retângulo que ele
ocupa, `[x, y, largura, altura]` no `square`. Um ponto `(x, y)` do quadrado cai
no recorte normalizado em `((x − cx) / cw, (y − cy) / ch)`.

## Detecção

```json
{ "anchor": 6123, "score": 0.412, "box": [312.5, 140.2, 18.1, 301.7],
  "coef": [0.12, -1.03, "… 32 números"],
  "exists": true, "inBand": true, "shown": true, "counted": true }
```

| Campo | Significado |
|---|---|
| `anchor` | a âncora que originou a detecção, única na inferência — a chave das junções |
| `score` | confiança, de 0 a 1 |
| `box` | `[x, y, largura, altura]` no `square` |
| `coef` | os 32 coeficientes da máscara |
| `exists` | `score ≥ thresholds.confidence` — o app a enxergou |
| `inBand` | marca e foto: a fração da caixa dentro da faixa, no eixo dela, ≥ `band.membership`; `true` com a faixa desligada |
| `shown` | marca: `exists ∧ inBand ∧ score ≥ thresholds.appearance` — estava desenhada |
| `inCore` | releitura: a fração da área da caixa dentro de `reread.core` ≥ `reread.membership` |
| `counted` | entrou na contagem que a tela mostrou para aquela leitura |

As listas vêm em ordem de confiança decrescente e incluem tudo de
`thresholds.recorded` para cima. **Filtrada por `exists`, a lista é exatamente
a do app**: o NMS é guloso por confiança, e as detecções fracas não mudam
nenhuma decisão sobre as fortes.

## Máscaras

`*.protos.f16` são os protótipos da inferência: `float16` little-endian, forma
`[32, 160, 160]`, sem cabeçalho. A máscara de uma detecção, em 160×160 — um
quarto do `square`:

```python
P = np.fromfile("square.protos.f16", dtype="<f2").astype(np.float32).reshape(32, 160, 160)
logit = np.tensordot(np.array(det["coef"], np.float32), P, axes=1)   # (160, 160)
x, y, w, h = (v / 4 for v in det["box"])
mask = np.zeros_like(logit, bool)
r0, r1 = int(np.floor(y)), int(np.ceil(y + h))
c0, c1 = int(np.floor(x)), int(np.ceil(x + w))
mask[r0:r1, c0:c1] = logit[r0:r1, c0:c1] > 0                         # sigmoide > 0,5
```

É a mesma regra com que o app desenha: fora da caixa, nada; dentro, logit
positivo.

## `session.json`

```json
{
  "format": 1,
  "id": "2026-10-19T14-03-22",
  "name": "sala, luz da noite",
  "startedAt": 1792418602000, "endedAt": 1792419310000,
  "endReason": "stopped",
  "app": { "version": "1.0.0", "build": "42" },
  "device": { "model": "iPhone15,5", "os": "26.5" },
  "model": {
    "identifier": "vizi-seg", "inputWidth": 640, "inputHeight": 640,
    "weightsSha256": "…", "weightsSource": "mlpackage",
    "metadata": { "date": "…", "version": "…", "names": "{0: 'book'}" }
  },
  "policies": { "session": {}, "capture": {}, "band": {}, "overlay": {}, "collection": {} },
  "purpose": "exam", "light": null,
  "shelves": [ { "id": "s-mf2k1x-4f", "name": "sala 1", "count": 22 } ],
  "counts": { "marks": 12, "captures": 10, "answered": 19, "skipped": 2 },
  "bytes": 183100000,
  "export": { "at": 1792419400000, "bytes": 183400000 }
}
```

| Campo | Significado |
|---|---|
| `endReason` | `stopped` — desligado; `background` — o app foi para segundo plano; `recovered` — o app foi encerrado à força e a sessão foi fechada na abertura seguinte |
| `model.weightsSha256` | o que separa uma sessão de um modelo da de outro, depois de um retreino. Com `weightsSource: "mlpackage"`, é o SHA-256 de `Data/com.apple.CoreML/weights/weight.bin` do `.mlpackage` — o mesmo que `sha256sum` dá no arquivo do repositório |
| `bytes` | o tamanho da pasta da sessão ao fechar |
| `policies` | como o app as enviou ao abrir a sessão; cada item grava também o que ele mesmo usou |
| `purpose` | `training` — fotos para o treino; `exam` — a prova, que nunca entra no treino. Ausente nas sessões gravadas antes da spec 008 |
| `light` | `day` ou `night` no treino, escolhida ao ligar; `null` na prova |
| `shelves` | as prateleiras cadastradas no aparelho ao abrir a sessão, com o número de livros do inventário naquele momento. É contra esta lista que a prova diz quais ficaram sem captura |

## `item.json` — o que toda marca e captura têm

```json
{
  "format": 1, "id": "m0001", "kind": "mark", "seq": 1,
  "t": 41250, "at": 1792418643250,
  "transform": "stretch",
  "thresholds": { "confidence": 0.25, "iou": 0.7, "appearance": 0.3, "recorded": 0.05 },
  "band": { "mode": "horizontal", "center": 0.5, "thickness": 0.33, "membership": 0.5 },
  "gravity": { "x": 0.01, "y": 0.99, "z": -0.05 },
  "images": { "square": { "file": "square.jpg", "width": 640, "height": 640 } },
  "tags": {
    "shelf": { "id": "s-mf2k1x-4f", "name": "sala 1", "count": 22 },
    "background": false, "distance": "near", "angle": "front"
  },
  "recordMs": 38.2
}
```

`gravity` é `null` sem leitura. `recordMs` é quanto a gravação do item custou,
em segundo plano.

**`tags`** é o que a pessoa tinha escolhido na câmera no instante do toque,
gravado como o app enviou. Ausente nas sessões anteriores à spec 008.

| Campo | Significado |
|---|---|
| `shelf` | a prateleira — o identificador, o nome e o número do inventário naquele momento —, ou `null` |
| `background` | `true` numa foto sem livros: sem prateleira, sem distância e sem ângulo |
| `distance` | `near` — só um pedaço da prateleira, livros grandes; `mid` — a prateleira inteira dentro da faixa; `far` — a prateleira inteira pequena, com as vizinhas. `null` na prova e nas fotos sem livros |
| `angle` | `left`, `front` ou `right`; `null` como `distance` |

A luz e o tipo são da sessão (`light`, `purpose`).

## Marca — `kind: "mark"`

| Campo | Significado |
|---|---|
| `images.square` | o quadrado que o modelo leu — o que estava na tela, embaixo das caixas |
| `images.frame` | o quadro da câmera, em retrato, sem esticar |
| `detections` | do quadro |
| `protos` | `"square.protos.f16"` |
| `displayedCount` | a contagem que a tela mostrava no toque — a mediana da faixa; `null` com a faixa desligada |
| `frameCount` | as detecções do quadro com `exists ∧ inBand` |
| `presentationTime` | o carimbo do quadro na câmera, em segundos do relógio do sistema |

## Captura — `kind: "capture"`

| Campo | Significado |
|---|---|
| `options` | o `CaptureOptions` que a captura recebeu |
| `images` | `photo`, `photoSquare`, `crop` e `rereadSquare`, cada uma quando existir |
| `photoRead.detections`, `photoRead.protos` | a leitura da foto |
| `geometry` | abaixo |
| `reread` | abaixo; `null` sem releitura |
| `result` | o que a tela recebeu: `count`, `countSource` (`reread` ou `photo`), `shelves`, `shelfCount`, `lyingCount`, `straightened`, `declineReason`, `geometryConfidence`, `azimuthConfidence`, `usedGravity`, `outsideBandCount` |
| `timings` | `elapsedMs` (a foto), `readyMs` (do toque ao resultado na tela), `rereadMs` |

**`geometry`**, toda no espaço `photo` quando é ponto ou reta:

| Campo | Significado |
|---|---|
| `fieldOfViewDegrees`, `focal` | da câmera e no espaço canônico |
| `horizon` | reta homogênea `[a, b, c]`, ou `null` |
| `verticalVP`, `horizontalVP` | pontos de fuga homogêneos `[x, y, w]`, ou `null` |
| `sourceQuad` | os quatro cantos do recorte na foto — os cantos superior esquerdo, superior direito, inferior direito e inferior esquerdo do `crop.jpg`, nessa ordem —, ou `[]`. Podem cair fora da foto: aí o recorte tem uma cunha sem imagem, abaixo |
| `books` | onde os livros ficam no recorte, `[x, y, largura, altura]` de 0 a 1 |
| `fullyRectified` | `true` com perspectiva corrigida; `false` no recuo de só rotação |
| `rows` | fileiras da foto, cada uma uma lista de `anchor` |
| `lying` | os `anchor` dos deitados |
| `azimuthScores` | a curva de azimute; só com o diagnóstico ligado |

**`reread`**:

| Campo | Significado |
|---|---|
| `content` | o retângulo do recorte no `square` |
| `core` | o recorte sem a margem, no `square` — onde a maior parte da caixa precisa estar |
| `membership` | a fração da regra das bordas |
| `detections`, `protos` | a leitura do quadrado da releitura |
| `rows`, `lying` | em `anchor`, como na geometria |

**A cunha fora da foto.** Quando um canto de `sourceQuad` cai fora da foto, o
recorte tem uma região sem imagem. A releitura a vê preta — o recorte é
composto sobre preto. Desde a spec 008, o `crop.jpg` a grava preta também e é,
em resolução cheia, a imagem que a releitura leu. **Antes, ela saía branca**:
para refazê-la, leve cada pixel do `crop.jpg` à foto pela homografia que manda
os cantos `(0, 0)`, `(W, 0)`, `(W, H)` e `(0, H)` do recorte nos cantos de
`sourceQuad`, e pinte de preto o que cair fora de `[0, largura] × [0, altura]`
da foto.

## `truth.json`

```json
{ "count": 23, "skipped": false, "prefill": 21, "answeredAt": 1792418650100 }
```

`count` é o número de livros que **aparecem na tela** — no quadro parado
(dentro da faixa, quando ligada) ou no resultado da captura. Com `skipped:
true`, `count` é `null`. **Sem `truth.json`**, a pessoa saiu sem responder ou o
app fechou antes. Nos dois últimos casos o item não tem gabarito.

## Refazer a contagem

| Leitura | Conta quem | Tem de dar |
|---|---|---|
| quadro da marca | `exists ∧ inBand` | `frameCount` |
| foto | `exists ∧ inBand` | `result.count`, quando `countSource` é `photo` |
| releitura | `exists ∧ inCore` | `result.count`, quando `countSource` é `reread` |

As regras estão escritas acima com os números do próprio item. Uma checagem
séria refaz `inBand` e `inCore` a partir de `box`, `band` e `reread.core`, em
vez de confiar nas marcas.

## `telemetry.jsonl`

Uma linha JSON por evento:

```json
{"type":"cameraStart","at":1792418610000,"captureWidth":1440,"captureHeight":1080,"maxFrameRate":60}
{"type":"sample","at":1792418610500,"fpsCaptured":60.0,"fpsInferred":59.8,"inferMs":3.1,"e2eMs":36.4,"thermalState":"nominal"}
{"type":"cameraStop","at":1792418700000}
```

As amostras têm os mesmos campos do evento de telemetria do app. A última linha
pode estar cortada se o app foi encerrado à força: ignore uma linha que não
seja JSON válido.

## Versões

`format` muda quando um campo muda de significado ou some. Campos novos podem
aparecer sem mudar a versão: quem lê ignora o que não conhece.

| Spec | O que mudou, ainda na versão 1 |
|---|---|
| 007 | o formato |
| 008 | `purpose`, `light` e `shelves` na sessão; `tags` no item; a cunha do `crop.jpg` preta, como a releitura a vê |
