# Fase 0 — Pesquisa

Quatro incógnitas. A R15 é a que decide se o marco entrega algo confiável.

---

## FECHAMENTO — revisão do código contra a spec, 25/09/2026

A T030 fechou a última incógnita, a R16. Antes de encerrar o marco, uma leitura
do código contra a spec achou sete desvios. Nenhum aparece no uso normal, e é
por isso que sobreviveram até aqui. **Tudo abaixo está escrito e ainda sem
build**; a validação vem junto com a T034.

| | o que estava | o que ficou |
|---|---|---|
| FR-008 | divisões calculadas e nunca desenhadas: só o texto "N divisões" | linhas sobre o resultado, com botão para ligar e desligar |
| SC-004 | a foto inferia com `0.25`/`0.7` fixos no Swift, ignorando a sessão | a foto usa os limiares do ao vivo |
| princípio IV | tolerância de em pé, vão entre fileiras, mínimo por fileira e pesos da confiança fixos na `ShelfGeometry` | em `CaptureOptions.geometry`, com os mesmos valores |
| contrato | `geometryConfidence` levava a confiança do **azimute**, não a da R15, que é a que o limiar compara | `geometryConfidence` é a da R15; a do azimute atravessa como `azimuthConfidence` |
| FR-011 | com a geometria recusada, "poucos livros" era trocado por "sem ponto de fuga horizontal" | o motivo da estimativa vem primeiro |
| sessão | `configure` acumulava entrada e saídas na mesma `AVCaptureSession`; um segundo `startSession` falharia | remove as anteriores antes de adicionar |
| sessão | parar a sessão no resultado deixava congelamento e pausa presos | `startSession` e `stopSession` desfazem o estado de resultado |

Os dois defeitos de sessão foram achados na leitura, não no aparelho. O
histórico os expôs: ele é uma aba, e trocar de aba desmonta a câmera.

**O plano errou uma dependência.** O `expo-file-system` "já presente" estava
aninhado em `node_modules/expo/node_modules`. O autolinking o incluía no
binário, mas o app não conseguia importá-lo. Virou dependência direta, na mesma
versão.

**Tirar as faixas do aparelho.** Com `UIFileSharingEnabled`, a pasta de
documentos aparece no app Arquivos e em `ifuse --documents com.jxnatan7.vizi`:
`history/*.jpg` e o `index.json`. É o material para medir a releitura.

**Ficou para specs próprias**, por decisão do autor em 25/09: a releitura da
faixa endireitada pelo modelo, com caixas e máscaras no resultado, e a faixa de
interesse arrastável que limita onde a detecção vale.

---

## MEDIÇÃO — 5,6 min, 22 capturas, Release ✅

`medicoes/2026-09-17-canonico-22-capturas.json`. **19321 de 19321 frames.**

| | início | fim | |
|---|---|---|---|
| inferência | 6,60 ms | 6,46 ms | −2,0% |
| transformação | 1,45 ms | 1,46 ms | +0,3% |
| desenho | 1,50 ms | 1,30 ms | −12,8% |
| ponta-a-ponta | 36,38 ms | 34,53 ms | −5,1% |
| fps | 60,00 | 60,00 | 0,0% |

Térmico `nominal` do início ao fim. **Nenhum número piorou.**

**21 das 22 capturas são invisíveis na telemetria** — só a de 283,7 s deixou
marca (52 fps na janela). A troca de formato, a foto de 12 MP e a volta
acontecem sem que a sessão perceba.

### Bateria — a primeira medição real do projeto

**5 pontos em 5,6 minutos**, ou cerca de **53 pontos por hora**. É consumo alto:
câmera a 60 fps, inferência a cada frame, mais 22 capturas de 12 MP. Um app
assim esvazia a bateria em menos de duas horas de uso contínuo.

Não é defeito — é o preço de inferir a cada frame, que foi decisão consciente do
marco 2 com a promessa de medir depois. **Está medido.** E é o primeiro
argumento concreto a favor de limitar a cadência, que até agora não tinha
nenhum: o térmico nunca reclamou e a latência nunca cresceu.

