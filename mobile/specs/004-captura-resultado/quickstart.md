# Quickstart — validar a captura

Build e instalação seguem o [marco 1](../001-coreml-proof/quickstart.md).
**Medir em Release**, pelas razões de sempre.

## O que olhar, em ordem

**1. A transição começa no toque?** Se houver congelamento antes de a animação
começar, o FR-009 não está sendo cumprido — a animação está esperando a foto.
É o item mais visível e o mais fácil de errar.

**2. A imagem troca sem salto?** A foto em alta resolução substitui o frame
congelado no meio da animação. Se houver piscada ou deslocamento, o
enquadramento das duas não coincide.

**3. As lombadas ficam verticais?** É o SC-003. Fotografe a mesma estante de
frente e a uns 30° e compare.

**4. A recusa funciona?** Force o caso ruim: fotografe três livros, ou de muito
de lado. **O resultado deve aparecer sem endireitar, com aviso.** Endireitar
errado é pior que não endireitar, e este é o teste disso.

**5. A contagem bate?** Compare com a contagem ao vivo na mesma cena (SC-004).
Diferença grande indica que a foto e o frame de vídeo não estão vendo a mesma
coisa — enquadramento, exposição ou formato.

**6. A câmera volta inteira?** Depois de fechar o resultado, a telemetria deve
mostrar 60 fps de novo em menos de 500 ms. Uma sessão que volta degradada é
pior que uma que demora a voltar.

## Calibrar a confiança (R15)

Capturar deliberadamente casos ruins — poucos livros, estante curva, ângulo
extremo — e anotar `geometryConfidence` de cada um. O limiar sai desses
números, não de palpite.

Os mesmos casos valem como registro: uma captura que deveria ter sido recusada
e não foi é o defeito mais grave que este marco pode ter.
