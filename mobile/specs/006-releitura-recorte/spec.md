# Feature Specification: Releitura do recorte

**Feature Branch**: `mobile/006-releitura-recorte`

**Created**: 2026-09-27

**Status**: Draft

**Input**: User description: "Gostaria que a releitura fosse em cima da imagem já endireitada, já cortada, com o fundo preto no quadrado. Depois de clicar em capturar, a imagem vai ser endireitada e cortada e exibida na tela. Quero que depois disso, no final do pipe de captura, rode por último uma leitura do modelo sobre a imagem, e apenas essas informações serão consideradas como dados da leitura pós-captura." Nas respostas antes desta spec: o filtro das bordas fica ligado; as divisões são recalculadas a partir da releitura; "não existe caixa que conta mas não aparece — só existe caixa que aparece no frame da releitura"; e o FR-004 da 004 é revogado.

> **Terceiro marco de produto.** A 004 contou pela foto, e a 005 disse o que
> contar. A 006 faz a contagem ser a da imagem que a pessoa está vendo: o
> recorte endireitado, no quadrado, lido por último.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - O resultado é a leitura da imagem na tela (Priority: P1)

A pessoa captura. A imagem endireitada e recortada aparece no quadrado, com
preto em volta, como hoje. Por último, o modelo lê exatamente esse quadrado, e
o que ele encontra é o resultado: a contagem, as caixas e as máscaras que a
pessoa liga e desliga sobre a imagem, e o que vai para o histórico.

**Why this priority**: é o pedido. Sem isto, a contagem continua vindo de outra
imagem — a foto inteira, torta — e as caixas não existem sobre o resultado.

**Independent Test**: capturar uma prateleira e contar as caixas sobre o
resultado: são o número mostrado, e esse número fica a ±10% da contagem manual.

**Acceptance Scenarios**:

1. **Given** uma captura endireitada na tela, **When** a leitura termina,
   **Then** caixas e máscaras aparecem sobre a imagem, cada uma sobre um livro,
   e a contagem é o número de caixas.
2. **Given** o resultado na tela, **When** a pessoa desliga e religa as caixas
   ou as máscaras, **Then** a mudança aparece na hora.
3. **Given** a faixa vertical sobre uma coluna, **When** a pessoa captura,
   **Then** as fatias dos livros vizinhos que a margem do recorte mostra não
   contam nem aparecem.
4. **Given** o resultado, **When** a pessoa salva, **Then** o histórico guarda
   a contagem da releitura e registra que ela veio da releitura.
5. **Given** o resultado, **When** a pessoa volta à câmera, **Then** nenhuma
   caixa, máscara ou divisão do resultado aparece sobre a imagem ao vivo.
6. **Given** uma captura em que o endireitamento foi recusado e a tela mostra a
   imagem inteira, **When** o resultado aparece, **Then** a contagem é a da
   foto — que já é a leitura da imagem na tela — e o resultado diz isso.

---

### User Story 2 - As divisões da releitura (Priority: P2)

As divisões entre livros vizinhos saem das caixas da releitura, fileira a
fileira. Por isso caem entre as caixas que estão na tela.

**Why this priority**: sem as divisões o resultado já vale — contagem e caixas.
Mas divisões vindas de outra leitura ficariam desencontradas das caixas, e a
tela mostraria duas leituras ao mesmo tempo.

**Independent Test**: ligar caixas e divisões juntas e conferir que cada
divisão está entre duas caixas vizinhas da mesma fileira.

**Acceptance Scenarios**:

1. **Given** o resultado endireitado, **When** as divisões aparecem, **Then**
   cada uma está entre duas caixas vizinhas da mesma fileira.
2. **Given** uma captura só girada, sem correção de perspectiva, **When** o
   resultado aparece, **Then** as divisões aparecem também.
3. **Given** duas fileiras no recorte — a faixa vertical sobre uma coluna —,
   **When** o resultado aparece, **Then** cada fileira tem as suas divisões e a
   sua contagem.

---

### Edge Cases

- **Livro cortado pela margem do recorte.** A margem existe para a base dos
  livros aparecer inteira (004), e mostra pedaços do que está em volta. Conta
  só quem tem a maior parte da caixa dentro do recorte sem a margem; os outros
  não contam nem aparecem.
- **A releitura não encontra nenhum livro.** O resultado diz zero, vindo da
  releitura. Não pede a contagem da foto emprestada, e não diz "nenhum livro na
  faixa": a faixa tinha livros, a releitura é que não os achou.
- **Endireitamento recusado sem recorte.** A tela mostra a imagem inteira, que
  é exatamente o que a foto leu. A leitura da foto, filtrada pela faixa, é o
  resultado.
- **Diagnóstico ligado.** A tela mostra um desenho, não o recorte. A releitura
  lê o recorte do mesmo jeito, para a contagem não mudar com o modo, e nada é
  desenhado sobre o diagnóstico.
- **A sessão termina durante a releitura** — a aba trocada, o app em segundo
  plano. Nada da releitura aparece depois.
- **A releitura falha.** O resultado sai da leitura da foto e diz isso, em vez
  de perder a captura.
- **Faixa desligada.** O recorte é o de todos os livros, e a releitura funciona
  igual.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Depois que o resultado endireitado e recortado estiver na tela, o
  sistema MUST executar, por último, uma leitura do modelo sobre exatamente a
  imagem exibida: o recorte encaixado no quadrado, centrado, com preto no resto.
- **FR-002**: Os dados da leitura pós-captura — contagem, caixas, máscaras,
  fileiras, deitados e divisões — MUST vir só dessa leitura. A leitura da foto
  serve para achar os livros, endireitar e recortar.
