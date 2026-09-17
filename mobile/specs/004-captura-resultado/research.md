# Fase 0 — Pesquisa

Quatro incógnitas. A R15 é a que decide se o marco entrega algo confiável.

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
