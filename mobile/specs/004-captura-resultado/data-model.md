# Fase 1 — Modelo de dados

## Captura

O que existe entre o toque e o resultado. Vive inteira no nativo.

| Atributo | Descrição |
|---|---|
| foto | imagem em resolução máxima. **O maior dado que o app já manipulou** — não atravessa a fronteira |
| instâncias | detecções da foto, com máscara |
| geometria | o quadrilátero estimado e sua confiança |
| aplicada | se a correção foi usada ou recusada |

---

## Geometria da estante

| Atributo | Descrição |
|---|---|
| quadrilátero | quatro cantos, no espaço da foto |
| confiança | 0 a 1, combinando os sinais da R15 |
| motivo da recusa | texto legível, quando abaixo do limiar |

**O motivo é para a tela, não para o log.** "Poucos livros para estimar a
perspectiva" diz à pessoa o que fazer diferente; "confiança 0.31" não diz nada.

---

## Resultado

O que a pessoa vê e pode salvar.

| Atributo | Descrição |
|---|---|
| imagem | recortada e, se aplicável, endireitada |
| contagem | número de objetos |
| divisões | posições das fronteiras entre objetos adjacentes |
| endireitado | se a correção foi aplicada |
| capturadoEm | data |

---

## Entrada de histórico

| Atributo | Descrição |
|---|---|
| id | identificador |
| arquivo | caminho da imagem no aparelho |
| contagem, endireitado, capturadoEm | do resultado |

**Imagens em arquivo, índice em JSON.** Guardar imagem dentro do índice o faria
crescer sem limite e tornaria a listagem lenta — o problema clássico de misturar
metadado com conteúdo.
