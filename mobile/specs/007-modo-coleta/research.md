# Fase 0 — Pesquisa

Onze incógnitas, nenhuma sobre o modelo. O app já calcula tudo o que a coleta
precisa; o trabalho é guardar sem mudar nada do que ele calcula, sem custar um
quadro, e de um jeito que alguém fora do aparelho consiga ler.

A R37 e a R38 são as que decidem se o zip mente. Uma imagem de um quadro com as
detecções de outro, ou uma lista de detecções que não reproduz a contagem da
tela, bastam para o gabarito valer menos que nada.

---

## R36 — Quem é dono da sessão

**Decisão.** Um gravador nativo, `CollectionRecorder`, criado pelo módulo e
vivo enquanto o app vive. Ele abre e fecha a sessão, recebe as marcas e as
capturas, escreve tudo numa **fila serial própria, de prioridade utilitária**, e
avisa o JavaScript por um evento, `onCollectionChange`, só em mudança discreta:
abriu, fechou, um item terminou de gravar, uma resposta chegou. O JavaScript
espelha o estado, como faz com a faixa (005).

A sessão é independente da sessão de câmera. Trocar de aba desliga a câmera
(`stopSession`), mas não a coleta (FR-013); quando a câmera volta, a mesma
sessão de coleta continua recebendo.

```
Documents/collection/
├── 2026-10-19T14-03-22/            uma sessão, nomeada pelo início
│   ├── session.json
│   ├── telemetry.jsonl
│   ├── FORMAT.md                   copiado ao exportar
│   └── items/
│       ├── m0001/                  marca
│       ├── c0002/                  captura
│       └── .tmp-c0003/             ainda gravando — não existe para ninguém
└── 2026-10-19T14-03-22.zip         o último zip exportado dessa sessão
```

A pasta de documentos já está exposta no app Arquivos e no `ifuse` (004), então
as sessões também chegam ao Linux sem passar pelo zip.

**Por quê.** As imagens nascem no nativo e não podem atravessar (princípio II).
Fechar a sessão no segundo plano e recuperá-la depois de o app ser encerrado à
força (R41, R42) precisa acontecer sem o JavaScript, que pode estar suspenso. E
o histórico mostrou o custo de um índice mantido em TypeScript: duas escritas
seguidas precisaram de fila para não se apagarem.

**Alternativas.** Índice em TypeScript, como o histórico: o JS teria de
coordenar com escritas nativas assíncronas, e a recuperação depois de um
encerramento forçado dependeria de o JS rodar primeiro. Uma pasta por camada
(imagens aqui, dados ali): ler um item exigiria juntar três lugares.

---

## R37 — O quadro da marca

**Decisão.** Marcar é um pedido que **o próximo quadro processado** atende.
O toque liga um sinal; o laço da câmera, ao terminar a inferência do quadro
seguinte, fotografa do próprio quadro: o buffer da câmera, o quadrado que foi
ao modelo, o resultado da inferência com o tensor cru (R38) e a faixa naquele
instante. A tela congela nesse quadro: o quadrado vai para o preview com
`showStill`, e as detecções dele são publicadas no overlay **em modo ao vivo**,
com a faixa e o limiar de aparência de sempre. É exatamente o que estava na
tela, com as caixas daquele mesmo quadro.

O atraso é de no máximo um quadro, uns 17 ms a 60 fps.

*Na implementação, 19/10:* a escrita que ignoraria a pausa no `ResultStore`
(T025) não foi preciso. O congelamento acontece na fila da câmera logo
**depois** de o quadro publicar as próprias detecções — e o preview recebeu o
quadrado dele antes da inferência. Congelar e pausar ali, na mesma fila,
deixa na tela exatamente o quadro marcado, já em modo ao vivo, sem escrever
nada por cima.

**A contagem que a tela mostrava** é a mediana da faixa (`BandRenderer`, 005),
lida na thread de interface no instante do toque. Com a faixa desligada, a
pílula não aparece: a contagem mostrada é registrada como ausente, e o pedido
vem preenchido com a do quadro.

**O gesto da faixa trava** enquanto o quadro está parado, e a cápsula some como
na captura: mexer na faixa mudaria o que aparece, e a tela deixaria de ser o
que foi gravado.

**Por quê.** É o único jeito de imagem e detecções serem do mesmo instante por
construção (FR-008, SC-005), e não custa nada quando ninguém marca. O
congelamento da captura não serve: o preview recebe o quadrado *antes* da
inferência, então no instante do congelamento a imagem pode estar um quadro à
frente das caixas — tolerável numa transição de 700 ms, não num gabarito.

