# Fase 0 — Pesquisa

---

## MEDIÇÃO — caixas, Release, 16/09/2026

`medicoes/2026-09-16-caixas-release.json` — 100 s, 5998 de 5999 frames.

| | marco 2 | agora | |
|---|---|---|---|
| fps processados | 60,00 | **60,00** | mantido |
| ponta-a-ponta | 39,63 ms | **36,28 ms** | −8% |
| transformação | 1,50 ms | 1,43 ms | |
| inferência | 6,50 ms | 6,50 ms | |
| decodificação | 3,48 ms | **0,10 ms** | |
| desenho | — | **0,30 ms** | |
| trabalho/frame | 11,48 ms | **8,03 ms** | folga de 8,64 ms |

Térmico `nominal` o tempo todo, bateria 80% → 80% em 100 s.

### Três leituras

**1. A hipótese do Debug se confirmou exatamente.** A decodificação caiu de
3,48 para **0,10 ms** — os ~35× previstos. Era `-Onone` num laço sobre 8400
âncoras, e nada mais.

**2. A hipótese sobre a inferência caiu.** `inferMs` ficou em **6,50 ms nos
dois builds**. Os 2,1× contra os 3,1 ms do marco 1 **não eram artefato de
build** — são reais e persistem em Release.

A diferença entre os dois contextos: o marco 1 media 100 execuções em laço
fechado sobre **um único buffer reutilizado**; aqui cada frame traz um buffer
diferente de um pool, e a inferência divide o aparelho com a transformação
(Core Image sobre Metal) e com a composição do preview.

**Hipótese não verificada:** contenção de GPU entre a transformação e o
caminho do Core ML. Testável desligando a transformação e alimentando o modelo
com um buffer fixo durante a sessão ao vivo. Fica registrado como pergunta
aberta — **não vale otimizar sem saber**, e 6,5 ms cabem folgados no orçamento.

**3. O desenho é praticamente gratuito.** 0,30 ms, e num `CADisplayLink` na
thread principal — **não consome o orçamento do frame**. O e2e até caiu, porque
a decodificação otimizada compensou com sobra.

### Portão do marco

| | | |
|---|---|---|
| SC-001 · 60 fps mantidos | ✅ | 60,00 |
| SC-002 · e2e +15% máx | ✅ | **caiu** 8% |
| SC-003 · custo do desenho reportado | ✅ | 0,30 ms |
| SC-004 · caixas sobre os objetos | ✅ | confirmado visualmente |
| SC-005 · máscaras | ⬜ | fase 4, não implementada |

---

## 🚦 T013 — o overlay é fluido. O marco 4 encolhe.

Observado com o aparelho na mão, em movimento: **fluido o tempo todo**, caixas
coladas nos objetos, cores estáveis entre vizinhos.

Isto responde a decisão adiada da spec. A arquitetura previa, no marco 4,
rastreador, filtro de Kalman e compensação de movimento — tudo para **tornar
convincente o intervalo entre detecções**. A 60 fps esse intervalo é de um
frame, e não há o que disfarçar.

**O marco 4 deixa de ser necessário para fluidez.** O que sobra dele:

- **identidade estável** — hoje a cor vem da posição e troca ao cruzar célula
  (R11). Um rastreador daria id estável e cor fixa por objeto.
- **rede de segurança térmica** — se a cadência cair, a predição volta a fazer
  falta. Mas isso é o marco 6, e só se a medição mostrar queda.

A recomendação é **não construir o marco 4 como estava**, e reavaliar depois das
máscaras: se a cor piscando incomodar, um rastreador simples resolve — sem
Kalman, sem compensação de movimento.

---

## MEDIÇÃO FINAL — caixas e máscaras, Release, 17/09/2026 ✅ PORTÃO ATINGIDO

`medicoes/2026-09-17-mascaras-release.json` — 31 s, **1842 de 1842 frames**.

| | sem overlay | só caixas | caixas + máscaras |
|---|---|---|---|
| fps processados | 60,00 | 60,00 | **60,00** |
| ponta-a-ponta | 39,63 ms | 36,28 ms | **36,43 ms** |
| desenho | — | 0,30 ms | **2,02 ms** |
| trabalho/frame | 11,48 ms* | 8,03 ms | **8,22 ms** |

\* em Debug; os demais em Release.

**As máscaras custam ~1,7 ms de desenho** — e o desenho roda no `CADisplayLink`,
na thread principal, **fora do orçamento do frame**. O trabalho da fila da
câmera praticamente não mudou: 8,03 → 8,22 ms.

