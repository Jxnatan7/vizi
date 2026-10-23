# Feature Specification: Coleta para treino e prova

**Feature Branch**: `mobile/008-coleta-treino`

**Created**: 2026-10-22

**Status**: Draft

**Input**: User description: "Gostaria que você melhorasse o modo coleta e
deixasse ele no jeito para eu tirar as próximas fotos e mandar para o
Roboflow." Nas respostas antes desta spec: **prateleiras no app**, com o
número do inventário, escolhidas a cada captura; sessão de **treino ou
prova**, escolhida ao ligar; **modo rápido no treino** — grava e volta direto
à câmera, sem mostrar o resultado nem pedir a contagem; **guia de variações**
por prateleira; a luz (dia ou noite) escolhida **uma vez, ao ligar** a sessão
de treino; para o Roboflow vão **o recorte de toda captura e a foto inteira de
uma em cada três**; e o pacote é gerado **por um script no Linux**, a partir
do zip que o app já exporta.

> **Para que serve.** O gate do projeto é contar com exatidão todos os livros
> da casa do autor. As coletas de 20/10 mostraram que o modelo erra no que
> nunca viu — livros grandes de perto, a madeira da casa, o estojo — e que a
> releitura entrega ao modelo uma imagem que ele não conheceu no treino: o
> recorte sem esticar e com preto em volta. O caminho é treinar com fotos da
> casa, marcadas pela [regra de contagem](../../models/regra-de-contagem.md),
> e medir numa prova que nunca entra no treino. Esta spec deixa o app e o zip
> prontos para as duas coisas.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Uma sessão de treino vira um pacote para o Roboflow (Priority: P1)

A pessoa liga o modo coleta e escolhe **treino** e a luz do momento — dia ou
noite. Na câmera, escolhe a prateleira e a variação — distância e ângulo — e
captura. A captura é gravada e a câmera volta direto ao vivo, sem resultado e
sem pergunta; o indicador conta mais uma e mostra a prateleira e a variação
gravadas. Ela muda a variação, captura de novo, e segue. Para as fotos sem
livro escolhe "sem livros". Ao fim, desliga, exporta o zip como hoje e o
leva ao Linux, onde um comando gera uma pasta: ela a arrasta para o Roboflow,
e cada imagem chega com o contorno dos livros que o app achou, para ela só
corrigir.

**Why this priority**: é o pedido. Sem o pacote, cada foto teria de ser
marcada do zero; sem o modo rápido, umas 270 capturas viram uma tarde de
toques.

**Independent Test**: uma sessão de treino de 20 capturas — duas sem livros —,
exportada e empacotada. A pasta traz o recorte de cada captura e a foto
inteira de uma em cada três, com os nomes certos e os contornos; importada no
Roboflow, os contornos caem sobre os livros.

**Acceptance Scenarios**:

1. **Given** o modo desligado, **When** a pessoa o liga, **Then** escolhe
   treino ou prova; no treino, escolhe também dia ou noite. A sessão guarda o
   tipo e a luz.
2. **Given** uma sessão de treino, **When** a pessoa ainda não escolheu
   prateleira e variação, **Then** capturar não está disponível, e a tela diz
   o que falta.
3. **Given** prateleira e variação escolhidas, **When** a pessoa captura,
   **Then** a captura é gravada com a prateleira, a variação e a luz, e a
   câmera volta ao vivo sem mostrar o resultado nem pedir a contagem. A
   escolha continua a mesma para a próxima captura.
4. **Given** "sem livros" escolhido, **When** a pessoa captura, **Then** a
   captura é gravada como foto sem livro, sem pedir distância nem ângulo.
5. **Given** uma sessão de treino exportada, **When** a pessoa roda o comando
   sobre o zip, **Then** recebe uma pasta pronta para arrastar no Roboflow,
   com o recorte de toda captura que teve recorte, a foto inteira de uma em
   cada três capturas de cada prateleira e a foto de toda captura sem livros.
6. **Given** a pasta, **When** a pessoa a importa no Roboflow, **Then** cada
   imagem de livros chega com um contorno em cada livro que o app achou nela
   — também os de fora da faixa e os das bordas —, sem contornos repetidos no
   mesmo livro; as fotos sem livros chegam sem contorno.
