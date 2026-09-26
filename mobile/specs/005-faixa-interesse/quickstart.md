# Quickstart — validar a faixa

Build e instalação seguem o [marco 1](../001-coreml-proof/quickstart.md).
**Medir em Release**, pelas razões de sempre.

## O que olhar, em ordem

**1. A faixa abre no centro?** Ao iniciar a sessão: faixa horizontal no terço
do meio, resto escurecido. Mexer nela, parar a sessão e iniciar de novo: volta
ao centro (FR-002).

**2. A borda cola no dedo?** Arrastar devagar e depressa. Qualquer atraso entre
o dedo e a borda é sinal de que algo passou pelo JavaScript (R18). A tela não
pode rolar junto (R19). É o item mais visível e o mais fácil de errar.

**3. A caixa troca na hora certa?** Levar uma borda devagar sobre um livro: a
caixa acende quando a maior parte dele entra, e apaga quando sai (R21).

**4. Dois dedos.** Pousar o segundo dedo no meio de um arrasto: nada salta.
Afastar e aproximar: espessura e posição juntas. Girar até ficarem lado a lado:
a faixa vira, com um toque na mão. Oscilar perto da diagonal: não tremula.
**SC-004:** dez viradas, dez na primeira tentativa.

**5. Desligar e religar.** Afastar os dedos além da imagem: desliga, com um
toque. Pinçar de novo: a faixa nasce entre os dedos. Pela cápsula: volta onde
estava.

**6. A contagem junto à faixa não pisca** com a faixa parada sobre uma
prateleira (R23).

**7. A captura respeita a faixa.** Numa estante de três prateleiras, com a
faixa na do meio:

- contagem manual da prateleira do meio contra a captura — **SC-001**, ±10%;
- dez capturas, e o recorte mostra só a do meio nas dez — **SC-002**;
- faixa sobre uma parede vazia: o resultado diz "nenhum livro na faixa".

**8. Fluidez.** Trinta segundos manipulando a faixa sem parar, e copiar a
sessão. Nenhuma janela abaixo de 59 fps — **SC-003**. Registrar `drawMs` com e
sem a faixa em movimento.

**9. Desligada, é a 004.** Com a faixa desligada, o SC-004 da 004 na mesma cena
— **SC-006**.

**10. Leitor de tela.** A jornada inteira com o VoiceOver: mover, engrossar,
afinar, virar, desligar, voltar ao centro — sem nenhum gesto de dois dedos
(FR-021, R25).

**11. Diagnóstico.** A foto crua mostra a faixa e marca os livros que ela
descartou (FR-022).

## O teste de uso — SC-005

Três pessoas que nunca viram o app, uma de cada vez, sem nenhuma instrução
além de "conte os livros da prateleira do meio". Cronometrar do primeiro toque
até a faixa cobrir a prateleira. **Duas de três em menos de 20 s.**

Anotar onde cada uma hesitou. É o insumo para a folga da orientação, a
espessura mínima e o desenho da cápsula — os números que a spec adiou.