### O que esta sessão fecha de outros marcos

| | |
|---|---|
| M2 · SC-001 térmico | ✅ `nominal` em 5,6 min |
| M2 · SC-002 latência | ✅ −2,0% |
| M2 · SC-003 fps | ✅ 0,0% |
| M2 · SC-005 e2e | ✅ 35,9 ms |
| M2 · SC-007 bateria | ✅ **medida** — 53 pontos/hora |
| M4 · T007 câmera volta | ✅ confirmado 22 vezes, não uma |

## REESTRUTURAÇÃO — espaço canônico, 17/09/2026

**O sintoma.** A foto saía em 4032×3024 (paisagem), o frame de vídeo em
768×1024 (retrato). Esticados para 640×640, produziam deformações **opostas** de
cenas **giradas 90°** entre si. As detecções da foto desenhadas sobre o frame de
vídeo não podiam coincidir.

**A causa raiz não era a rotação.** Era o alinhamento depender de **duas
configurações independentes concordarem**: `videoRotationAngle` na conexão de
vídeo e na conexão de foto. Uma pegou, a outra não. Mesmo se as duas tivessem
pegado, o alinhamento seria coincidência, não garantia.

**A correção.** Um espaço canônico, e tudo converte para ele explicitamente:

```
fonte (vídeo OU foto, qualquer orientação e resolução)
   ↓  normalizar para retrato    ← no nosso código, olhando as dimensões
   ↓  transformar para 640×640   ← a transformação escolhida
CANÔNICO — o que o modelo vê É o que a tela mostra
```

A normalização vive no `FrameTransform` e olha o próprio buffer: largura maior
que altura, gira. **Autocorretiva** — some a classe inteira de bug "as duas
conexões discordam".

**E o segundo defeito, que não era bug.** As detecções vinham da foto e a
imagem exibida era o frame de vídeo congelado: duas imagens na tela. Isso era a
T028 não construída, e as peças tinham sido implementadas numa ordem que produz
um estado intermediário incoerente. `PreviewSink.showStill` passou a exibir a
imagem canônica da foto, e a T028 deixou de ser refinamento para virar
pré-requisito de coerência.

**O que ficou redundante.** A rotação na conexão de vídeo. Mantida porque poupa
uma rotação por frame no caminho ao vivo — mas **nada mais deve depender dela**
para alinhar detecção com imagem.

---

## R14 — Geometria da estante a partir das máscaras

**Por que não das caixas.** Uma caixa alinhada aos eixos é idêntica para um
livro reto e um inclinado. A inclinação está na silhueta.

**Direção.** Para cada máscara, PCA sobre os pixels ativos: o autovetor
dominante é o eixo da lombada, e projetando a silhueta nesse eixo saem os
extremos superior e inferior. Duas nuvens de pontos — topos e bases — e uma
reta ajustada a cada uma dá as bordas da estante.

**A parte barata.** Isso roda **uma vez**, na captura, não a 60 Hz. Pode custar
dezenas de milissegundos sem incomodar.

**Como fechar.** Desenhar o quadrilátero estimado sobre a foto, antes de
endireitar, e olhar se ele acompanha a estante.

**Fechada em 24/09 — por outro caminho.** O quadrilátero pelos topos e bases
foi abandonado: topos de livros não formam reta. A retificação passou a ser **do
plano**. A gravidade dá a vertical, e a reta das bases da fileira mais
populosa, cruzada com o horizonte, dá a horizontal. As máscaras ficaram com três
papéis: separar em pé de deitado, achar as bases e agrupar as fileiras. O
desenho sobre a foto crua (T017) foi o que tornou isso depurável; o SC-003 foi
validado pelo autor na T022.

---

## R15 — Quando confiar na geometria

**O risco.** Endireitar errado é pior que não endireitar: entrega uma imagem
torta com aparência de corrigida.

**Sinais candidatos:**

| sinal | o que indica |
|---|---|
| nº de objetos | menos de ~5 torna as retas mal determinadas |
| resíduo do ajuste | topos ou bases que não formam reta |
| paralelismo dos eixos | lombadas que não convergem para um ponto comum |
| sanidade do quadrilátero | convexo, sem auto-cruzamento, proporção plausível |
| ângulo implícito | acima de ~30° a correção estica demais |