7. **Given** uma imagem da pasta, **When** o Roboflow a reduz ao tamanho que o
   modelo lê, **Then** ela é a mesma imagem que o modelo leu no app: o recorte
   sem esticar e com preto em volta, ou a foto esticada.

---

### User Story 2 - A prova, com o inventário como gabarito (Priority: P2)

A pessoa liga o modo coleta e escolhe **prova**. Em cada prateleira, escolhe
qual é e captura. O resultado aparece como sempre, e a pergunta da contagem já
vem com o número do inventário daquela prateleira; ela confirma, ou pula e
captura de novo se algum livro ficou cortado. No Linux, um comando lê o zip e
mostra, por prateleira, quanto o app contou contra o inventário, e quais
prateleiras ficaram sem captura. O comando do Roboflow recusa essa sessão.

**Why this priority**: a prova é a régua do gate. Ela vale sem o treino — mede
o app de hoje —, mas não serve para nada sem prateleiras cadastradas, que vêm
da US3.

**Independent Test**: com o inventário cadastrado, uma prova de todas as
prateleiras, duas capturas cada. Toda pergunta vem com o inventário da
prateleira escolhida; o relatório lista todas, com o resultado de cada
captura; o comando do Roboflow recusa o zip.

**Acceptance Scenarios**:

1. **Given** uma sessão de prova, **When** a pessoa ainda não escolheu a
   prateleira, **Then** capturar não está disponível.
2. **Given** a prateleira escolhida, **When** a pessoa captura, **Then** o
   resultado aparece como fora do modo, e a pergunta da contagem vem
   preenchida com o inventário da prateleira, dizendo também quanto o app
   contou.
3. **Given** a pergunta na tela, **When** a pessoa confirma, **Then** a
   captura fica gravada com a prateleira, o inventário daquele momento e a
   resposta.
4. **Given** uma prova exportada, **When** a pessoa roda o relatório, **Then**
   vê, para cada captura, a prateleira, a contagem do app, o gabarito e se
   bateu; o total de exatas; e as prateleiras cadastradas que ficaram sem
   captura.
5. **Given** uma prova exportada, **When** a pessoa roda o comando do
   Roboflow, **Then** ele recusa e diz por quê.

---

### User Story 3 - As prateleiras e o guia de variações (Priority: P3)

Na aba Medição, a pessoa cadastra as prateleiras da casa — um nome e o número
de livros do inventário —, corrige o número quando muda livros de lugar,
renomeia e apaga. Na câmera, numa sessão de treino, o guia mostra para a
prateleira escolhida as nove combinações de distância e ângulo na luz da
sessão, com as que já têm foto marcadas; ela escolhe a próxima variação
tocando no próprio guia. Na Medição, cada prateleira mostra quantas das nove
já tem de dia e de noite, e as fotos sem livros mostram quantas faltam para a
meta.

**Why this priority**: as US1 e US2 precisam de prateleiras para escolher; o
guia é o que garante a variedade das fotos sem a pessoa ter de anotar.

**Independent Test**: cadastrar três prateleiras, fazer uma sessão de treino
de dia com cinco variações de uma delas e apagar a sessão do aparelho. O guia
mostra as cinco, e continua mostrando depois de apagar.

**Acceptance Scenarios**:

1. **Given** a Medição, **When** a pessoa cadastra uma prateleira com nome e
   número, **Then** ela aparece na lista e para escolher na câmera.
2. **Given** uma prateleira cadastrada, **When** a pessoa muda o número,
   **Then** as próximas provas usam o número novo, e as já gravadas ficam com
   o de quando foram feitas.
3. **Given** uma sessão de treino com a prateleira escolhida, **When** a
   pessoa olha a câmera, **Then** vê as nove combinações na luz da sessão, as
   que já têm foto marcadas e a escolhida em destaque.
4. **Given** uma captura de treino gravada, **When** a câmera volta, **Then** a
   combinação dela aparece marcada no guia.
5. **Given** sessões de treino apagadas do aparelho, **When** a pessoa olha o
   guia, **Then** as combinações delas continuam marcadas.
6. **Given** uma prateleira apagada, **Then** ela some da lista, da escolha na
   câmera e do guia; as sessões já gravadas guardam o nome dela.

---

### Edge Cases

- **Nenhuma prateleira cadastrada.** No treino, só "sem livros" está
  disponível, e a tela aponta para a Medição. Na prova, capturar não está
  disponível, pela mesma razão.
