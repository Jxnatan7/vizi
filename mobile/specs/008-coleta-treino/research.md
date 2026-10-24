# Fase 0 — Pesquisa

Continua a numeração da 007 (R36–R46). As medições de R50 a R52 foram feitas
nas 12 capturas da sessão `2026-10-20T10-41-44`, com os scripts descartáveis
da análise de 20/10.

---

## R47 — Onde o tipo, a luz e a prateleira entram no registro

**Incógnita.** A spec pede que cada item guarde prateleira e variação, e a
sessão, tipo e luz. Dá para fazer sem tocar no Swift?

**Achado.** Não. A captura grava as opções que recebeu campo a campo
(`CaptureOptions.collectionDictionary`): um campo novo no TypeScript some no
caminho. `markFrame` não recebe nada. Só as políticas da sessão passam sem
interpretar (`CollectionOptionsRecord.policies`).

**Decisão.**

- **Item:** `capture` e `markFrame` ganham um segundo argumento, `tags`, um
  dicionário que o nativo grava como chegou em `item.json`, na chave `tags`.
  Argumento, e não um estado guardado no nativo: o valor é o do toque por
  construção, e um recarregamento do JavaScript não deixa no nativo uma
  prateleira velha.
- **Sessão:** `startCollection` ganha `session`, um dicionário — tipo, luz e,
  na prova, as prateleiras cadastradas com seus números —, que o nativo grava
  no topo de `session.json` e devolve no estado e na lista, para a câmera e a
  Medição saberem o tipo da sessão aberta mesmo depois de trocar de aba.

**Alternativas.** Guardar a escolha num estado do nativo, mudado a cada toque
no seletor: menos parâmetros, mas dois donos da mesma escolha. Pôr os campos em
`policies`: passaria sem Swift novo, mas a lista e o estado não os veriam, e
política não é o que a sessão é.

---

## R48 — O modo rápido sem nativo novo

**Incógnita.** Voltar ao vivo sem mostrar o resultado exige mudar a captura?

**Achado.** Não. A aproximação, o endireitamento e a volta duram
`approachMs`, `transitionMs` e o mesmo `transitionMs` no `dismissResult` —
políticas do TypeScript. Com zero, o `ResultRenderer` já encaixa sem animar:
`begin` só anima com duração positiva, e `morph` e `fade` saem antes de criar
animação quando a duração é zero.

**Decisão.** No treino, a captura vai com `approachMs: 0` e `transitionMs: 0`
(`FAST_CAPTURE`, em `src/collection/policy.ts`), sem diagnóstico, e o
JavaScript chama `dismissResult` assim que o resultado chega, sem passar pelo
estado `result`. A captura roda inteira — foto, geometria, recorte, releitura —
e a coleta grava como sempre. O item fica sem resposta: `dismissResult` já
libera o que esperava resposta (R43).

**O tempo.** Em 20/10, `toque → pronto` foi de 690 a 831 ms nas 12 capturas, e
a releitura de 10 a 71 ms. Somando a volta pela ponte, a câmera volta perto de
1 s depois do toque. O SC-001 pede menos de 1,5 s.

**Medido em 23/10** (270 capturas de treino): mediana de `toque → pronto`
700 ms; com a releitura, acima de 1,45 s em 9; o autor capturou de novo até
0,93 s depois da anterior. Gravar custa ~400 ms por captura, em segundo plano,
como na 007 — compor o recorte sobre preto não pesou.

**O que se vê.** A imagem endireitada pode aparecer por um ou dois quadros
entre `showStill` e a volta. Não é o resultado — é o que custa não mudar o
nativo, e não muda o que é gravado.

---

## R49 — Prateleiras e guia no JavaScript

**Incógnita.** Onde vivem as prateleiras e o guia, que sobrevivem às sessões
apagadas (FR-012)?

**Decisão.** Num arquivo JSON do app, `Documents/shelves.json`, lido e escrito
pelo `expo-file-system`, que o app já usa no histórico, com a mesma fila de
escrita. O nativo não sabe que prateleiras existem: recebe a escolha como
`tags` (R47).

- **O guia é um contador.** Cada captura de treino que volta com
  `collectionItemId` soma um na célula — prateleira, luz, distância e ângulo —
  ou nas fotos sem livros. Apagar a sessão não desconta. Um item que falhar
  depois, na fila de gravação, fica contado; o indicador mostra o erro, e o
  custo é uma célula marcada a mais.
