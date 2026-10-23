# Regra de contagem

Decidida pelo autor em 20/10/2026. Vale para o inventário, para o gabarito de
toda coleta (`truth.json`) e para toda marcação de treino no Roboflow. Uma
marcação que fuja dela ensina a dúvida ao modelo.

**O que é livro:** livro, mangá e HQ. Nada mais — revista, caderno, agenda,
pasta, caixa e enfeite não contam, mesmo com cara de livro.

**Duas ideias:**

1. **Só conta o que a câmera vê.** Se é preciso lembrar que o livro está ali
   para contá-lo, ele não conta.
2. **Um livro físico é uma contagem e um contorno.** Nunca dois contornos no
   mesmo livro, nunca um contorno pegando dois.

| Caso | Conta? | Como marcar no treino |
|---|---|---|
| Estojo (a caixa da Ferrante) | a caixa não; cada livro com lombada visível dentro dela, sim | nada na caixa; um contorno em cada lombada visível |
| Capa virada para frente (o Crepúsculo) | sim, 1 | um contorno só, lombada e capa juntas |
| Deitado | sim, 1 cada | um contorno em cada um |
| Escondido em parte | sim, se dá para ver que é livro sem adivinhar | um contorno na parte visível |
| Escondido por inteiro | não | nada |
| Cortado na borda da foto | na prova, enquadrar a prateleira inteira, com folga | marcar mesmo assim, na parte visível |
| Parece livro e não é (caixa, vaso, dobradiça, madeira, a peça clara ao lado da luminária) | não | nada, nunca |

**Marcar não é contar.** No treino, toda foto tem **todos** os livros visíveis
marcados — os cortados, os meio escondidos, os de outras prateleiras que
apareçam. Uma foto com livro sem contorno ensina que aquilo não é livro. Quem
decide o que entra na contagem é o app, com a faixa e as bordas.
