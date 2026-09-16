# Fase 0 — Pesquisa

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
