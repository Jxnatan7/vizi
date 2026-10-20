# Fase 1 — Modelo de dados

Os campos de cada arquivo estão no [formato do zip](./contracts/zip-format.md).
Aqui ficam as entidades, as regras que as amarram e os estados por que passam.

## Sessão de coleta

O intervalo entre ligar e desligar o modo. Uma pasta em
`Documents/collection/<id>/`, onde `<id>` é o instante de abertura
(`2026-10-19T14-03-22`).

| Atributo | Descrição |
|---|---|
| id | o instante de abertura; também ordena as pastas |
| nome | opcional, dado na lista depois de fechada |
| início, fim | milissegundos desde a época; o fim ausente enquanto aberta |
| motivo do fim | `stopped`, `background` ou `recovered` (R41, R42) |
| app, aparelho, modelo | versão e build; identificador e sistema; metadados e SHA-256 dos pesos (R45) |
| políticas | as que o JS enviou ao abrir, como chegaram |
| contadores | marcas, capturas, respondidas, puladas, bytes |
| telemetria | as amostras de ~2 Hz e o início e o fim de cada sessão de câmera |
| último zip | caminho, bytes e quando foi exportado; ausente se nunca |

**Estados**

```
            ligar                   desligar ou segundo plano
 (nenhuma) ──────▶ aberta ──────────────────────────▶ fechando ──▶ fechada
                     │                                    │
                     │ app encerrado à força              │ sem itens
                     ▼                                    ▼
                 (órfã) ── próxima abertura do app ──▶ fechada    apagada
                            endReason: recovered
                            sem itens → apagada
```

- **Uma aberta por vez.** Ligar com uma aberta não abre outra.
- **Fechando** espera a fila terminar os itens que já entraram nela.
- **Só a fechada exporta, recebe nome e é apagada** (FR-015, FR-018).
- **Sem itens não sobrevive** ao fechamento nem à recuperação (FR-019).

---

## Item

Uma marca ou uma captura gravada. Uma pasta em `items/<id>/`: `m0001` para
marca, `c0002` para captura — o número é a ordem na sessão, comum aos dois.

**Estados**

```
 pedido ──▶ gravando ──▶ gravado ──┬──▶ respondido   truth.json { count }
           (.tmp-<id>)             ├──▶ pulado       truth.json { count: null, skipped }
               │                   └──▶ sem resposta (sem truth.json)
               │ falha, sem espaço,
               ▼ app encerrado
           (some inteiro)
```

- **Gravando não existe para ninguém.** A lista, os contadores e o zip só veem
  `items/<id>/` (R41).
- **A resposta pode chegar antes de o item terminar** — a pessoa responde
  enquanto o JPEG de 12 MP ainda codifica. Ela entra na fila depois do item e
  chega ao disco depois dele (R43).
- **Só o item à espera aceita resposta**, e ele deixa de esperar ao voltar à
  câmera, ao retomar o ao vivo, com um item novo ou no fim da sessão (FR-011).

### Marca

| Atributo | Descrição |
|---|---|
| imagens | o quadrado que o modelo leu (640×640) e o quadro da câmera, sem esticar |
| detecções | do quadro, até `minScore`, com caixa, confiança, âncora, coeficientes e as marcas abaixo |
| protótipos | do quadro, fp16 `[32, 160, 160]` |
| faixa | modo, centro, espessura e a fração de pertencimento |
| gravidade | o vetor no quadro, ou ausente |
| contagem mostrada | a mediana da faixa no toque; ausente com a faixa desligada |
| contagem do quadro | as detecções que existem e estão na faixa |
| limiares, transformação | os da sessão naquele instante |

### Captura