**Alternativas.** Guardar o último quadro a cada quadro, com o modo ligado:
seguraria um buffer do pool da câmera o tempo todo e ainda teria o
descompasso entre imagem e caixas. Gravar o quadro do toque sem congelar: a
pessoa contaria olhando outra cena (decisão do autor: o quadro parado).

**Como fechar.** SC-005: dez marcas com o aparelho em movimento, as caixas
gravadas desenhadas sobre a imagem gravada caem sobre os livros.

---

## R38 — Uma decodificação a 0,05, e a contagem continua a mesma

**Decisão.** O app continua decodificando como hoje, com o limiar da sessão. A
coleta decodifica **de novo**, em segundo plano, o tensor cru de detecção que a
inferência já devolveu, com o limiar mínimo de gravação (0,05). Para isso, o
`RunResult` passa a carregar o tensor cru além das instâncias. Não há cópia: o
Core ML aloca saídas novas a cada predição (o projeto não usa
`outputBackings`), então segurar a referência é seguro.

**Por que a lista a 0,05 reproduz a do app.** O NMS do `Decode` é guloso por
confiança: percorre os candidatos do mais confiante para o menos, e um
candidato só é suprimido por um que já foi aceito — logo, mais confiante.
Candidatos abaixo de 0,25 entram depois de todos os que passam de 0,25 e não
mudam nenhuma decisão sobre eles. Filtrar a lista de 0,05 por `score ≥ 0,25`
devolve **exatamente** as detecções do app. É isso que torna o SC-002
verificável a partir do zip.

**A junção é pela âncora**, não pela posição na lista. O `sorted` do Swift não
garante ordem entre confianças iguais, e a lista de 0,05 tem mais candidatos.
Cada detecção carrega o índice da âncora que a originou (`anchorIndex`), único
por inferência; fileiras, deitados e a regra das bordas são gravados como
listas de âncoras.

**Custo.** A 0,05, o NMS recebe mais candidatos — quadrático, mas fora do
caminho do app, na fila da coleta. O quickstart anota o tempo.

**Alternativas.** Decodificar sempre a 0,05 e filtrar: o custo cairia em todo
quadro do ao vivo, com ou sem coleta. Gravar o tensor cru inteiro (1,2 MB por
inferência): reproduziria qualquer limiar, mas obrigaria a reimplementar a
decodificação fora do aparelho para ler qualquer coisa — e abaixo de 0,05 é
ruído.

---

## R39 — As máscaras

**Decisão.** Cada detecção gravada leva os seus 32 coeficientes, no JSON. Os
protótipos da inferência vão num arquivo binário: `float16` little-endian,
forma `[32, 160, 160]`, ~1,6 MB. A máscara de uma detecção se reconstrói como o
app a compõe (`MaskCompose`): o produto dos coeficientes pelos protótipos, em
160×160, recortado à caixa dividida por 4, e positivo onde o logit é maior que
zero — o mesmo que sigmoide acima de 0,5. A fórmula está no
[formato](./contracts/zip-format.md).

**Por quê.** É exato e não custa processamento no aparelho: o tensor vira fp16
com o Accelerate e vai para o disco. Qualquer outra representação decide algo
no aparelho — o limiar, o contorno — que depois não se desfaz.

**Alternativas.** Polígonos: exigiriam traçar contornos no aparelho, perdem
detalhe e são o que um script no Colab gera quando o Roboflow pedir (fora de
escopo, decisão do autor). Um PNG por detecção: dezenas de arquivos por item, e
o limiar embutido.

---

## R40 — As imagens

**Decisão.** JPEG pela **CPU**: `CGImage` do buffer pelo VideoToolbox, escrito
pelo ImageIO, com a qualidade da política (0,9, como o histórico). A foto sai
**em retrato nos próprios pixels**, girada com o vImage pela mesma regra do
pipeline — mais larga que alta, gira —, sem depender de orientação EXIF, que
nem todo leitor respeita.

| Item | Imagem | Tamanho típico |
|---|---|---|
| marca | `square.jpg` — o quadrado que o modelo leu | 640×640 |
| marca | `frame.jpg` — o quadro da câmera, sem esticar | o formato do ao vivo |
| captura | `photo.jpg` — a foto, em retrato | 3024×4032 |
| captura | `photo-square.jpg` — o quadrado que o modelo leu da foto | 640×640 |
| captura | `crop.jpg` — o recorte endireitado, resolução cheia | varia |
| captura | `reread-square.jpg` — o quadrado da releitura, como a tela | 640×640 |

