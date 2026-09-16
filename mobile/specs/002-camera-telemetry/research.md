# Fase 0 — Pesquisa

Quatro incógnitas. Nenhuma ameaça o marco como a R1 ameaçava o anterior — a
viabilidade já foi provada. Estas são sobre custo e correção.

---

## R6 — Qual formato de captura pedir

**Incógnita.** A câmera do iPhone 14 Plus oferece dezenas de formatos. Capturar
em 4K para reduzir a 640×640 desperdiça banda de memória e energia — e energia
é exatamente o que este marco mede.

**Direção.** O menor formato 4:3 cujas duas dimensões passem de 640. Formato de
pixel em BGRA se a transformação for por Core Image; YUV se o custo de conversão
aparecer na medição.

**Como fechar.** Enumerar os formatos no aparelho, escolher, e medir o consumo
com dois candidatos se houver dúvida.

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

**Como fechar.** A telemetria separa transformação de inferência. Se a
transformação custar mais que a inferência, a escolha se reabre.

---

## R8 — Preview sem bloquear a inferência

**Incógnita.** Como exibir o buffer transformado a 60 Hz sem que o desenho e a
inferência esperem um ao outro (princípio I).

**Direção.** `AVSampleBufferDisplayLayer` recebendo o buffer transformado. O
caminho de exibição é do compositor; a inferência consome o mesmo buffer em
paralelo.

**A armadilha.** Se os dois retiverem o mesmo `CVPixelBuffer`, o pool esvazia e
a captura trava esperando buffer livre. Retenção e liberação precisam ser
explícitas nos dois caminhos.

---

## R9 — Orientação

**Incógnita.** A conexão de vídeo entrega frames na orientação do sensor, não da
interface. Com o aparelho em retrato, o buffer costuma chegar deitado.

**Por que importa mais aqui do que parece.** O dataset foi fotografado com este
mesmo aparelho. Se os frames chegarem rotacionados em relação às fotos de
treino, o modelo vê a cena de lado — e a degradação é silenciosa, do mesmo tipo
que já nos custou duas rodadas.

**Como fechar.** O preview mostra o que o modelo recebe. Se aparecer deitado, o
problema é visível em um segundo. **Esta é a justificativa principal da decisão
de preview.**

---

## Já decidido, sem pesquisa

| Decisão | Valor | Por quê |
|---|---|---|
| Origem dos frames | `AVCaptureSession` próprio | frames nunca tocam JavaScript (princípio II) |
| Preview | o buffer transformado | torna geometria e orientação visíveis |
| Cadência | toda frame | medir o teto antes de otimizar |
| Registro | JSON para a área de transferência | torna a medição versionável |
| Transformação | as três, selecionáveis | o Roboflow ainda não foi confirmado |
| Ação térmica | nenhuma | pertence ao marco 6; aqui só se mede |