Térmico `nominal` do início ao fim, bateria 55% → 55%, fps 60,0 → 60,0.

**A escolha do Accelerate se justificou.** Metal não foi necessário: compor na
resolução dos protótipos e deixar o compositor ampliar resolveu, como a R10
previa. A rota Metal fica disponível e não foi paga.

### Portão

| | | |
|---|---|---|
| SC-001 · 60 fps mantidos | ✅ | 60,00, 1842 de 1842 frames |
| SC-002 · e2e +15% máx | ✅ | 36,43 ms, **abaixo** da linha de base |
| SC-003 · custo do desenho reportado | ✅ | 2,02 ms |
| SC-004 · caixas sobre os objetos | ✅ | confirmado |
| SC-005 · máscaras seguem a silhueta | ✅ | confirmado |
| SC-006 · alternância consistente | ✅ | |

### Duas observações para os próximos marcos

**`instanceCount` chegou a 104.** A mediana é 20, mas houve cena com mais de
cem instâncias, e o `drawMs` subiu a 4,71 ms nesses momentos. O custo do desenho
escala com a contagem — hoje sobra folga, mas é o primeiro lugar onde um limite
de instâncias desenhadas faria falta.

**A inferência subiu de 6,55 para 7,18 ms** entre o início e o fim dos 31
segundos. Está dentro da tolerância, mas é a primeira vez que o número sobe.
Sessão longa diria se é tendência ou ruído.

---

## R10 — Custo de compor as máscaras

**A conta.** Máscara = coeficientes × protótipos. Para N instâncias:
`[N, 32] × [32, 25600]`. Com N=24, são **19,6 milhões de multiplicações por
frame**, e a 60 Hz isso é 1,2 GFLOP/s.

**Direção.** `cblas_sgemm` do Accelerate. É exatamente a forma de uma
multiplicação de matrizes densa, o Accelerate usa SIMD e os núcleos de
desempenho, e 19,6 M de operações é trabalho pequeno para ele.

**Como fechar.** A telemetria reporta o custo do desenho à parte (FR-006). Se
passar de ~2 ms, a rota é Metal.

**Nota sobre a medição.** O marco 2 mostrou que build Debug infla laço apertado
em ~35×. Uma composição que pareça cara em Debug pode ser barata em Release —
**medir em Release antes de trocar de rota**.

---

## R11 — Cor estável sem rastreamento

**O problema.** O FR-004 pede cor distinta para objetos adjacentes. O caminho
óbvio — cor por índice na lista — **pisca**: a ordenação vem do escore, que
muda a cada frame, e livro nenhum fica com a mesma cor dois frames seguidos.

Identidade estável é trabalho de rastreador, e rastreador é o marco 4, que este
marco existe em parte para questionar.

**Direção.** Cor derivada da **posição** do objeto: função determinística do
centro da caixa, quantizado. Enquanto o objeto não se move muito, a cor é a
mesma. Dois livros lado a lado caem em células diferentes e recebem cores
diferentes.

**O que isso não resolve.** Um objeto atravessando a fronteira entre duas
células troca de cor. É aceitável aqui: o marco não promete identidade estável,
e se incomodar é argumento a favor do marco 4 — que é justamente o dado que
estamos buscando.

---

## R12 — O desenho pode entrar no caminho crítico

**O risco.** A `PreviewView` recebe buffers da fila da câmera, e a mesma fila
roda a inferência. Se o desenho bloquear essa fila, o princípio I cai no
primeiro marco em que existe desenho.

**Direção.** O nativo **publica** o último resultado e segue. As camadas são
atualizadas na thread principal, e o Core Animation compõe no ritmo do display.
A inferência nunca espera o desenho.

**A consequência desejada do FR-009.** Se uma inferência falhar ou demorar, o
overlay continua mostrando o último resultado em vez de apagar. Sumir é pior que
atrasar.

---

## R13 — Máscaras sobrepostas

**O problema.** Livros adjacentes disputam pixels na fronteira. Se a regra
depender da ordem de chegada, a fronteira cintila entre frames.

**Direção.** Determinística: em pixel disputado, vence a instância de maior
confiança. Como a confiança de cada detecção é estável entre frames, a fronteira
também é.

---

## Já decidido, sem pesquisa

| Decisão | Valor |
|---|---|
| Onde desenhar | nativo, Core Animation sobre a `PreviewView` |
| Resolução das máscaras | 160×160, ampliada pelo compositor |
| Skia / Reanimated | fora do projeto |
| Suavização e rastreamento | fora deste marco, de propósito |
| Mapeamento de coordenadas | 1 para 1 — herança do preview do marco 2 |
