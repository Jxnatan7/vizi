# Fase 0 — Pesquisa

Quatro incógnitas. Nenhuma ameaça o marco como a R1 ameaçava o anterior — a
viabilidade já foi provada. Estas são sobre custo e correção.

---

## MEDIÇÃO — 16/09/2026, sessão ao vivo ⚠️ BUILD DEBUG

`medicoes/2026-09-16-stretch-debug.json` — 3,6 min, `stretch`, 437 amostras.

| | resultado |
|---|---|
| frames | **13091 de 13092** processados (99,99%) |
| taxa | **60 fps sustentados**, sem queda |
| térmico | `nominal` → `nominal`, nenhuma transição |
| bateria | 85% → 85%, sem variação mensurável |
| ponta-a-ponta | **39,6 ms** (limite 80) |

Degradação entre os primeiros e os últimos 10%:

| | início | fim | |
|---|---|---|---|
| inferência | 6,53 ms | 6,47 ms | −0,9% |
| transformação | 1,39 ms | 1,45 ms | +4,2% |
| decodificação | 2,87 ms | 2,69 ms | −6,3% |
| fps | 60,00 | 60,00 | 0,0% |

**Nenhuma degradação.** O trabalho por frame soma 11,48 ms de um orçamento de
16,67 ms — folga de 5,19 ms, e é ela que sustenta os 60 fps.

### Portão

| | | |
|---|---|---|
| SC-001 térmico ≤ fair | ✅ | `nominal` o tempo todo |
| SC-002 latência +50% máx | ✅ | −0,9% |
| SC-003 fps −20% máx | ✅ | 0,0% |
| SC-004 fila ≤ 1 | ⚠️ | passa **trivialmente** — ver limitação |
| SC-005 e2e < 80 ms | ✅ | 39,6 ms |
| SC-007 bateria | ⚠️ | **não mensurável** em 3,6 min |

### Duas ressalvas que impedem declarar o marco fechado

**1. É um build Debug, com Swift em `-Onone`.** Comparando com o marco 1, medido
em Release sobre buffer estático:

| | marco 1 (Release) | agora (Debug) | |
|---|---|---|---|
| inferência | 3,1 ms | 6,5 ms | 2,1× |
| decodificação | ~0,1 ms | 3,5 ms | **~35×** |

A decodificação é um laço sobre 8400 âncoras — exatamente o que `-Onone` não
otimiza. Os 35× têm explicação sólida.

**Os 2,1× da inferência não têm.** O `modelMs` cronometra só
`model.prediction(from:)`, que é código do Core ML e não deveria depender da
nossa configuração de build. Hipóteses não verificadas: buffers rotativos do
pool contra um único buffer reutilizado, ou o acelerador sob carga sustentada a
60 Hz em vez de rajadas. **Medir em Release antes de concluir qualquer coisa.**

Se a decodificação voltar a ~0,1 ms, o trabalho por frame cai de 11,5 para
~4,5 ms e a folga triplica.

**2. A bateria não foi medida.** O iOS reporta em degraus grossos, e 3,6 minutos
não movem o indicador. O SC-007 exige uma sessão longa de verdade.

---

## R6 — Qual formato de captura pedir

**Incógnita.** A câmera do iPhone 14 Plus oferece dezenas de formatos. Capturar
em 4K para reduzir a 640×640 desperdiça banda de memória e energia — e energia
é exatamente o que este marco mede.

**Direção.** O menor formato 4:3 cujas duas dimensões passem de 640. Formato de
pixel em BGRA se a transformação for por Core Image; YUV se o custo de conversão
aparecer na medição.

**RESOLVIDA.** O aparelho escolheu **1024×768 a 60 fps** — o menor 4:3 com os
dois lados acima de 640. Não houve necessidade de comparar candidatos.

---

## R7 — Custo da transformação do frame

**Incógnita.** Converter o frame da câmera em 640×640 é trabalho por frame que
não existia no marco 1 — lá o buffer já vinha pronto.

**Direção.** Core Image com contexto sobre Metal, escrevendo num
`CVPixelBufferPool` reutilizado. Alocar buffer por frame a 60 Hz seria 100 MB/s
de lixo.

