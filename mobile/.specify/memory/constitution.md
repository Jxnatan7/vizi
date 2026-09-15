# Constituição — vizi mobile

App React Native + Expo de detecção e segmentação de objetos em tempo real,
on-device. Esta constituição governa `mobile/`. O projeto `web/` está
**encerrado e congelado**: serve como referência de medição e não recebe
desenvolvimento.

## Princípios fundamentais

### I. O desenho nunca espera a inferência (NÃO-NEGOCIÁVEL)

Câmera, inferência e display são três relógios independentes. O loop de render
roda na frequência do display e desenha um estado **predito**, mantido
continuamente por um filtro. A inferência apenas *corrige* esse estado.

Regras verificáveis:

- Nenhum caminho de código permite que o loop de desenho aguarde, sincronize
  com, ou consulte a conclusão de uma inferência.
- A fila entre captura e inferência tem profundidade máxima 1, com descarte do
  frame mais antigo. Fila que cresce é latência que cresce sem limite.
- Desligar a inferência inteira deve deixar o overlay fluido, apenas
  progressivamente mais impreciso — nunca congelado.

**Por quê:** fluidez é propriedade do relógio do display; precisão é do relógio
da inferência. Acoplar os dois faz o app inteiro rodar na velocidade do modelo,
e nenhum modelo de segmentação roda a 60 Hz num telefone.

### II. Dado grande não cruza a fronteira (NÃO-NEGOCIÁVEL)

Frames, tensores de protótipos e pixels de máscara nascem, vivem e morrem do
lado nativo. Para o JavaScript vai apenas a lista compacta de instâncias.

Regras verificáveis:

- Nenhum `ArrayBuffer` maior que 64 KB atravessa a ponte nativo↔JS por frame.
- Máscaras são compostas em shader e entregues como textura GPU; o que cruza é
  um handle, nunca pixels.
- Protótipos (`[1, 32, 160, 160]`, 3,2 MB em fp32) jamais são serializados.

**Por quê:** serializar um único tensor de protótipos por frame custa mais que a
inferência inteira, e ainda gera pressão de coletor de lixo no caminho quente.

### III. Zero re-render de React no caminho quente (NÃO-NEGOCIÁVEL)

Tudo que se move a 60 Hz vive em `SharedValue` do Reanimated ou do lado nativo.
React desenha apenas o cromo — controles, HUD, navegação.

Regras verificáveis:

- Nenhum `useState` ou store de React é escrito por frame.
- O overlay não re-renderiza como componente React; ele é redesenhado dentro de
  um `useFrameCallback` na UI thread.
- Estado de aplicação (classe ativa, limiar, modo) é escrito uma vez em
  `SharedValue` quando o usuário muda, não lido por frame do React.

**Por quê:** um único re-render por frame no caminho quente consome o orçamento
de 16,7 ms sozinho, e o jank resultante é exatamente o que separa um app premium
de um demo.

### IV. Substrato nativo, política em JavaScript

O código nativo em `modules/` é substrato: capturar frame, rodar modelo,
devolver tensores, expor superfície de desenho. Tudo que se ajusta por
tentativa e erro — tracker, limiares, estilo do overlay, controle adaptativo —
vive em TypeScript.

Regras verificáveis:

- Constante de tuning em Swift ou Kotlin é violação. Elas pertencem ao TS.
- Uma mudança de comportamento perceptível ao usuário não deve exigir rebuild
  nativo, salvo quando tocar captura, modelo ou shader.

**Por quê:** o build nativo roda em CI de runner macOS e a assinatura expira em
7 dias. O ciclo nativo é caro e raro por construção; o ciclo JS é instantâneo.
Esta divisão é a restrição de build transformada em arquitetura.

### V. Cada marco tem portão de saída mensurável

Toda spec corresponde a um marco e declara um portão numérico, verificado no
iPhone 14 Plus físico antes de a spec ser considerada concluída.

Regras verificáveis:

- Uma spec sem portão mensurável não entra em `/speckit-plan`.
- Portão não atingido não é contornado com ajuste de escopo silencioso: ou a
  arquitetura muda, ou o portão é renegociado explicitamente na spec.

## Restrições técnicas

**Stack fixa.** Expo com dev client (nunca Expo Go — não aceita módulo nativo
próprio), `react-native-vision-camera`, `@shopify/react-native-skia`,
Reanimated, e um Expo Module local para inferência.

