# Fase 1 — Modelo de dados

## Frame

Uma captura, do sensor ao resultado.

| Atributo | Descrição |
|---|---|
| buffer | pixels, do lado nativo. **Nunca atravessa a fronteira.** |
| presentationTimeStamp | carimbo do próprio frame, dado pela captura |
| sequência | número crescente, para detectar descartes |

**O carimbo é o que torna o FR-009 possível.** Medir a latência a partir do
momento em que o processamento começou esconde justamente o tempo que o frame
passou esperando — que é parte do que o usuário sente.

---

## Transformação de entrada

| Opção | O que faz | Quando é a certa |
|---|---|---|
| `stretch` | 4:3 → 1:1 esticando | se o Roboflow usou *Stretch to*, o padrão dele |
| `centerCrop` | recorta o miolo quadrado | se o Roboflow usou *Fill* |
| `letterbox` | preserva proporção, preenche | se o Roboflow usou *Fit* |

Escolhida em TypeScript e trocável em execução — a comparação é o método, não
uma configuração de conveniência.

---

## Amostra de telemetria

Uma leitura periódica. Emitida ao JavaScript a cada ~500 ms, não por frame.

| Atributo | Descrição |
|---|---|
| t | milissegundos desde o início da sessão |
| fpsCaptured / fpsInferred | quantos chegaram e quantos foram processados |
| transformMs, inferMs, decodeMs | medianas da janela |
| e2eMs | do carimbo do frame até o resultado pronto (**FR-009**) |
| queueDepth, dropped | saúde do descarte |
| thermalState, batteryLevel | o que o marco existe para medir |
| instanceCount | contagem detectada |

---

## Sessão

A série de amostras de uma execução, mais o que a torna comparável com outra.

| Atributo | Descrição |
|---|---|
| startedAt, durationMs | |
| device, os, model | procedência |
| transform | qual estava ativa |
| thermalAtStart, batteryAtStart | **sem isto a sessão não é comparável** |
| samples | a série |
| thermalTransitions | instante de cada mudança de estado (**FR-007**) |

**Regra de fronteira.** Uma sessão de 10 minutos a 2 amostras por segundo são
1200 amostras. Só isso pode crescer sem limite neste marco, então o buffer é
circular e limitado; a exportação avisa se houve truncamento.