**Como fechar.** Coletar os sinais em capturas reais, incluindo casos
deliberadamente ruins — três livros, estante curva, foto muito de lado — e
calibrar os limiares com dado, não com palpite.

**Fechada em 24/09, com uma lacuna.** Entraram quatro sinais: contagem de
livros em pé, resíduo da reta das bases, dispersão angular das lombadas e
diferença de inclinação entre fileiras. A sanidade do quadrilátero virou guarda,
não nota, e o ângulo implícito não entrou. Os limiares ficaram em 5 livros e
0,6, e "recusa em vez de errar" foi validado pelo autor (T023, T024).

**A lacuna:** os números das capturas ruins não foram registrados. E não seriam
os do limiar: até 25/09 o `geometryConfidence` na tela era o do azimute (ver
fechamento). A próxima calibração — a faixa de interesse muda o que entra na
geometria, então vai haver uma — já tem o número certo na tela.

---

## R16 — Animar uma correção de perspectiva

**O problema.** Recorte e zoom são afins e o Core Animation faz. Endireitar é
projetivo, e `CGAffineTransform` não representa.

**Direção.** `CATransform3D` tem o termo `m34` de perspectiva, e uma homografia
de plano se decompõe nela. O Core Animation interpola a matriz e a GPU faz o
mapeamento — sem redesenhar nada.

**A armadilha.** Interpolar linearmente os elementos de uma matriz projetiva
não produz movimento visualmente linear. Pode ser preciso interpolar em
parâmetros (ângulo, escala, translação) e remontar a matriz por quadro.

**Como fechar.** Olhar. Se a animação acelerar ou torcer de forma estranha no
meio, é isso.

**O que foi feito (2026-09-24).** Nem decomposição, nem interpolação da matriz.
A 3×3 cabe inteira na `CATransform3D` — a terceira linha da homografia vai para
`m14`, `m24` e `m44` —, e o que se interpola são os **quatro cantos**, cada um
em linha reta. A homografia de cada instante sai dos cantos, um quadro-chave
por quadro de tela; entre dois vizinhos, a interpolação do Core Animation não
tem espaço para torcer.

A camada animada é **o próprio resultado**, deformado de volta ao quadrilátero
do recorte. No último quadro a transformação é só uma translação, e a troca
pela camada de vídeo, com a mesma imagem por baixo, não tem o que mostrar
(FR-010).

**Fechada em 25/09** pela T030, validada pelo autor: SC-001 e SC-002, sem a
torção que a armadilha previa.

---

## R17 — Trocar de formato sem quebrar a sessão

**O que acontece.** A sessão ao vivo roda em 1024×768. A foto em resolução
máxima exige outro formato ativo, e a troca interrompe a entrega de frames.

**Direção.** No toque: congelar a última imagem na tela, trocar o formato,
capturar, restaurar o formato, retomar. O carregamento cobre o intervalo, e a
transição já começou com o frame congelado (FR-009).

**O que medir.** Quanto custa a ida e volta. Se passar de ~1 s, o SC-001 fica
apertado e vale considerar manter um formato único que sirva aos dois.

**Risco conhecido.** A retomada precisa devolver 60 fps (SC-005). Uma sessão
que volta degradada é pior que uma que demora a voltar.

**Fechada em 17/09.** A ida e volta não degrada a sessão: 60 fps de volta
depois de cada uma das 22 capturas da medição no topo deste arquivo, e 21
delas nem aparecem na telemetria (T007).

---

## Já decidido, sem pesquisa

| Decisão | Valor |
|---|---|
| Captura | foto em resolução máxima, troca de formato no toque |
| Inferência na foto | uma só, sem ladrilhamento |
| Recuo do endireitamento | mostra sem corrigir, e avisa |
| Resultado | faixa recortada, com arrasto horizontal |
| Histórico | local: imagens em arquivo, índice em JSON |
| Superfície | uma view nativa com dois estados |