- **Prateleira tem identificador.** O guia e as sessões a seguem pelo id;
  renomear não perde o que já foi feito. As sessões guardam também o nome e o
  número do momento.

**Alternativa.** Reconstruir o guia lendo as sessões no aparelho: zera quando
a pessoa apaga uma sessão para liberar espaço, que é exatamente o que ela vai
fazer depois de mandar as fotos para o Roboflow.

---

## R50 — A imagem do recorte para o Roboflow

**Incógnita.** O recorte gravado (`crop.jpg`) é a imagem que a releitura leu?

**Medição.** Encaixando o `crop.jpg` num quadrado — centrado, com preto em
volta, pela mesma conta do `FrameTransform.fit` — e reduzindo a 640:

- **A geometria é exata.** O retângulo calculado é o gravado em
  `reread.content` nas 12 capturas, até o décimo de pixel.
- **Os pixels não eram.** Em três capturas a correlação com o quadrado
  gravado caía para 0,45–0,53. A causa: onde o recorte endireitado sai da
  foto, sobra uma cunha sem imagem. A releitura a vê **preta** — o `fit`
  compõe sobre preto —, e o `crop.jpg` a grava **branca**: o buffer tem alfa
  zero ali, e o JPEG achata a transparência em branco. A cunha ocupa até 7% do
  recorte.
- **Com a cunha refeita pela geometria**, as 12 ficam com correlação de 0,983
  a 0,998 e diferença média de 1,8 a 5,3 níveis em 255, com um viés de cerca de
  −2. O resto é compressão e a redução do Core Image, que trabalha em luz
  linear.

**Decisão.**

1. **O app passa a gravar a cunha preta.** No `CollectionWriter`, o recorte
   é pré-multiplicado pelo alfa e gravado opaco, o que é compor sobre preto. O
   `crop.jpg` fica sendo o que a releitura leu, em resolução cheia. É um
   conserto da 007; o formato não muda de versão, e o `FORMAT.md` registra a
   mudança.
2. **A ferramenta refaz a cunha das sessões anteriores pela geometria**: a
   homografia leva os cantos do recorte a `geometry.sourceQuad`, e o que cai
   fora da foto vira preto. **Corrigido em 23/10:** é só uma aproximação. Nas
   270 capturas das sessões de 23/10 ela errou em 70 — pintava de preto parte
   dos livros —, porque o endireitamento não é esse mapa; nenhuma ordem dos
   cantos reproduz a cunha. Nas sessões da 008 o app já grava a cunha preta e
   a ferramenta não a refaz (270 de 270 passam na conferência); nas anteriores
   refaz, e a conferência recusa onde errar — nas 12 de 20/10, acertou.
3. **A imagem vai em 2048×2048**, com o recorte encaixado como na releitura.
   O Roboflow a reduz a 640 sem distorcer — um quadrado continua quadrado —, e
   a pessoa marca com três vezes a resolução que o modelo vê.
4. **A ferramenta confere cada imagem (SC-003):** o retângulo do conteúdo é o
   gravado, e a imagem reduzida tem correlação de pelo menos 0,97 com o
   quadrado gravado. Correlação, e não diferença absoluta: ela ignora o viés
   de tom, que o treino cobre (R51).

**Alternativas.** Mandar o quadrado de 640 gravado: equivalente perfeito, mas
as lombadas finas ficam com poucos pixels para a pessoa marcar. Mandar o
`crop.jpg` como está: o Roboflow o esticaria para 640×640 — numa faixa de
4262×1477, isso engorda cada livro quase três vezes na altura —, e o modelo
aprenderia uma imagem que o app nunca lhe dá.

---

## R51 — A foto inteira

**Medição.** O `photo.jpg` esticado para 640 tem correlação de 0,988 a 0,997
com o `photo-square.jpg` nas 12 capturas, com um viés constante de −6,5 a −7,9
níveis: o quadrado que o modelo leu sai um pouco mais claro. É gestão de cor:
o quadrado passa pelo Core Image, e a foto vai do buffer ao JPEG pelo
VideoToolbox.

