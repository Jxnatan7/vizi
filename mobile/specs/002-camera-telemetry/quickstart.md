# Quickstart — medir a sessão de 10 minutos

Build, assinatura e instalação seguem o
[quickstart do marco 1](../001-coreml-proof/quickstart.md), que não muda.

## O protocolo da medição

O resultado só vale se as condições forem registradas. O protótipo web mediu
variação de 20% no mesmo modelo só por temperatura.

1. **Aparelho o mais frio possível.** Se acabou de compilar, assinar e instalar,
   ele não está frio. Esperar.
2. **Fechar os outros apps.** Desligar modo de baixo consumo.
3. **Bateria acima de 50% e sem carregador.** Carregando, a bateria não é
   mensurável e o aparelho esquenta por outro motivo.
4. **Instalar o build Release.** O app avisa na tela se for Debug.
5. **Escolher a transformação** e apontar para uma cena estável, apoiado — dez
   minutos na mão muda o enquadramento e contamina a contagem.
6. **Deixar rodando 10 minutos sem tocar na tela.**
7. **Parar, copiar o JSON** e colar em `specs/002-camera-telemetry/medicoes/`.

## O que olhar primeiro

**O preview, antes de qualquer número.** Ele mostra o que o modelo recebe.

- Imagem deitada → orientação errada (**R9**), e todo o resto da medição é lixo.
- Objetos achatados ou esticados → a transformação não bate com o dataset.
- Laterais da cena faltando → recorte central, pode não ser o que você quer.

Um minuto olhando o preview economiza dez minutos medindo a coisa errada.

## Comparar as três transformações

Antes da sessão longa, três sessões curtas de um minuto, mesma cena, mesmo
apoio, alternando a transformação. Comparar contagem e estabilidade.

Se uma delas ficar perto da contagem do marco 1 sobre a imagem embarcada, é
forte indício de que reproduz o dataset — e o registro do Roboflow confirma.

## Portão

| | |
|---|---|
| **SC-001** | térmico não passa de `fair` em 10 min |
| **SC-002** | latência mediana não cresce mais de 50% |
| **SC-003** | taxa de quadros sem queda sustentada > 20% |
| **SC-005** | e2e mediana < 80 ms |

Se o térmico estourar, **não é falha do marco** — é a resposta que ele foi
construído para dar. Aí a decisão adiada sobre cadência se resolve com número.
