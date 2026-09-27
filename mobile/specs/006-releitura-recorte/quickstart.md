# Quickstart — validar a releitura

Build e instalação seguem o [marco 1](../001-coreml-proof/quickstart.md).
**Medir em Release**, pelas razões de sempre.

## O que olhar, em ordem

**1. As caixas caem sobre os livros?** Capturar uma prateleira de frente, com a
faixa sobre ela. Quando a transição termina, caixas e máscaras aparecem sobre a
imagem endireitada, cada uma sobre um livro. Nenhuma girada, deslocada ou
esticada (R30). O cartão diz "leitura: recorte na tela".

**2. Caixa na tela é caixa contada.** Contar as caixas e comparar com o número
do cartão — **SC-002**. Vale em toda captura com recorte, inclusive nas de
livros com pouca confiança.

**3. Os botões valem no resultado.** Desligar e religar caixas e máscaras com o
resultado na tela: muda na hora (FR-006).

**4. A contagem certa.** Dez capturas da mesma prateleira, contra a contagem
manual — **SC-001**, ±10% nas dez. Anotar o `rereadMs` e o `toque → pronto` de
cada uma — **SC-004**: pronto abaixo de 1,5 s, e releitura abaixo de 600 ms,
para as caixas chegarem com o fim da transição.

**5. As bordas.** Faixa vertical sobre uma coluna, dez capturas: nenhuma fatia
de livro vizinho com caixa — **SC-003**. Olhar também o alto e a base do
recorte, onde aparece a prateleira de cima e a de baixo.

**6. As divisões.** Caixas e divisões ligadas: toda divisão entre duas caixas
vizinhas da mesma fileira — **SC-005**. Com a faixa vertical, cada fileira com
as suas. Uma captura de lado, que caia no recuo de só rotação: as divisões
aparecem também.

**7. A volta.** Dez voltas à câmera: nenhuma caixa, máscara ou divisão sobre o
ao vivo, nem por um quadro — **SC-007**. Trocar de aba com o resultado na tela
e voltar: a câmera nova começa limpa.

**8. Quando a foto é o resultado.** A faixa sobre uma parede vazia: sem livros
na faixa não há recorte, a tela mostra a imagem inteira, e o cartão diz
"nenhum livro na faixa" e "leitura: foto". Uma prateleira com três livros, ao
contrário, ainda tem recorte — só girado —, e é lida pela releitura.

**9. Diagnóstico.** Com o diagnóstico ligado, a mesma prateleira dá a mesma
contagem que sem ele, e nenhuma caixa aparece sobre o desenho (FR-010).

**10. Histórico.** Salvar um resultado e abrir o `index.json`
(`ifuse --documents com.jxnatan7.vizi`): a entrada traz `countSource`.

**11. Faixa desligada.** Com a faixa desligada, a contagem do resultado contra a
mediana ao vivo na mesma cena, ±10% — **SC-006**.