**Decisão.** A foto vai como está, copiada byte a byte, e o Roboflow a estica
para 640×640 — a mesma redução do dataset (002) e do app. O viés de 3% de
brilho fica dentro do aumento de dados que o treino já faz: a Ultralytics varia
o brilho em até ±40% por padrão. E as fotos do dataset atual também chegaram ao
treino pelo arquivo, como esta.

---

## R52 — Os contornos

**Medição.** Máscara de cada detecção pela regra do `FORMAT.md`, com o mapa de
logits ampliado de 160 para 640 por interpolação bilinear antes do limiar — a
160 o contorno sai em degraus de 4 px —, contorno externo e polígono
simplificado a 1% do perímetro:

| Captura | contornos | o app contou | vértices (mediana / máx.) | tempo |
|---|---|---|---|---|
| c0001 | 22 | 22 | 4 / 5 | 0,3 s |
| c0005 | 16 | 35 | 6 / 10 | 0,2 s |
| c0006 | 16 | 37 | 6 / 14 | 0,2 s |
| c0008 | 37 | 46 | 5 / 13 | 0,6 s |

Com o descarte de duplicatas, c0005 e c0006 ficam com 16 — o número real.

**Decisão.**

- **Todas as detecções da imagem**, não só as da faixa ou do recorte sem
  margem: o Roboflow e o treino exigem todo livro visível marcado.
- **Confiança mínima:** o limiar da sessão gravado no item (0,25).
- **Duplicata:** descartar a detecção cuja máscara está 80% ou mais dentro da
  máscara de uma mais forte, em ordem de confiança. São os números da análise
  de 20/10; os dois ficam como parâmetros da ferramenta (decisão adiada da
  spec).
- **Máscaras com menos de 20 pixels** a 640 não viram contorno — a mesma
  regra com que o app descarta máscara vazia (006, R34).
- **Na imagem do recorte**, os contornos vêm da releitura; **na foto**, da
  leitura da foto, com as coordenadas levadas do quadrado à foto pela regra
  `stretch` do `FORMAT.md`.
- **Fotos sem livros** vão sem contorno nenhum.

---

## R53 — Uma foto inteira em cada três

**Decisão.** A foto inteira vai quando a célula da captura está numa diagonal
do guia: `(distância + ângulo + luz) mod 3 = 0`, com os índices da ordem da
política e a luz valendo 0 de dia e 1 de noite. Em cada prateleira e cada luz,
isso escolhe 3 das 9 células, uma de cada distância e uma de cada ângulo, e a
noite pega outra diagonal. É determinístico — empacotar a mesma sessão duas
vezes escolhe as mesmas fotos — e não depende de ordem nem de quantas sessões
entram juntas.

Vão sempre: a foto das capturas sem recorte, e a das fotos sem livros. Nas
sessões sem tipo, sem variação gravada, vai uma em cada três pela ordem do
item.

**Alternativa.** A cada três capturas, pela ordem: com a pessoa varrendo o
guia linha a linha, três seguidas da mesma distância e a foto sempre da mesma
coluna.

---

## R54 — O formato do pacote

**Decisão.** Uma pasta com as imagens e um `_annotations.coco.json` (COCO,
segmentação por polígono), com a classe `book`. O Roboflow importa COCO JSON
com polígonos num projeto de segmentação, arrastando o JSON e as imagens na
página de upload. A comunidade recomenda soltar o JSON primeiro e testar com
um subconjunto antes de um lote grande ([docs][rf-upload], [fórum][rf-seg]).

- **Um arquivo de anotação**, e não um `.txt` por imagem do formato YOLO: o
  COCO leva o nome da classe, e o YOLO precisaria de um `data.yaml` para dizer
  que 0 é `book`.
- **O nome de cada imagem** é
  `<sessão>_<item>_<prateleira>_<variação>_<tipo>.jpg` — por exemplo
  `2026-10-23T19-02-11_c0042_sala-1_perto-frente-noite_recorte.jpg` —, com a
  prateleira em minúsculas, sem acento e com hífen. Ele é a única etiqueta que
  chega ao Roboflow sem API.
- **Risco a conferir na primeira importação:** se as fotos sem livros chegam
  como imagens vazias ("null") ou como "não anotadas". No segundo caso, a
  pessoa as marca como vazias no Roboflow. Está no quickstart.

[rf-upload]: https://docs.roboflow.com/developer/manage-images/upload-an-annotation
[rf-seg]: https://discuss.roboflow.com/t/how-to-upload-json-annotation-file-format-for-instance-segmentation/1611