**Inferência.** Core ML com `computeUnits = .all` no iOS; LiteRT com delegate de
GPU no Android. Interface TypeScript idêntica nas duas plataformas.

**Modelo.** Exportado no Colab a partir de um único `.pt`. **A geometria de
export acompanha a do treino** — hoje 640×640, porque é o formato do dataset.
Entrada retangular casando com o sensor economizaria 25%, mas só é legítima
depois de um retreino nessa proporção: mudar a proporção no export degrada em
silêncio. fp16 como padrão, e **NMS fora do grafo** — NMS embutido empurra
operações para a CPU e arrasta parte da rede junto. Shapes e classes vêm dos
metadados do próprio modelo; nada de shape hardcoded em TypeScript.

**Build.** Continuous Native Generation: `ios/` e `android/` não são
versionados. Toda configuração nativa vive em config plugins no
`app.config.js`. Compilação em GitHub Actions sem assinatura; assinatura local
com `zsign`; instalação com `ideviceinstaller`.

**Plataforma alvo.** iOS é primário (iPhone 14 Plus, A15). Android é
secundário e vem por último — sem aparelho físico, o emulador não mede nada
aproveitável.

**Sem Instruments.** Não há Mac, logo não há Xcode Instruments nem Core ML
Performance Report. A telemetria construída no app é a única visibilidade que
existirá, e por isso ela vem no marco 2, não no fim.

## Fluxo de desenvolvimento

**Uma spec por marco.** Os marcos vêm da arquitetura, em ordem, e cada um é
validável sozinho:

| # | Marco | Portão de saída |
|---|-------|-----------------|
| 1 | Prova de vida do Core ML | inferência < 30 ms no iPhone 14 Plus |
| 2 | Telemetria e câmera ao vivo | `queueDepth` ≤ 1 por 10 min contínuos |
| 3 | Caixas, sem suavização | desenho a 60 fps medido |
| 4 | Os três relógios | overlay fluido com inferência limitada a 10 Hz |
| 5 | Máscaras em shader | composição ≤ 1 ms, sem regressão de e2e |
| 6 | Acabamento e adaptação | 20 min de uso sem degradação perceptível |
| 7 | Android | paridade funcional |

**Ordem é deliberada.** Os marcos 1 e 2 podem matar o projeto e custam poucos
dias. Nada de valor é construído antes de eles passarem.

**Branch por feature**, nomeada `mobile/{número}-{slug}`. O prefixo existe
porque o repositório git é compartilhado com `web/` e o número sozinho não
diria de qual projeto a branch é.

**Ciclo:** perguntar → `/speckit-specify` → `/speckit-plan` → `/speckit-tasks`
→ `/speckit-implement`.

**As dúvidas são resolvidas antes de especificar, não depois.** Toda pergunta
cuja resposta mudaria o escopo, os critérios de aceite ou os requisitos é feita
ao autor do projeto **antes** de a spec ser escrita. Uma spec entregue com
marcador `[NEEDS CLARIFICATION]` é uma spec que não fez o trabalho de perguntar.

`/speckit-clarify` fica disponível como conserto — para quando uma ambiguidade
só aparecer depois — e não como etapa planejada do fluxo.

Isto não proíbe adiar decisão: uma escolha que depende de um número que ainda
não existe deve ser registrada como **decisão adiada** na própria spec, com o
que a destravará. Adiar conscientemente é diferente de não ter perguntado.

## Governança

Esta constituição prevalece sobre preferência pessoal e sobre conveniência de
implementação. Os princípios I, II e III são não-negociáveis: uma violação é
motivo de rejeição, não de discussão de trade-off.

Emendas exigem: a mudança registrada aqui, a justificativa, e a versão
incrementada. Um princípio derrubado por medição deve ser removido
explicitamente — não deixado a apodrecer enquanto o código o ignora.

Princípios IV e V admitem exceção pontual, desde que a exceção seja registrada
na spec que a introduz, com prazo ou condição de remoção.

**Version**: 1.1.0 | **Ratified**: 2026-09-15 | **Last Amended**: 2026-09-15

### Histórico de emendas

- **1.1.0** (2026-09-15) — O fluxo passa a resolver dúvidas *antes* de
  `/speckit-specify`, em vez de depender de `/speckit-clarify` como etapa. A
  versão 1.0.0 tornava `/speckit-clarify` obrigatório no caminho quente, o que
  institucionalizava entregar spec ambígua e corrigir depois. Acrescenta o
  conceito de decisão adiada, para separar "não perguntei" de "depende de um
  número que ainda não existe".