- **A captura do modo rápido não é gravada** — falta de espaço, como na 007
  (FR-020). Como o resultado não aparece, o aviso fica na câmera, e o guia não
  marca a combinação.
- **A captura falha** — a foto não sai. Nada é gravado, a câmera volta, e o
  aviso diz isso.
- **Endireitamento recusado ou releitura que falha.** Grava-se o que existe,
  como na 007. No pacote, sem recorte, vai a foto inteira daquela captura.
- **"Sem livros" com um livro na foto.** A foto vai sem contorno; cabe à
  pessoa acrescentá-lo no Roboflow ou apagar a imagem.
- **A luz muda no meio da sessão.** A pessoa desliga e liga de novo,
  escolhendo a outra luz.
- **Marcar numa sessão de treino ou de prova.** Continua possível, como na
  007, e a marca guarda a prateleira e a variação escolhidas. Marcas não vão
  para o pacote nem para o relatório.
- **Uma prateleira renomeada.** O guia a segue; as sessões gravadas guardam o
  nome antigo.
- **Sessões gravadas antes desta spec** não têm tipo. Aparecem na lista como
  "sem tipo"; o comando do Roboflow só as aceita quando a pessoa pede
  explicitamente, e o relatório da prova não as aceita.
- **O mesmo zip empacotado duas vezes.** Os nomes das imagens são os mesmos, e
  o Roboflow aponta as repetidas na importação.

## Requirements *(mandatory)*

### Functional Requirements

**Sessão**

- **FR-001**: Ligar o modo coleta MUST pedir o tipo da sessão — treino ou
  prova — e, no treino, a luz — dia ou noite. A sessão MUST guardar os dois,
  e a lista da Medição MUST mostrá-los. A sessão de prova MUST guardar também,
  ao abrir, as prateleiras cadastradas com seus números.
- **FR-002**: Com uma sessão aberta, a câmera MUST mostrar a prateleira
  escolhida e, no treino, a variação; a escolha MUST persistir de uma captura
  para a outra até a pessoa mudá-la.
- **FR-003**: Capturar MUST NOT estar disponível numa sessão de treino sem
  prateleira escolhida — ou "sem livros" — e, com prateleira, sem distância e
  ângulo; nem numa sessão de prova sem prateleira escolhida. A tela MUST dizer
  o que falta.
- **FR-004**: Cada captura e cada marca gravadas MUST guardar a prateleira — o
  identificador e o nome do momento —, a distância e o ângulo, quando houver,
  e a luz e o tipo da sessão. Na prova, MUST guardar também o inventário da
  prateleira no momento da captura.

**Treino**

- **FR-005**: Numa sessão de treino, depois de gravar a captura, o app MUST
  voltar a câmera ao vivo sem mostrar o resultado e sem pedir a contagem real.
  A captura fica "sem resposta".
- **FR-006**: Depois de cada captura de treino, o indicador MUST mostrar se ela
  foi gravada, com a prateleira e a variação; se não foi, por quê.
- **FR-007**: A distância MUST ter três valores — perto, média, longe — e o
  ângulo três — frente, esquerda, direita —, com a descrição de cada um à
  vista da pessoa na hora de escolher.
- **FR-008**: "Sem livros" MUST ser uma escolha fixa no treino, sem distância
  nem ângulo, que não se edita nem se apaga.

**Prova**

- **FR-009**: Numa sessão de prova, a captura MUST mostrar o resultado como
  fora do modo, e a pergunta da contagem real MUST vir preenchida com o
  inventário da prateleira escolhida, dizendo também a contagem do app. O
  resto da pergunta é o da 007: ajustável com +/−, e pode-se pular.

**Prateleiras e guia**

- **FR-010**: A aba Medição MUST permitir cadastrar, renomear, mudar o número
  e apagar prateleiras. Apagar pede confirmação. As prateleiras MUST persistir
  no aparelho, entre sessões e entre aberturas do app.
- **FR-011**: Na câmera, numa sessão de treino com prateleira escolhida, o
  guia MUST mostrar as nove combinações de distância e ângulo na luz da
  sessão, marcando as que já têm captura gravada e destacando a escolhida.
  Escolher a variação MUST ser possível tocando no guia.
- **FR-012**: O guia MUST contar só capturas de treino gravadas, e MUST
  continuar contando-as depois que as sessões forem apagadas do aparelho.