**Quando.** O trabalho da captura vai para a fila da coleta no fim do
`capture`, depois da releitura e com o resultado já montado. O `readyMs` é
medido antes da releitura (006, R29), então a gravação não pode atrasá-lo por
construção (SC-004). Os quadrados são codificados primeiro: vêm do pool do
`FrameTransform`, de seis buffers, que o ao vivo também usa.

**Por que CPU.** A gravação começa enquanto a transição do resultado anima. Um
JPEG de 12 MP pelo `CIContext`, como o histórico faz, disputaria a GPU com a
animação; pela CPU, numa fila utilitária, disputa só núcleos que sobram — a
inferência está no acelerador dedicado.

**Memória.** A foto em BGRA tem 48 MB, e girada, outros 48 MB, por alguns
décimos de segundo. Duas capturas seguidas se sobrepõem na fila; o aparelho tem
6 GB.

*Na revisão da implementação, 19/10:* cada captura na fila segura a foto, o
recorte e os dois quadrados até ser escrita. Capturas em sequência rápida
empilham isso. O ritmo humano — foto, transição, pergunta — deve manter a fila
curta, mas é a primeira coisa a olhar se o app morrer por memória no meio de
uma sessão: o `recordMs` das capturas (T040) diz quanto cada uma fica na fila.

**Alternativas.** O caminho do histórico (`CIContext`, GPU): a disputa acima.
HEIC: metade do tamanho, mas o Colab e o Roboflow precisariam de conversão (a
spec assume JPEG). Orientação EXIF em vez de girar: o Roboflow orienta, mas um
script de treino desavisado leria a foto deitada.

---

## R41 — Item inteiro ou nada

**Decisão.** Cada item é escrito numa pasta temporária, `items/.tmp-<id>/`, e
renomeado para `items/<id>/` só depois do último arquivo. Renomear no mesmo
volume é atômico: o item existe inteiro ou não existe (FR-014). O
`session.json` e a resposta são escritos com `.atomic` — arquivo temporário e
troca.

**Recuperação**, quando o módulo nasce, antes de qualquer outra coisa na fila
da coleta:

1. apagar toda `.tmp-*`;
2. fechar toda sessão que ficou aberta, com `endReason: "recovered"` e o fim no
   horário do último item;
3. apagar as que ficaram sem nenhum item (FR-019).

A telemetria é anexada linha a linha; depois de um encerramento forçado, a
última linha pode estar cortada, e o formato manda ignorá-la.

**Como fechar.** SC-006.

---

## R42 — Abrir, fechar, segundo plano, aba

**Decisão.**

| Evento | O que acontece com a coleta |
|---|---|
| ligar o modo | abre uma sessão; o JS envia as políticas em vigor (R45) |
| desligar o modo | espera a fila esvaziar, grava o fim e fecha; sem itens, apaga |
| trocar de aba | nada — a câmera para, a coleta não |
| segundo plano | fecha, como desligar |
| app encerrado à força | a recuperação fecha na próxima abertura (R41) |

O segundo plano é observado **no nativo**, por
`UIApplication.didEnterBackgroundNotification`, com uma tarefa de segundo
plano para a fila terminar os itens pendentes. Não pelo `AppState` do JS: a
regra da câmera dispara em `inactive` — puxar a Central de Controle, por
exemplo —, e fechar a coleta ali encerraria sessões por acidente.

**Alternativas.** Fechar também na troca de aba: o autor escolheu não.
Deixar uma sessão aberta atravessar o segundo plano: o autor escolheu fechar.

---

## R43 — A contagem real

**Decisão.** O nativo guarda **um item à espera de resposta** por vez: o
último gravado — marca ou captura. A resposta só é aceita para ele; voltar à
câmera, retomar o ao vivo, um item novo ou o fim da sessão o liberam
(FR-011). A resposta entra na fila depois do trabalho do item, então chega ao
disco depois dele mesmo que a pessoa responda antes de o JPEG de 12 MP
terminar.

| Situação | `truth.json` |
|---|---|
| respondeu | `{ count, skipped: false, prefill, answeredAt }` |
| pulou | `{ count: null, skipped: true, prefill, answeredAt }` |
| saiu sem responder, ou o app fechou | ausente |

As duas últimas são "sem resposta" na spec; o formato distingue as duas de
graça.

**O preenchimento.** Na captura, a contagem do resultado. Na marca, a contagem
que a tela mostrava, ou a do quadro quando a faixa está desligada (R37).

---

## R44 — Exportar