| Atributo | Descrição |
|---|---|
| imagens | a foto em retrato, o quadrado da foto, o recorte endireitado e o quadrado da releitura — cada uma quando existir |
| leitura da foto | detecções até `minScore`, protótipos, e quais a faixa deixou entrar |
| geometria | endireitado, motivo da recusa, confiança, azimute, gravidade, focal, horizonte, pontos de fuga, o quadrilátero de origem do recorte, a extensão dos livros no recorte, fileiras e deitados em âncoras, a curva de azimute quando houver |
| releitura | detecções até `minScore`, protótipos, onde o recorte está no quadrado, o recorte sem a margem e a fração da regra das bordas |
| resultado | contagem, origem, fileiras com divisões, número de fileiras, deitados — o mesmo `CaptureResult` que a tela recebeu |
| tempos | `elapsedMs`, `readyMs`, `rereadMs` e quanto a gravação custou |
| opções | o `CaptureOptions` que a captura recebeu |

---

## Detecção gravada

| Atributo | Descrição |
|---|---|
| âncora | o índice da âncora que a originou — única na inferência, a chave das junções (R38) |
| confiança | 0 a 1 |
| caixa | `[x, y, largura, altura]` em pixels do quadrado que o modelo leu |
| coeficientes | os 32 da máscara |
| marcas | dizem o que o app fez com ela — tabela abaixo |

**As marcas**

| Marca | Vale em | Regra |
|---|---|---|
| `exists` | todas | `confiança ≥ confidenceThreshold` — o app a enxergou |
| `inBand` | marca, foto | a fração da caixa no eixo da faixa ≥ `membership` (005); `true` com a faixa desligada |
| `shown` | marca | `exists ∧ inBand ∧ confiança ≥ minConfidence` — estava desenhada na tela |
| `inCore` | releitura | a fração da área da caixa no recorte sem a margem ≥ `rereadMembership` (006) |
| `counted` | marca, foto, releitura | entrou na contagem que a tela mostrou para aquela leitura |

**A contagem se refaz assim** (SC-002):

| Leitura | `counted` | contagem |
|---|---|---|
| quadro da marca | `exists ∧ inBand` | a do quadro |
| foto | `exists ∧ inBand` | a do resultado, quando a origem é `photo` |
| releitura | `exists ∧ inCore` | a do resultado, quando a origem é `reread` |

As regras são gravadas com os números que usam — faixa, núcleo, frações —,
então a checagem não confia na marca `counted`: refaz a conta e compara.

**Por que a lista a 0,05 serve.** Filtrada por `exists`, ela é exatamente a
lista do app (R38). As detecções abaixo do limiar são o que distingue o livro
"quase visto" do "não visto" — o motivo da coleta.

---

## Contagem real

O número de livros que aparecem na tela, dado pela pessoa. É o gabarito do
item.

| Atributo | Descrição |
|---|---|
| contagem | inteiro ≥ 0, ou ausente quando pulou |
| pulou | `true` quando tocou em pular |
| preenchimento | o número que o pedido mostrou ao abrir |
| quando | milissegundos desde a época |

**O que conta como "aparece na tela"** (decisão do autor):

| Item | A pessoa conta |
|---|---|
| marca, faixa ligada | os livros dentro da faixa, no quadro parado |
| marca, faixa desligada | os livros do quadro inteiro |
| captura com recorte | os livros do recorte |
| captura sem recorte | os livros da faixa na foto exibida |
| captura com diagnóstico | os livros dentro do recorte desenhado |

Pular ou sair sem responder é "sem resposta" na spec. O arquivo distingue os
dois (R43).

---

## Política da coleta

Vive em `src/collection/policy.ts` (princípio IV).

| Campo | Valor inicial | Decide |
|---|---|---|
| `minScore` | 0,05 | até que confiança as detecções são gravadas |
| `minFreeBytes` | 1 GB | abaixo disto, marcar é recusado e a captura não é gravada |
| `jpegQuality` | 0,9 | a qualidade de todas as imagens da coleta |

A gravação decodifica com **o menor entre `minScore` e o limiar da sessão**.
Um `minScore` acima do limiar perderia detecções que o app contou, e o SC-002
cairia; com o menor dos dois, a lista gravada contém sempre a do app, e o item
registra o limiar que de fato usou.

---

## Zip da sessão

`Documents/collection/<id>.zip`. A pasta da sessão com o `FORMAT.md` dentro.
Substituído a cada exportação e apagado com a sessão. Nome sugerido ao
compartilhar: `vizi-coleta-<id>[-<nome>].zip`.