- **FR-013**: A Medição MUST mostrar, por prateleira, quantas das nove
  combinações já têm captura de dia e quantas de noite, e quantas fotos sem
  livros há contra a meta.
- **FR-014**: As combinações, as descrições e a meta de fotos sem livros MUST
  ser ajustáveis sem rebuild nativo, conforme o princípio IV.

**Pacote para o Roboflow**

- **FR-015**: Uma ferramenta fora do app MUST ler um ou mais zips de sessões
  de treino e gerar uma pasta que o Roboflow importa arrastando, com imagens e
  contornos.
- **FR-016**: Para cada captura de treino com livros, a pasta MUST trazer o
  recorte, quando houve, numa imagem que, reduzida ao tamanho que o modelo lê,
  é a mesma que a releitura leu — o recorte sem esticar, centrado, com preto
  em volta —, em resolução maior que a dele, para que se possa marcar.
- **FR-017**: A pasta MUST trazer a foto inteira de uma em cada três capturas
  de cada prateleira, distribuídas entre as variações, e de toda captura sem
  recorte; e a foto de toda captura sem livros. Reduzida como o Roboflow reduz,
  a foto MUST ser a mesma que o modelo leu.
- **FR-018**: Cada imagem de livros MUST levar um contorno em cada livro que o
  app achou nela — inteira, não só a faixa ou o recorte sem margem —, a partir
  das máscaras, com a classe do modelo. Detecções cuja máscara está quase toda
  dentro da de uma detecção mais forte MUST ser descartadas antes. As fotos
  sem livros MUST ir sem contorno.
- **FR-019**: O nome de cada imagem MUST dizer a sessão, o item, a prateleira,
  a variação, a luz e o tipo de imagem, para se poder buscar no Roboflow.
- **FR-020**: A ferramenta MUST recusar sessões de prova sempre, e sessões sem
  tipo a menos que a pessoa peça explicitamente. Marcas MUST NOT ir para a
  pasta.
- **FR-021**: A ferramenta MUST dizer, ao terminar, quantas imagens e quantos
  contornos gerou, por prateleira.

**Relatório da prova**

- **FR-022**: Uma ferramenta fora do app MUST ler um zip de prova e mostrar,
  por captura, a prateleira, a contagem do app, o gabarito e se bateu; o total
  de capturas exatas; e as prateleiras sem captura naquela prova — as que a
  sessão registrou como cadastradas ao abrir.

**O que não muda**

- **FR-023**: Com o modo desligado, e na prova, o app MUST contar, mostrar e
  guardar no histórico exatamente como antes. Nenhuma regra de contagem muda.
- **FR-024**: O formato do zip MUST continuar o da 007, com os campos novos
  descritos no `FORMAT.md` que vai dentro dele.
- **FR-025**: Nenhum pixel MUST atravessar para o JavaScript (princípio II):
  prateleira, variação, tipo e luz são texto e números.
- **FR-026**: O recorte gravado MUST ser, em resolução cheia, a imagem que a
  releitura leu — inclusive a região fora da foto, que ela vê preta. Para as
  sessões gravadas antes, a ferramenta do pacote MUST refazer essa região a
  partir da geometria gravada.

### Key Entities

- **Prateleira**: um lugar da casa com nome e o número de livros do
  inventário. Vive no aparelho, fora das sessões.
- **Sem livros**: a escolha fixa para fotos de fundo, sem número.
- **Variação**: a distância e o ângulo de uma captura de treino, mais a luz
  da sessão. São 18 por prateleira: 3 distâncias, 3 ângulos, 2 luzes.
- **Tipo da sessão**: treino ou prova. Sessões anteriores a esta spec não têm.
- **Guia**: para cada prateleira e cada variação, se já existe captura de
  treino gravada. Sobrevive às sessões apagadas.
- **Pacote para o Roboflow**: a pasta gerada fora do app — imagens com
  contornos e nomes que dizem de onde vieram.
- **Relatório da prova**: a contagem do app contra o inventário, por captura e
  por prateleira.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Numa sessão de treino de 20 capturas seguidas, a câmera volta ao
  vivo em menos de 1,5 s do toque em todas, e volta a 60 fps depois de cada
  uma, medido pela telemetria.