**Decisão.** O zip vem do próprio sistema: ler a pasta da sessão por um
`NSFileCoordinator` com `.forUploading` entrega um zip dela, num endereço
temporário que vale enquanto a leitura dura. Ele é copiado para
`collection/<id>.zip` — substituído a cada exportação, apagado com a sessão — e
entregue a um `UIActivityViewController`, apresentado pelo próprio módulo a
partir do controlador de tela do Expo. A promessa resolve quando o menu fecha,
dizendo se foi compartilhado.

Antes de zipar, o `FORMAT.md` vai para a pasta da sessão (FR-017). Ele vem do
bundle do app, para onde o config plugin o copia a partir do
[contrato do formato](./contracts/zip-format.md): o contrato **é** o arquivo
que vai no zip, e não existe uma segunda cópia para divergir.

Exportar confere antes se há espaço para o zip — da ordem do tamanho da
sessão — e falha avisando, com a sessão intacta.

**Alternativas.** `expo-sharing`: uma dependência a mais para abrir um menu
que são vinte linhas de Swift. Uma biblioteca de zip (ZIPFoundation,
SSZipArchive): um pod novo para o que o sistema já faz. Zipar em JavaScript:
pixels atravessando, princípio II.

---

## R45 — O que mais vai na sessão

**Decisão.**

- **O modelo.** Os metadados do próprio `.mlpackage` — o Ultralytics grava a
  data do export, a versão, o `imgsz` e as classes — e o **SHA-256 dos pesos**,
  calculado uma vez na carga. Quando o modelo for retreinado, é isso que
  separa as sessões de um e de outro.
- **O app e o aparelho.** Versão e build do bundle, o identificador do
  aparelho e a versão do sistema.
- **As políticas.** O JS envia, ao abrir a sessão, as políticas em vigor —
  sessão, captura, faixa, aparência e coleta — e o nativo as grava como
  chegaram, sem interpretar. Cada item grava também o que ele mesmo usou:
  limiares, modo de transformação e as opções da captura, porque essas coisas
  mudam no meio de uma sessão (o diagnóstico, por exemplo).
- **A telemetria.** O nativo já monta uma amostra a ~2 Hz para o evento
  `onTelemetry`. Com a coleta aberta, a mesma amostra vira uma linha de
  `telemetry.jsonl`, junto com as linhas de início e fim de cada sessão de
  câmera. Nada novo atravessa.

---

## R46 — Espaço e o indicador

**Decisão.** Antes de cada marca e de cada captura gravada, o nativo lê o
espaço livre (`volumeAvailableCapacityForImportantUsage`) e compara com o
limite da política. Abaixo dele, a marca é recusada e a captura acontece sem
ser gravada, devolvendo o motivo (FR-020).

O indicador mostra marcas, capturas e megabytes, que chegam pelo
`onCollectionChange` a cada item. O tempo de sessão é calculado no JS a partir
do início, num componente pequeno que se redesenha **uma vez por segundo** — o
princípio III proíbe estado de React por quadro, a 60 Hz; um segundo é cromo.

**Alternativas.** Um evento nativo por segundo com o tempo: uma travessia
para dizer o que o JS sabe calcular.

---

## Já decidido, sem pesquisa

| Decisão | Valor |
|---|---|
| Nome, sessões, contagem real, histórico, exportar, controles | decisões do autor (spec) |
| Ao vivo | só sob demanda; nenhuma amostragem automática |
| Formato das imagens | JPEG, qualidade da política |
| Limiar mínimo, limite de espaço, qualidade | em `src/collection/policy.ts` (princípio IV) |
| Rótulos para o Roboflow, editar a resposta depois | fora — decisão do autor |
| Dependências novas | nenhuma |
| Verificação do zip | um script de checagem na pasta da spec, ao lado das medições — o primeiro Python escrito para o projeto, e de propósito: ele mede o portão, não faz parte do app |

---

## Constitution Check, revisto depois da fase 1

| Princípio | Depois do desenho |
|---|---|
| I | A gravação tem fila própria. A marca é um sinal lido pelo laço da câmera; o congelamento usa `showStill` e a publicação que já existem. O display nunca espera nada da coleta. |
| II | Imagens, protótipos e tensores nascem e morrem no nativo. Atravessam identificadores, contagens, bytes, o resumo das sessões e, uma vez por sessão, as políticas — todos muito abaixo de 64 KB. |
| III | Nenhum estado de React por quadro. O evento da coleta é discreto; o relógio do indicador, 1 Hz. |
| IV | Limiar mínimo, limite de espaço e qualidade vêm do TS. O que fica no Swift é definição de formato — fp16, a forma dos protótipos, os nomes dos arquivos —, não ajuste. |
| V | SC-001 a SC-006 numéricos, verificados no aparelho e no zip. |

**Continua sem violação.**