- **FR-003**: A releitura MUST usar os mesmos limiares de detecção do ao vivo.
- **FR-004**: Um livro MUST contar só quando a maior parte da sua caixa estiver
  dentro do recorte sem a margem. Os outros não contam nem aparecem.
- **FR-005**: Toda caixa que conta MUST aparecer no resultado, e nenhuma outra
  MUST aparecer: o número de caixas na tela é a contagem.
- **FR-006**: Caixas e máscaras MUST poder ser ligadas e desligadas sobre o
  resultado, com efeito imediato.
- **FR-007**: As divisões MUST ser recalculadas a partir das caixas da
  releitura, por fileira, sempre que a tela mostrar um recorte — endireitado ou
  só girado.
- **FR-008**: Quando a tela não mostrar um recorte, a leitura da foto, filtrada
  pela faixa, MUST continuar sendo o resultado: ela já é a leitura da imagem
  exibida.
- **FR-009**: O resultado MUST dizer de qual leitura veio a contagem, e o
  histórico MUST guardar isso junto com ela.
- **FR-010**: No modo diagnóstico, a releitura MUST rodar sobre o recorte do
  mesmo jeito, e nada dela MUST ser desenhado sobre o diagnóstico.
- **FR-011**: Voltar à câmera ou encerrar a sessão MUST NOT deixar caixa,
  máscara ou divisão do resultado sobre a imagem ao vivo — inclusive quando a
  releitura terminar depois.
- **FR-012**: Se a releitura falhar, o resultado MUST sair da leitura da foto e
  dizer isso (FR-009).
- **FR-013**: Nenhum pixel da releitura — do quadrado ou das máscaras — MUST
  atravessar para o JavaScript, conforme o princípio II.
- **FR-014**: Ligar e desligar a releitura e a fração da regra das bordas MUST
  ser ajustáveis sem rebuild nativo, conforme o princípio IV.

### Key Entities

- **Quadrado da releitura**: o recorte encaixado no quadrado, centrado, com
  preto no resto. É o que a tela mostra, e é o que o modelo lê.
- **Releitura**: as detecções sobre o quadrado — caixas e máscaras — e o que
  sai delas: contagem, fileiras, divisões e deitados.
- **Recorte sem a margem**: a extensão dos livros da faixa, onde a maior parte
  de uma caixa precisa estar para contar.
- **Origem da contagem**: releitura ou foto. Vai no resultado e no histórico.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Em 10 capturas de uma prateleira, com a faixa sobre ela, a
  contagem do resultado fica dentro de ±10% da contagem manual nas 10.
- **SC-002**: Em toda captura com recorte, o número de caixas na tela é igual à
  contagem mostrada.
- **SC-003**: Em 10 capturas com a faixa vertical sobre uma coluna, nenhuma
  fatia de livro vizinho conta.
- **SC-004**: A releitura não acrescenta espera. O resultado continua visível
  em menos de 1,5 s do toque (SC-001 da 004), e as caixas aparecem até o fim da
  transição nas 10 capturas do SC-001.
- **SC-005**: Em 10 capturas com caixas e divisões ligadas, toda divisão está
  entre duas caixas vizinhas da mesma fileira.
- **SC-006**: Com a faixa desligada, a contagem do resultado fica dentro de
  ±10% da contagem mediana ao vivo na mesma cena — o SC-004 da 004, agora
  medido com a releitura.
- **SC-007**: Em 10 voltas à câmera, nenhuma caixa, máscara ou divisão do
  resultado aparece sobre a imagem ao vivo.

## Relação com as specs anteriores

- **Revoga o FR-004 da 004** ("uma inferência sobre a foto, sem
  ladrilhamento"). A captura passa a ter duas leituras: a da foto, que acha os
  livros, endireita e recorta, e a do recorte na tela, que é o resultado.
  Ladrilhamento continua fora.
- **Redefine o SC-004 da 004** e, por ele, o SC-006 da 005: a contagem da
  captura comparada com a mediana ao vivo passa a ser a da releitura.
- **Estende uma regra da 004**: "uma imagem na tela, e as detecções são dela"
  passa a valer também para a imagem endireitada. Até aqui ela recebia só as
  divisões, vindas da foto.

## Assumptions

- **O quadrado é o que a tela mostra, com preto em volta.** Decisão do autor.
  A tela já encaixa o recorte no quadrado do preview; a releitura lê esse mesmo
  enquadramento.
- **A leitura da foto continua**, filtrada pela faixa: sem ela não há livros
  para endireitar nem recortar. Ela só deixa de ser o resultado.
- **A margem do recorte continua**, porque é ela que garante a base dos livros
  inteira (004). A regra das bordas é o que a impede de contar.
- **Geometria e faixa continuam vindo da foto.** Endireitado ou não, o motivo
  da recusa, as confianças, a gravidade e os livros fora da faixa descrevem
  como a imagem foi feita e o que a faixa deixou de fora — não são leitura do
  resultado.
- **Falha da releitura cai na foto** (FR-012). É uma leitura a confirmar com o
  autor: perder uma captura boa por um erro raro pareceu pior que mostrar a
  contagem da foto dizendo de onde ela veio.
- **Fora de escopo, por decisão do autor em 27/09:** ladrilhamento, entrada
  larga, retreino, preenchimento diferente do preto e comparação entre as duas
  leituras.
- **Arrasto e ampliação do resultado**, adiados na 004 "para a releitura",
  continuam fora. O recorte aparece inteiro, reduzido para caber — que é
  exatamente o quadrado que a releitura lê.

## Decisões adiadas

- **A fração da regra das bordas.** Começa em 0,5 — a maior parte, como a regra
  da faixa (005). Ajustar se o SC-003 falhar.