---

## R55 — O relatório da prova

**Decisão.** Lê um ou mais zips de prova. Por captura: prateleira, contagem do
app (`result.count`), gabarito (`truth.json`), inventário gravado nas `tags` e
se a contagem bateu com o gabarito. Embaixo, o total de exatas e as prateleiras
de `session.shelves` sem nenhuma captura. Quando o gabarito difere do
inventário — a pessoa mudou o número —, o relatório mostra os dois.

Sessões que não são de prova são recusadas: medir o modelo numa sessão de
treino é medir nas fotos que ele vai estudar.

---

## R56 — Onde ficam as ferramentas

**Decisão.** Um arquivo só, `mobile/tools/coleta.py`, com dois comandos —
`pacote` e `prova` —, e as dependências declaradas no próprio arquivo (PEP 723),
para rodar com `uv run mobile/tools/coleta.py …` sem instalar nada antes:
`numpy`, `Pillow` e `opencv-python-headless`.

Fora da pasta da spec, ao contrário do verificador da 007: aquele mede um
portão uma vez, e este é usado a cada rodada de treino. Lê zip ou pasta já
extraída, porque o autor extrai os zips na raiz do repositório.

---

## R57 — O formato do zip passa a viver na 008

**Decisão.** O config plugin copia hoje `specs/007-modo-coleta/contracts/zip-format.md`
para dentro de todo zip. O formato ganha campos (R47) e o conserto da cunha
(R50), então a cópia viva passa a ser
`specs/008-coleta-treino/contracts/zip-format.md`, e o plugin aponta para
ela. O da 007 fica como a 007 o entregou. A versão continua 1: campos novos não
mudam a versão, pelo próprio formato.

---

## R58 — O contorno redesenhado pelo SAM

**Incógnita.** No primeiro pacote, importado no Roboflow em 22/10, o autor achou
os contornos ruins. São?

**Achado.** Nas laterais das lombadas, bons; no topo, ruins. A máscara do app
tem 160×160 — na imagem de 2048, um degrau de 13 px —, e no topo dos livros,
onde aparece o miolo das páginas, ela vaza para o vizinho em zigue-zague e às
vezes junta dois livros. Nos Spy x Family, o topo fica caótico.

**Decisão.** O contorno de cada livro é redesenhado pelo SAM 2.1 (base), com a
caixa da detecção como pergunta — o mesmo tipo de modelo do "Smart Polygon" do
Roboflow. A escolha das detecções não muda: limiar e descarte de duplicatas
continuam pela máscara do app (R52), e o SAM só refaz a borda. Sem máscara do
SAM para uma caixa, vale o polígono do app. Simplificação a 0,5% do perímetro,
porque o SAM segue a borda de perto.

- **Mede-se a olho, nas prévias:** lombadas e topos justos em c0005, c0007,
  c0008 e c0012. O SAM não conserta o que o app errou: uma detecção sobre o
  estojo da Ferrante continua lá, agora contornando as letras da capa.
- **Custo:** 6 a 12 s por imagem na CPU do autor (i5-1135G7), 2,5 min para as
  16 do pacote de 20/10; uma sessão de ~270 capturas, perto de 45 min. Na
  primeira execução, o `uv` baixa o PyTorch de CPU (~1,7 GB no cache) e a
  ferramenta, os pesos do SAM (154 MB, em `~/.cache/vizi/`).
- **`--sem-sam`** volta ao contorno do app, rápido e grosseiro.
- O PyTorch vem do índice de CPU, declarado no cabeçalho do script: o do PyPI
  traz CUDA, que este computador não usa.

**Alternativas.** Marcar à mão por quem lê as imagens — o assistente — não dá a
precisão de pixel que o treino pede. Pedir só o "Smart Polygon" no Roboflow:
funciona para corrigir, mas um clique por livro em ~300 imagens é o trabalho
que o pacote existe para poupar.

---

## R59 — Só as imagens, e quem marca é o Roboflow

**Decisão do autor, 22/10.** Com o SAM, os contornos continuaram ruins para
ele. O pacote ganha `--so-imagens`: as mesmas imagens — o recorte equivalente
ao que a releitura lê, a foto em uma de cada três, as fotos sem livros —, sem
contorno nem `_annotations.coco.json`, e quem marca é a IA do Roboflow.

