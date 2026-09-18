# Fase 0 — Pesquisa

Quatro incógnitas. A R15 é a que decide se o marco entrega algo confiável.

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