**Por que não deixar o Vision fazer.** O `VNImageCropAndScaleOption` oferece
exatamente as três transformações de graça — mas faz a conversão internamente e
**não devolve o buffer resultante**. O preview deste marco mostra o que o modelo
recebe, então precisamos do buffer na mão.

**RESOLVIDA.** A transformação custa **1,50 ms** — 13% do trabalho por frame,
contra 57% da inferência. O Core Image sobre Metal dá conta e a escolha não se
reabre.

---

## R8 — Preview sem bloquear a inferência

**Incógnita.** Como exibir o buffer transformado a 60 Hz sem que o desenho e a
inferência esperem um ao outro (princípio I).

**Direção.** `AVSampleBufferDisplayLayer` recebendo o buffer transformado. O
caminho de exibição é do compositor; a inferência consome o mesmo buffer em
paralelo.

**A armadilha.** Se os dois retiverem o mesmo `CVPixelBuffer`, o pool esvazia e
a captura trava esperando buffer livre.

**RESOLVIDA.** Pool de 6 buffers. 13091 de 13092 frames processados — o pool
nunca esvaziou.

---

## R9 — Orientação

**Incógnita.** A conexão de vídeo entrega frames na orientação do sensor, não da
interface. Com o aparelho em retrato, o buffer costuma chegar deitado.

**Por que importa mais aqui do que parece.** O dataset foi fotografado com este
mesmo aparelho. Se os frames chegarem rotacionados em relação às fotos de
treino, o modelo vê a cena de lado — e a degradação é silenciosa, do mesmo tipo
que já nos custou duas rodadas.

**RESOLVIDA** na primeira execução, olhando o preview — que é exatamente para
isso que ele existe. Retrato correto, `videoRotationAngle = 90` na conexão de
captura funcionou.

---

## Geometria — confirmada pelo autor (16/09/2026)

O dataset foi montado no Roboflow com **resize 640×640, preset YOLOv8**, cujo
modo padrão é **Stretch to**. As fotos vieram do próprio iPhone 14 Plus, câmera
traseira sem zoom, e passaram por aumento de dados.

**Logo `stretch` é a transformação correta** — e já é o padrão em
`DEFAULT_SESSION`. A câmera entrega 4:3 e é esticada para o quadrado, do mesmo
jeito que as fotos de treino foram.

As outras duas continuam implementadas: servem de controle. Se `stretch` não
produzir a melhor contagem no aparelho, a discordância entre o registro e a
medição é sinal de que algo mais está errado — e aí vale investigar, não
escolher a que der melhor número.

## Já decidido, sem pesquisa

| Decisão | Valor | Por quê |
|---|---|---|
| Origem dos frames | `AVCaptureSession` próprio | frames nunca tocam JavaScript (princípio II) |
| Preview | o buffer transformado | torna geometria e orientação visíveis |
| Cadência | toda frame | medir o teto antes de otimizar |
| Registro | JSON para a área de transferência | torna a medição versionável |
| Transformação | as três, selecionáveis | o Roboflow ainda não foi confirmado |
| Ação térmica | nenhuma | pertence ao marco 6; aqui só se mede |


---

## Limitação conhecida: `dropped` e `queueDepth` não medem nada

O delegate da câmera é serial na mesma fila onde a inferência roda, então o
`FrameGate` nunca vê "ocupado". Os dois campos leem **sempre zero**, mesmo se
frames estivessem sendo descartados — quem descartaria é o
`alwaysDiscardsLateVideoFrames` da AVFoundation, antes de chegar a nós.

**Consequência: o SC-004 passa trivialmente e não testa nada.**

O sinal real de descarte é **`fpsCaptured` caindo abaixo de 60**. Nesta sessão
ficou em 60,00 de mediana, com mínimo de 25,95 em algum instante isolado — o
que indica que houve, sim, momentos de perda.

Conserto, quando incomodar: mover a inferência para fila própria. Fica
registrado em vez de corrigido porque o descarte funciona; o que não funciona é
a métrica.
