# Quickstart — validar o overlay

Build e instalação seguem o [marco 1](../001-coreml-proof/quickstart.md).

## O que olhar, em ordem

**1. As caixas caem sobre os livros?** É o SC-004 e o teste do mapeamento de
coordenadas. Deslocamento sistemático — tudo para a direita, ou tudo para
baixo — indica erro de geometria, não de modelo.

Como o preview mostra o buffer que o modelo recebe, o mapeamento é 1 para 1. Se
estiver errado aqui, o erro é simples e está no desenho.

**2. As máscaras seguem a silhueta?** Uma máscara idêntica ao retângulo
significa que os coeficientes não estão sendo aplicados. Uma máscara ruidosa
ou deslocada indica erro na composição.

**3. O overlay parece fluido?** 🚦 **Esta é a observação que decide o marco 4.**

Com inferência a 60 fps, cada frame tem resultado próprio e não há intervalo a
disfarçar. Se as caixas parecerem estáveis e coladas nos objetos, o marco 4
encolhe para rede de segurança térmica. Se tremerem, o tracker se justifica.

Olhe com o aparelho na mão, em movimento normal — não apoiado.

**4. Quanto custou?** Comparar com o marco 2 na mesma cena:

| | marco 2 |
|---|---|
| fps processados | 60,00 |
| ponta-a-ponta | 39,6 ms |

O portão: fps igual, e2e não mais que 15% acima. O custo do desenho aparece
como estágio próprio.

**Medir em Release.** O marco 2 mostrou que Debug infla laço apertado em ~35×, e
a composição de máscara é exatamente isso.

## Comparação com e sem overlay

Na mesma cena e mesmo apoio, três sessões curtas: sem overlay, só caixas,
caixas e máscaras. A diferença entre elas é o custo real de cada camada.
