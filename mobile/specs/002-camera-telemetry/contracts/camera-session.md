# Contrato — sessão de câmera

A fronteira do marco 2. O que muda em relação ao marco 1: agora há um fluxo
**contínuo**, e a regra de tamanho vale por unidade de tempo, não por chamada.

```ts
startSession(options: SessionOptions): Promise<SessionInfo>
stopSession(): Promise<Session>
setTransform(transform: Transform): Promise<void>

// Evento, ~2 Hz — NÃO por frame.
addListener('onTelemetry', (sample: TelemetrySample) => void)
```

## `SessionOptions`

Política, vinda do TypeScript (princípio IV).

| Campo | Regra |
|---|---|
| `transform` | `'stretch' \| 'centerCrop' \| 'letterbox'` |
| `confidenceThreshold`, `iouThreshold` | mesmos do marco 1 |
| `sampleIntervalMs` | padrão 500. **Nunca menor que 100** |

## O evento é o ponto crítico deste contrato

Um evento por frame a 60 Hz seriam 60 travessias por segundo e 60 re-renders —
violação direta dos princípios II e III. **O nativo agrega e emite a ~2 Hz.**

A contagem na tela é uma amostra do estado, não um espelho dele. Isso é
deliberado: um número que pisca 60 vezes por segundo é ilegível de qualquer
forma.

## Regras invioláveis

1. **Nenhum pixel atravessa.** Nem o frame bruto, nem o transformado. O preview
   é uma view nativa que recebe o buffer sem passar por JavaScript.
2. **Máximo um frame pendente.** Chegando frame novo com a inferência ocupada, o
   pendente é substituído. Fila que cresce é latência que cresce para sempre.
3. **A `TelemetrySample` é pequena por construção** — algumas dezenas de números.
   A 2 Hz, são centenas de bytes por segundo.
4. **A inferência não bloqueia o preview**, e o preview não bloqueia a
   inferência. Caminhos separados sobre o mesmo buffer, com retenção explícita
   em cada um.
5. **`stopSession` devolve a sessão inteira** — é a única travessia grande, e
   acontece uma vez, quando o usuário pede.

## Erros

Falta de permissão, câmera indisponível e falha ao configurar formato retornam
mensagem legível para a tela (herdado do FR-008 do marco 1). Sem console no
aparelho, a string é a única pista.