**Por que ela pode marcar melhor.** O "Find Objects with AI" do Annotate usa o
SAM 3 com texto ("book"): acha e segmenta os livros sozinho, num modelo
centenas de vezes maior que o do app, e não depende das caixas do app — que
eram o limite do R58, porque livro que o app não achou ficava sem contorno, e
não-livro que ele achou ganhava um ([changelog do Roboflow][rf-find]). Lombadas
finas e coladas continuam difíceis para qualquer modelo: a revisão humana e a
[regra de contagem](../../models/regra-de-contagem.md) continuam valendo.

**O que fica.** A conferência de equivalência roda igual em toda imagem (SC-003);
sem contorno, o pacote leva segundos. O contorno do app, com ou sem SAM, segue
disponível sem a opção.

[rf-find]: https://docs.roboflow.com/changelog/explore-by-month/november-2025/find-objects-with-ai-annotation-tool

---

## R60 — Limpar o dataset antes de treinar

**Achado, 23/10.** O primeiro retreino, com o dataset v3 do Roboflow (154
fotos antigas e as 351 novas, cada uma do treino em 10 versões aumentadas),
ficou inseguro: confiança das caixas de ~0,9 para 0,3–0,7, e duas caixas
deslocadas por livro numa prateleira cheia. A auditoria do zip exportado achou
dois defeitos, nas fotos antigas e nas novas:

- **Marcações que se contradizem.** Estojo marcado junto com os livros de
  dentro (a caixa do Harry Potter, a da Holly Black), um contorno em volta de
  um grupo além dos contornos de cada livro, o mesmo livro duas vezes,
  fragmentos recortados dentro de um livro. 47% das fotos antigas e 34% das
  novas tinham ao menos um par de contornos com 70% ou mais do menor dentro do
  maior.
- **Marcação só com caixa.** 2.585 linhas `classe cx cy w h`, sem polígono,
  em 1.133 rótulos — quase todas de fotos novas. Num rótulo que também tem
  polígonos, a Ultralytics lê essas quatro coordenadas como dois pontos de um
  polígono: a caixa vira outra, e a máscara, vazia. Elas entraram no treino
  como lixo.

**Decisão.** `coleta.py limpar` gera uma cópia do zip: caixa vira retângulo;
contorno que contém dois ou mais com forma de livro (área ≥ 75% do retângulo
mínimo) sai como grupo ou estojo; os de dentro sem forma de livro saem como
fragmento; um de dentro com forma de livro sai como duplicata. No v3: 2.585
caixas convertidas e 4.812 marcações removidas (314 grupos, 1.164 duplicatas,
3.334 fragmentos), em 2 min. A primeira tentativa, que decidia "grupo" pela
área coberta, apagava os livros de dentro do estojo do Harry Potter e foi
descartada.

**O que a limpeza não faz.** Não-livro marcado sozinho — a capa do estojo da
Ferrante, a peça clara ao lado da luminária, um caderno espiral numa foto
antiga — e livro sem marcação. Isso é no Roboflow.

---

## Já decidido, sem pesquisa

| Decisão | Valor |
|---|---|
| Tipo, luz, modo rápido, guia, imagens, onde se empacota | decisões do autor (spec) |
| Distâncias, ângulos, descrições, meta de fotos sem livros, `FAST_CAPTURE` | `src/collection/policy.ts` (princípio IV) |
| Dependências novas no app | nenhuma |
| Tirar duplicatas da contagem do app | fora — spec própria |
| Subir pela API do Roboflow | fora |

---

## Constitution Check, revisto depois da fase 1

| Princípio | Depois do desenho | Veredito |
|---|---|---|
| **I** | O modo rápido usa as durações zero que o `ResultRenderer` já trata; nada espera a gravação. | ✅ |
| **II** | Atravessam o dicionário `tags` e o `session` — texto e números, centenas de bytes. Nenhuma imagem. | ✅ |
| **III** | Prateleiras, guia e escolha mudam por toque e por captura, nunca por quadro. | ✅ |
| **IV** | Vocabulário, descrições, metas e o modo rápido em TS; o nativo grava `tags` e `session` sem interpretar. O descarte de duplicatas é da ferramenta, não do app. | ✅ |
| **V** | SC-001 a SC-007 são numéricos; o SC-003 é conferido pela ferramenta em toda imagem. | ✅ |
