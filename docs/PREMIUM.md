# Experiência premium — o que falta

Continuação de [PERFORMANCE.md](./PERFORMANCE.md), em outro eixo. Lá o assunto
era **throughput**; aqui é **percepção**. São problemas diferentes e a solução de
um não resolve o outro.

## O limite que não vai sumir

Com o modelo `high` no aparelho alvo:

```
vídeo        60 fps        frame novo a cada 17ms
detecção     2.1 fps       resultado novo a cada ~470ms
latência     ~340ms        o resultado descreve o passado
```

**Não existe overlay preciso a 60 fps com detecção a 2 fps.** O que existe é
overlay *plausível* a 60 fps. Toda esta lista é sobre tornar o intervalo entre
detecções convincente, não sobre encurtá-lo.

Duas coisas foram consertadas antes de escrever isto, porque eram bugs e não
limitações:

- `MAX_EXTRAPOLATION_MS = 150` contra um ciclo de 472ms: a caixa se movia por
  150ms e **congelava por 320ms** até o resultado seguinte, quando saltava.
- A velocidade era descartada quando o intervalo passava de 500ms — a 472ms
  medidos, estava por um fio de zerar a extrapolação inteira.

Os dois eram constantes fixas para uma cadência variável. Agora o tracker mede a
própria cadência e deriva os limites dela.

---

## 1. Compensação de movimento global — o item principal

**O problema:** a máscara é um bitmap estático entre inferências. Por 470ms ela
não se mexe, e então salta. As caixas têm extrapolação por velocidade, mas
velocidade estimada a 2 Hz é ruidosa e não descreve bem um movimento de câmera.

**A observação:** ao varrer uma estante, quase todo o movimento na imagem é
**pan da câmera** — translação global, igual para todos os objetos. E
translação global é ordens de magnitude mais barata de estimar do que detectar
objetos.

**A solução:** estimar o deslocamento (dx, dy) entre frames de vídeo a 60 Hz e
aplicá-lo ao overlay inteiro:

- **Máscara:** um `transform: translate()` na camada. Trabalho de compositor,
  custo zero de repintura. A máscara passa a deslizar com a imagem.
- **Caixas:** somado por cima da velocidade por objeto, que passa a responder só
  pelo movimento *relativo* dos livros.

A infraestrutura já existe: `src/lib/motion.ts` já reduz o frame a 32x32 a cada
60ms para o gating. Estimar translação é buscar o (dx, dy) que minimiza a
diferença nessa mesma imagem reduzida — uma busca de ±6 px em 32x32 são ~170k
operações, na casa de 0.2ms.

**Variante:** o giroscópio (`DeviceMotionEvent`) dá rotação da câmera a 60 Hz+
mais barato e mais preciso que qualquer estimativa por imagem. No iOS exige
`requestPermission()` num gesto do usuário, e só captura rotação — translação do
corpo do aparelho gera paralaxe que o giro não vê. Bom como refinamento depois
que a versão por imagem estiver de pé.

**Impacto esperado:** é a mudança que mais muda a sensação. Sai de "o desenho
está atrasado" para "o desenho gruda na imagem".

---

## 2. Estabilidade: parar de piscar

Os ids chegam a `#700` em minutos. Cada id novo é uma caixa que apareceu do nada
— e cada uma que some é uma caixa que piscou. Isso lê como "instável" mesmo
quando a contagem está certa.

- **Confirmação antes de exibir.** Só desenhar um track depois de ele ser visto
  2 vezes. Custa um ciclo de latência para caixas novas e elimina o falso
  positivo de uma inferência só.
- **Fade in/out de ~150ms** em vez de aparecer e sumir instantaneamente. Aparecer
  é barato de aceitar; sumir é o que chama atenção.
- **Suavizar o tamanho**, não só a posição. Uma caixa cujo tamanho pulsa a cada
  detecção parece barata mesmo bem posicionada. EMA em largura/altura resolve.

---

## 3. Qualidade do desenho

O overlay atual é funcional e tem cara de debug:

- **Espessura fixa de 4px** num canvas de 480x640 que o CSS estica para a tela —
  a linha chega grossa e serrilhada. Escalar com a razão canvas/tela.
- **17 a 27 labels sobrepostos** viram ruído. Opções: mostrar label só nos N
  maiores, só no que estiver sob o dedo, ou nenhum e deixar a contagem no topo
  falar.
- **Cantos em vez de retângulos completos.** Marcadores de canto são a linguagem
  visual de scanner/AR, e tapam menos o conteúdo.
- **Verde puro `#00FF00`** é a cor mais agressiva do gamut. Um verde menos
  saturado com sombra sutil lê como produto em vez de ferramenta.
- **Opacidade de máscara padrão em 1.0** satura tudo. Algo em torno de 0.4-0.5
  mostra a segmentação sem esconder os livros.

---

## 4. Feedback de estado

App premium diz o que está fazendo:

- **Contagem animada** em vez de trocar o número de 17 para 24 secamente.
- **Indicador de varredura** discreto enquanto a detecção roda — hoje não há
  diferença visual entre "processando" e "parado" (o motion gating pode ter
  pausado tudo e nada na tela avisa).
- **Háptico leve** quando a contagem estabiliza num valor novo.

---

## O que não fazer

- **Atrasar o vídeo para interpolar em vez de extrapolar.** Alinharia perfeito —
  e custaria ~470ms de latência na pré-visualização. Mata a sensação de câmera
  ao vivo, que é justamente o que se está tentando comprar.
- **Web Worker.** Já avaliado e descartado em PERFORMANCE.md § E7: a UI não trava
  sem ele.
- **Perseguir 60 fps de detecção.** Não é alcançável e não é necessário — o
  item 1 entrega a sensação sem a taxa.

---

## Ordem sugerida

| # | Item | Esforço | Efeito |
|---|------|---------|--------|
| 1 | Compensação de movimento global (máscara + caixas) | 1-2 dias | **o salto de qualidade** |
| 2 | Confirmação + fade dos tracks | meio dia | fim do piscar |
| 3 | Suavização de tamanho | 1h | acabamento |
| 4 | Espessura, cor, cantos, opacidade padrão | meio dia | cara de produto |
| 5 | Labels sem colisão | meio dia | legibilidade |
| 6 | Contagem animada + háptico + indicador | meio dia | polimento |
| — | Giroscópio como refinamento do item 1 | 1 dia | precisão extra |

Itens 3 a 6 são independentes entre si e do item 1 — dá para intercalar conforme
o gosto. O item 2 fica melhor depois do 1, porque com o overlay grudado na
imagem fica mais fácil enxergar o que ainda pisca.