- **SC-002**: O zip dessa sessão — com pelo menos duas capturas sem livros —
  vira pacote com o recorte de 100% das capturas com recorte, a foto inteira
  de uma em cada três por prateleira e a de 100% das sem livros, cada uma com
  o nome certo. Importado no Roboflow, nenhuma imagem é recusada, e em 10
  imagens sorteadas os contornos caem sobre os livros.
- **SC-003**: Em 100% das imagens do pacote, reduzir a imagem ao tamanho que o
  modelo lê reproduz o quadrado que o app gravou para aquela leitura — mesma
  posição e escala do conteúdo, e a imagem igual a menos da compressão e de um
  leve desvio de tom —, conferido pela própria ferramenta.
- **SC-004**: A ferramenta do pacote recusa 100% das sessões de prova, e das
  sem tipo quando a pessoa não pede.
- **SC-005**: Numa prova de todas as prateleiras cadastradas, duas capturas
  cada, 100% das perguntas vêm preenchidas com o inventário da prateleira
  escolhida, e o relatório traz todas as capturas e nenhuma prateleira faltando.
- **SC-006**: Depois de duas sessões de treino, uma de dia e uma de noite, o
  guia marca exatamente as combinações das capturas gravadas, e continua igual
  depois de apagar as duas sessões.
- **SC-007**: Com o modo desligado, e numa prova, o resultado continua visível
  em menos de 1,5 s do toque (SC-001 da 004), com a mesma contagem de antes.

## Relação com as specs anteriores

- **007, modo coleta.** É a base: sessões, zip, marcas, a pergunta da
  contagem. Ganha o tipo, a luz, a prateleira e a variação, e o treino deixa de
  mostrar o resultado e de perguntar. E um conserto: onde o recorte endireitado
  sai da foto, a 007 gravava a região sem imagem em branco, e a releitura a vê
  preta. O recorte gravado passa a ser preto ali também.
- **004, captura.** Fora do treino, o fluxo é o mesmo. No treino, a captura
  roda inteira — foto, geometria, recorte e releitura — e só a tela do
  resultado é pulada.
- **006, releitura.** Nada muda. O pacote reproduz a imagem que ela lê.
- **002, geometria do dataset.** O dataset foi montado no Roboflow esticando
  as fotos para 640×640. O pacote parte dessa mesma redução.

## Assumptions

- **A regra de contagem** está em `models/regra-de-contagem.md`: livro, mangá
  e HQ; o estojo não conta, os livros dentro dele sim; um livro, um contorno.
  Ela vale para o inventário, para a resposta da prova e para toda correção no
  Roboflow.
- **As variações.** Perto: só um pedaço da prateleira, livros grandes na tela.
  Média: a prateleira inteira dentro da faixa. Longe: a prateleira inteira
  pequena, com as vizinhas aparecendo. Esquerda e direita: uns 20 a 30° de
  lado. Com umas 15 prateleiras, as 18 variações dão umas 270 capturas.
- **A meta de fotos sem livros** começa em 30 — cerca de 10% das capturas,
  como recomenda a Ultralytics.
- **O projeto do Roboflow** é o do dataset atual, com a classe `book` e a
  redução esticada para 640×640. Se a redução mudar lá, a equivalência do
  SC-003 deixa de valer.
- **A pessoa corrige os contornos no Roboflow.** O pacote só poupa o desenho
  do zero: ele traz o que o app achou, com os erros do app.
- **As ferramentas do pacote e do relatório rodam no Linux do autor**, como o
  verificador da 007, e não fazem parte do app.
- **Fora de escopo:** tirar as duplicatas da contagem do app (spec própria,
  medida na prova); subir para o Roboflow pela API; marcas no pacote; rodar ou
  comparar modelos na prova; o roteiro de treino no Colab; detectar distância,
  ângulo ou luz automaticamente; editar a resposta depois.

## Decisões adiadas

- **Quanto de sobreposição de máscara descarta um contorno, e a confiança
  mínima dos contornos.** Começam em 80% e no limiar da sessão (0,25), os
  números que as coletas de 20/10 sustentam. Ajustar depois do primeiro pacote,
  pelo que a pessoa teve de apagar e de desenhar.
- **Uma foto inteira em cada três.** Ajustar se o trabalho de corrigir as
  fotos inteiras pesar, ou se o passo que acha os livros na foto continuar
  errando na prova.
- **A meta de 30 fotos sem livros.** Ajustar pelo que a prova mostrar de
  não-livros contados.
