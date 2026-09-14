# Plano de melhoria de performance — vizi

> **Status (14/09/2026):** o plano foi executado até o fim do que era possível
> sem tocar no modelo. Resumo do que sobreviveu ao contato com a medição:
>
> | épico | desfecho |
> |-------|----------|
> | E0 instrumentação | ✅ feito — foi o que invalidou metade do resto |
> | E1 cross-origin isolation | ❌ impossível no iOS (sem relaxed SIMD) |
> | E2 custos por inferência | ❌ descartada inteira (12 ms de 400) |
> | E3 agendamento | ✅ throttle removido (−106 ms/ciclo) + guarda térmica |
> | E4 render desacoplado | ✅ feito — caixas a 60 FPS com predição |
> | E5 inferência adaptativa | ✅ motion gating, limiar calibrado no aparelho |
> | E6 startup | ✅ preload + cache imutável + Service Worker |
> | E7 worker | ⬇ perdeu a justificativa antes de ser construída |
> | E9 LiteRT direto | ⬇ rebaixada (o custo que eliminaria são 13 ms) |
>
> **O que continua na mesa:** `imgsz=320` no export — isoladamente maior que
> tudo acima somado. Os modelos chegaram; ver **Comparação de modelos** abaixo.
>
> **Outro eixo:** throughput acabou; o que limita a experiência agora é
> percepção — ver [PREMIUM.md](./PREMIUM.md).
>
> **Lição transversal:** das 8 hipóteses do plano original, 4 morreram na
> medição e 1 (o throttle) não estava no plano e foi o segundo maior ganho. A
> instrumentação da E0 pagou por si mesma várias vezes.

**Premissa deste documento: o modelo não muda.** `public/models/yolo-seg.tflite`
continua sendo um `yolov8n-seg`, `imgsz: [640, 640]`, float32, 13.3 MB. Os
~272 ms de `speed.inference` no caminho CPU/wasm são tratados como constante.

O que sobra é tudo o que está **em volta** da inferência — e sobra bastante:
o app hoje paga custos evitáveis antes e depois de cada `predict`, roda o wasm
com um núcleo só, e amarra o desenho ao ritmo da inferência.

Estado atual medido no celular (ver **Medições** abaixo): `device cpu`,
`coi não`, 4 núcleos, `infer 279ms`, ciclo de `406ms` — **2.5 fps**.

---

## Medições

### Baseline — 14/09/2026, iPhone / Safari (via ngrok)

| campo | valor |
|-------|-------|
| device | `cpu` |
| coi | **não** |
| núcleos | **4** |
| frame | 480x640 (retrato) |
| boxes | 10 |
| mask | 1228800 / 1228800 |
| pre | 2 ms |
| infer | **279 ms** |
| post | 13 ms |
| draw | 1.0 ms |
| ciclo | **406 ms · 2.5 fps** |

### Medição 2 — mesma sessão, com `extra`/`ocioso` e constraints de câmera

| campo | baseline | medição 2 | |
|-------|----------|-----------|---|
| frame | 480x640 | **640x640** | ⚠️ regressão do `ideal` (ver abaixo) |
| mask | 1228800 | 1638400 | +33% pixels |
| pre | 2 ms | 3 ms | |
| infer | 279 ms | 264 ms | ruído |
| post | 13 ms | 18 ms | acompanha o frame maior |
| draw | 1.0 ms | 1.0 ms | |
| **extra** | — | **8 ms** | leitura de pixels + saída do wasm |
| **ocioso** | — | **106 ms** | throttle + rAF |
| ciclo | 406 ms | 400 ms | 2.5 fps |

**A regressão:** pedir `width: { ideal: 640 }` e `height: { ideal: 640 }` fez o
iOS escolher um modo de captura **quadrado**, 640x640 — 409600 px contra os
307200 px do 480x640 nativo. Corrigido para `max` sem `ideal`, que deixa o UA no
modo natural da câmera dentro do teto.

**O buraco de 111 ms, resolvido: 106 ms são ociosidade deliberada, 8 ms são
trabalho.** Isso fecha duas decisões de uma vez:

- **T2.2 morre.** Entregar `ImageData` pronto ao `predict` economizaria parte de
  8 ms num ciclo de 400 ms. Toda a E2 sai do plano — `pre`, `draw` e `extra`
  somados dão 12 ms.
- **O throttle vira o alvo.** `DETECTION_INTERVAL_MS = 100` custa 26% do ciclo.
  Zerá-lo levaria 400 → ~294 ms, de 2.5 para 3.4 fps.

**Mas não zere ainda.** Esses 106 ms são o único respiro que a main thread tem:
a inferência wasm single-thread bloqueia tudo, e o `isInferring` só impede
concorrência, não bloqueio. Hoje a UI fica com 106 ms de cada 400 ms (26%);
cortando o throttle, com 12 ms de 294 ms (4%) — e o app fica intocável.

A ordem certa é **E1 antes de E3**: com a inferência em ~90 ms, o ciclo vira
~226 ms com 47% de ociosidade, e aí sobra folga de verdade para reduzir o
throttle. Mexer no throttle agora é trocar fps por responsividade, não ganhar as
duas.

### Medição 3 — 14/09/2026, após reverter COOP/COEP

| campo | m2 | m3 | |
|-------|----|----|---|
| frame | 640x640 | 640x640 | ⚠️ o fix de constraint **não** funcionou |
| boxes | 16 | 23 | cena diferente |
| infer | 264 ms | **317 ms** | mesmo modelo, +20% |
| post | 18 ms | 37 ms | acompanha o nº de instâncias |
| ocioso | 106 ms | 107 ms | estável |
| ciclo | 400 ms | 472 ms | 2.1 fps |

**Duas lições:**

1. **As constraints de câmera não funcionam no iOS** — o Safari corta em
   quadrado em vez de preservar o aspecto, tanto com `ideal` quanto com `max`.
   T2.1 revertida; o padrão (480x640) era o melhor.
2. **`infer` varia 264-317 ms entre medições do mesmo modelo.** Provável
   throttling térmico (o aparelho vinha rodando havia meia hora) somado à cena.
   **Isso define o piso de confiança: ganhos abaixo de ~20% não são
   distinguíveis de ruído neste setup.** Para medir algo menor, é preciso
   repetir a medição com o aparelho frio e a mesma cena.

O `ocioso` é a única métrica estável das três medições (106, 107, 107 ms), o que
a torna o alvo mais confiável que sobrou.

### Medição 4 — 14/09/2026, com throttle removido e E4/E6 implementadas

| campo | baseline | agora | |
|-------|----------|-------|---|
| frame | 480x640 | **480x640** | ✅ reversão da T2.1 correta |
| ocioso | 106 ms | **9 ms** | ✅ throttle removido |
| pre | 2 ms | 2 ms | |
| infer | 279 ms | 306 ms | aparelho quente (2h de uso) |
| post | 13 ms | 32 ms | 27 instâncias contra 10 |
| draw | 1.0 ms | 0.0 ms | camada própria, `ImageData` reaproveitado |
| extra | — | 2 ms | era 8 ms |
| ciclo | 406 ms | **351 ms** | 2.5 → 2.8 fps |

O ciclo caiu 14% mesmo com a inferência 10% mais lenta por calor: a ociosidade
de 106 ms virou 9 ms. Com o aparelho frio (infer ~264 ms) o mesmo ciclo daria
~310 ms, ~3.2 fps.

**Furo encontrado na guarda térmica:** `infer` em 306 ms contra 264 ms medidos a
frio, e a linha `térmico` não apareceu. A referência de "aparelho frio" é o
melhor tempo **da sessão**, e o app foi aberto com o aparelho já quente — a
referência nasceu quente. O painel passou a mostrar `min` ao lado de `infer`
para o caso ficar diagnosticável. Persistir o recorde entre sessões traria o
problema oposto (um recorde de um dia frio deixaria a guarda ligada para
sempre), então fica documentado em vez de "consertado" no chute.

### Comparação de modelos (`?model=`)

Três variantes em `public/models`, selecionáveis por query string:

| flag | arquivo | imgsz | dataset |
|------|---------|-------|---------|
| `?model=high` (padrão) | `best-high.tflite` | 640x640 | novo, maior |
| `?model=low` | `best-low.tflite` | 320x320 | novo, maior |
| `?model=v1` | `yolo-seg.tflite` | 640x640 | original |

`high` é o padrão por ser troca like-for-like do modelo antigo: mesmo `imgsz`,
então a única diferença é o dataset. `v1` fica disponível para separar "mudou
por causa do dataset" de "mudou por causa do imgsz" — sem ele, comparar `low`
contra o app de ontem misturaria as duas variáveis.

**Expectativa para `low`:** o custo da inferência é quadrático na resolução de
entrada, então 320 contra 640 são 4x menos trabalho em teoria. Na prática o
ganho é menor, porque `post` (composição da máscara, na resolução do frame) e o
`extra` não encolhem. Com `infer` de ~300ms e o resto do ciclo em ~45ms, um
ganho de 4x na inferência levaria o ciclo de ~350ms para ~120ms — de 2.8 para
~8 fps.

**O que observar além do fps:**

- **Contagem e caixas espúrias.** A 320 o modelo vê menos detalhe; livros finos
  na lateral da estante são os primeiros a sumir.
- **Qualidade da máscara.** Os prototypes caem de 160x160 para 80x80, e o
  upscale até o frame é maior — máscara mais grosseira nas bordas.
- **Estabilidade dos ids.** Se `low` produzir caixas mais estáveis entre frames,
  os ids param de escalar (hoje chegam a #700+ em minutos), e aí vale retomar a
  T4.5.

**Protocolo, dado o ruído medido (±20% por temperatura):**

1. Aparelho o mais frio possível, mesma cena, mesma confiança.
2. Recarregar a página entre variantes — o modelo é carregado uma vez por sessão.
3. Comparar `infer` **e** `min` (o `min` é o melhor caso da sessão, menos
   contaminado por calor que a leitura instantânea).
4. Anotar `boxes` e olhar a tela: fps sem qualidade não serve de nada.

### O que esses números dizem

**1. A computação é quase toda inferência.** `279` de `295 ms` instrumentados —
95%. Pré e pós-processamento somados dão 15 ms.

**2. O `post` de 13 ms derruba uma hipótese.** Eu tinha escrito que a composição
da máscara RGBA full-res era "o segundo maior custo do ciclo". É 4% dele. Isso
**rebaixa a Fase 7** (protos em shader): o trabalho que ela elimina custa 13 ms,
não vale uma reescrita de semanas.

**3. O `draw` de 1.0 ms derruba outra.** O caminho de máscara em JS — o
`new Uint8ClampedArray` de 1.2 MB por inferência, o `putImageData`, o
`drawImage` — custa 1 ms inteiro. As camadas de canvas e a opacidade via CSS
continuam valendo, mas **por fluidez e por simplificar o código, não por
milissegundos**.

**4. Faltam 111 ms.** `ciclo 406` − `(2+279+13+1) = 295`. Mais de um quarto do
ciclo não estava instrumentado. São duas coisas somadas:

- **`toImageData` roda fora do engine.** No wrapper
  (`@ultralytics/yolo/dist/index.js:459`), `toImageData(image)` é chamado
  **antes** de entrar no engine, então o `speed.preprocess` de 2 ms é só o
  letterbox em Rust — a alocação de `OffscreenCanvas`, o `drawImage` e o
  `getImageData` não aparecem em lugar nenhum. O mesmo vale para a cópia dos
  resultados de volta (`decodeResults`).
- **O throttle de 100 ms.** `DETECTION_INTERVAL_MS` conta a partir do *fim* da
  inferência, e o rAF acorda a cada ~16 ms, então o loop fica ~116 ms parado por
  ciclo de propósito.

Os campos `extra` e `ocioso` do painel foram adicionados para separar os dois.
**Rodar de novo e anotar antes de decidir entre T2.2 e T3.3** — se `extra` for
alto, o custo é leitura de pixels; se `ocioso` dominar, é agendamento.

**5. `coi: não` com 4 núcleos ociosos.** O aparelho tem 4 núcleos e o LiteRT usa
1. Continua sendo a única alavanca real sobre os 279 ms, e agora com número:
**E1 é o evento principal deste plano.**

### Prioridade revisada pela medição

| antes | depois | por quê |
|-------|--------|---------|
| E1 cross-origin isolation | **E1, sem concorrência** | 4 núcleos ociosos, 95% do custo é inferência |
| E2 custos por inferência | **depende de `extra`** | `pre` e `draw` são ruído; o custo real está escondido no buraco |
| E3 agendamento | **sobe** | 111 ms de buraco, dos quais ~116 são throttle deliberado |
| E4 render desacoplado | mantém | justificativa é percepção, não ms |
| Fase 7 shader de máscara | **desce muito** | elimina 13 ms ao custo de semanas |

## O orçamento real de um frame

Os 272 ms são só a parte do meio. O ciclo completo hoje é:

```
rAF (60x/s, quase sempre só para descobrir que ainda não é hora)
  └─ model.predict(video)
       ├─ preprocess : new OffscreenCanvas(640,480)   <- alocado A CADA CHAMADA
       │               drawImage(video)                <- readback GPU→CPU
       │               getImageData()                  <- +1.2 MB alocados
       ├─ inference  : 272 ms                          <- CONSTANTE, main thread
       └─ postprocess: máscara RGBA full-res composta no wasm
  └─ tracker.update()
  └─ drawOverlay()
       ├─ new Uint8ClampedArray(masks)                 <- +1.2 MB alocados
       ├─ putImageData() no canvas auxiliar
       └─ drawImage() com globalAlpha no canvas visível
```

Tudo isso na main thread, em série, ~3,7 vezes por segundo. São ~2.4 MB de lixo
por inferência (~9 MB/s) só nas duas alocações marcadas, e o overlay só se move
quando o ciclo inteiro termina.

### Dois achados dentro do `@ultralytics/yolo`

Ler `node_modules/@ultralytics/yolo/dist/index.js` mudou duas coisas que eu
tinha escrito antes:

**1. O "fast path" de vídeo não é tão fast assim** (`dist/index.js:110-137`):

```js
function toImageData(input) {
  if (input instanceof ImageData) {
    return { data: new Uint8Array(input.data.buffer), ... };   // <- saída zero-cópia
  }
  ...
  const canvas = makeCanvas(width, height);        // new OffscreenCanvas TODA chamada
  const ctx = get2d(canvas, { willReadFrequently: true });
  ctx.drawImage(input, 0, 0, width, height);
  const img = ctx.getImageData(0, 0, width, height);
  return { data: new Uint8Array(img.data.buffer), width, height };
}
```

Passar um `HTMLVideoElement` custa: alocação de canvas, `drawImage` para um
canvas CPU-backed (`willReadFrequently: true`), e `getImageData`. Mas **se a
entrada já for um `ImageData`, tudo isso é pulado** — a função só embrulha o
buffer. O app pode fazer esse passo uma vez, com canvas e buffer persistentes, e
entregar `ImageData` pronto. Ver Fase 3.

**2. É possível chegar nos prototypes.** Eu disse no plano anterior que a API não
expunha as máscaras 160×160. Isso vale para o wrapper `@ultralytics/yolo` — mas o
`@litertjs/core` por baixo exporta `loadAndCompile()` e `CompiledModel.run()`
públicos, com `Tensor.toGpuBuffer()` e `copyTo('webgpu')`, e `CompileOptions`
aceita `accelerator: 'wasm' | 'webgpu' | 'webnn'` e `cpuOptions: { numThreads }`.
Dirigir o LiteRT direto devolve os tensores crus do modelo. É a Fase 7, e é cara.

---

## Fase 1 — Cross-origin isolation ❌ TENTADA E REVERTIDA

**Resultado negativo, medido no aparelho em 14/09/2026.** Esta era a aposta
principal do plano. Não funciona no iOS, e a razão é estrutural.

### O que aconteceu

O isolamento foi conseguido: com COOP/COEP servidos pelo Vite e o wasm do LiteRT
mais o `@litertjs/core` self-hostados, o painel passou a mostrar `coi: sim`. E o
app quebrou no carregamento do modelo:

```
Error: Threads are only supported with relaxed SIMD, and the current
browser does not support relaxed SIMD.
```

### Por que

Duas coisas somadas:

**1. O WebKit do iPhone não tem relaxed SIMD**, e o LiteRT exige relaxed SIMD
para o build threaded (`@litertjs/core/dist/index.js:1308`). Tabelas de
compatibilidade dizem que o Safari 18.4+ suporta, mas o probe do próprio LiteRT
— um `WebAssembly.instantiate` num módulo de teste — reprovou no aparelho. O
commit do WebKit que implementa relaxed laneselect fala em **x86_64 com AVX**, o
que torna plausível que o ARM ainda não tenha. O probe no dispositivo é a
verdade, não a tabela.

**2. Sem relaxed SIMD, o iOS já rodava no build `compat`.** A seleção de arquivo
(`dist/index.js:1323-1332`) só sai do `litert_wasm_compat_internal` se
`relaxedSimd` for verdadeiro. Ou seja: **mesmo que o erro não existisse, o
isolamento não traria ganho nenhum no iOS.** Os 4 núcleos são inalcançáveis lá.

Agravante do wrapper: o `@ultralytics/yolo` passa
`threads: crossOriginIsolated` sem checar relaxed SIMD
(`dist/index.js:199`), com um comentário afirmando que "SIMD is detected by
LiteRT itself". O LiteRT detecta — e **lança exceção** em vez de cair para o
build sem threads. Então o que deveria ser degradação graciosa virou tela de
erro. Vale reportar upstream.

### O que ficou

- **Revertido:** COOP/COEP no `vite.config.ts` e no `public/_headers`, ambos com
  comentário explicando o porquê para ninguém religar por engano.
- **Mantido:** o self-host do wasm do LiteRT e do `@litertjs/core` em `public/`,
  via `npm run vendor`. Nasceu como pré-requisito do COEP, mas vale sozinho:
  tira o jsDelivr do caminho crítico do load, fixa a versão junto com o
  `package.json` e é o que permite cachear os binários (Fase 6).

### Quando revisitar

- WebKit publicar relaxed SIMD em ARM;
- Android/Chrome virar alvo — lá o ganho existe, e o self-host já está pronto,
  bastando religar dois headers.

### O que isso muda no plano

Os ~280 ms de inferência são **imexíveis no navegador do iOS** sem trocar o
modelo. O que sobrou de acionável foi o throttle — e ele caiu sem precisar do
worker que eu projetei para viabilizá-lo:

- **O throttle saiu direto.** Medido com `?interval=0` no aparelho: a UI
  continuou respondendo. Os ~106 ms de ociosidade por ciclo eram 26% do tempo,
  colhidos por uma mudança de constante.
- **A E7 (worker) perdeu a justificativa.** Ela existia para permitir esse corte
  sem travar a UI. A UI não travou. Sobra o jank residual durante a inferência,
  que o teste mostrou tolerável — não vale 2-3 dias agora.
- **O motion gating virou o par necessário.** Sem throttle, o loop infere
  back-to-back e cozinha o aparelho — e o throttling térmico já era visível
  (`infer` de 264 a 317 ms conforme esquentava). Parado não se infere; movendo,
  usa-se tudo.
- **Reduzir `imgsz` para 320 volta a ser, isoladamente, a maior alavanca que
  existe** para este app. Está fora do escopo deste documento por premissa, mas
  a premissa agora custa mais caro do que parecia.

## Fase 2 — Separar thread de inferência e thread de UI

O padrão moderno para visão em tempo real no browser é o **split render/infer**:
a main thread nunca roda o modelo, só compõe. Hoje os 272 ms bloqueiam a main
thread inteira — React, toques, scroll, tudo.

```
main thread            │ worker
───────────────────────┼──────────────────────────────
rVFC → pega frame      │
  postMessage(frame) ──┼─→ predict()  (272 ms, bloqueia só aqui)
                       │   tracker.update()
rAF → desenha 60 FPS ←─┼── postMessage({ boxes, maskBitmap })
  (do último resultado)│
```

Peças:

- **`OffscreenCanvas`** via `canvas.transferControlToOffscreen()` se o worker
  for desenhar; ou o worker devolve só dados e a main thread desenha. Prefira a
  segunda no começo — é mais simples e o desenho é barato.
- **Transferables** nos dois sentidos: `ImageBitmap` e `ArrayBuffer` viajam sem
  cópia se listados no segundo argumento do `postMessage`. Um `Uint8Array` de
  máscara não transferido é 1.2 MB copiados por frame.
- **Devolver a máscara como `ImageBitmap`**, não como bytes: o worker faz
  `createImageBitmap(imageData)` (assíncrono, fora da main thread) e transfere o
  bitmap. A main thread só faz `drawImage` — sem `putImageData`, sem
  `Uint8ClampedArray`, sem upload síncrono de textura.

### A pegadinha deste projeto

**Import maps não valem em escopo de worker.** O `@litertjs/core` hoje só
resolve por causa do import map no `index.html`; dentro de um worker esse import
falha. Resolver isso é exatamente o trabalho da Fase 1c — por isso **Fase 1 antes
da Fase 2**, sempre.

---

## Fase 3 — Pipeline de aquisição de frames

### 3.1 `requestVideoFrameCallback` no lugar de `requestAnimationFrame`

`src/components/DetectionView.tsx:116` agenda com rAF, que acorda 60x/s e na
maioria das vezes só descobre que ainda não é hora (`:133`). O rVFC dispara uma
vez por frame de vídeo realmente apresentado, e entrega metadata útil de graça
(`mediaTime`, `presentedFrames`, `expectedDisplayTime`).

Suportado no iOS Safari desde 15.4. Mantenha o fallback para rAF:

```ts
const schedule = (video: HTMLVideoElement, cb: () => void) =>
  'requestVideoFrameCallback' in video
    ? video.requestVideoFrameCallback(() => cb())
    : requestAnimationFrame(() => cb());
```

Benefício colateral: `presentedFrames` diz quantos frames você pulou, que é a
métrica honesta de "estou acompanhando a câmera?".

### 3.2 Entregar `ImageData` em vez do `<video>`

Explorando o early-return de `toImageData` (ver acima), o app assume o controle
da leitura de pixels e para de alocar um canvas por inferência:

```ts
// criado uma vez, ao lado do offscreenRef
const grabRef = useRef<{ canvas: HTMLCanvasElement; ctx: CanvasRenderingContext2D;
                         image: ImageData } | null>(null);

// por inferência: zero alocação
const { ctx, image } = grabRef.current;
ctx.drawImage(video, 0, 0);
const frame = ctx.getImageData(0, 0, w, h);   // ainda aloca; ver 3.3
const results = await model.predict(frame, { conf });
```

Já corta a alocação de `OffscreenCanvas` por chamada. Note que `getImageData`
ainda aloca — o `ImageData` não é reaproveitável por essa API.

### 3.3 Zero-copy de verdade: WebCodecs — e por que não no iOS

O caminho ideal é `MediaStreamTrackProcessor`, que entrega um
`ReadableStream<VideoFrame>` pipeável direto para o worker, com `VideoFrame`
sendo transferable e `frame.copyTo(buffer, { format: 'RGBA' })` escrevendo num
`ArrayBuffer` reaproveitado — sem canvas, sem `getImageData`, sem readback
síncrono na main thread.

**O Safari não implementa `MediaStreamTrackProcessor`, nem no iOS nem no macOS**
([bug WebKit 241124](https://bugs.webkit.org/show_bug.cgi?id=241124), aberto).
Como o iOS é justamente o alvo mais lento, trate isso como **enhancement
progressivo**: Chrome/Android ganham o caminho zero-copy, iOS fica no
`<video>` + rVFC + canvas persistente da 3.2. Vale escrever a aquisição atrás de
uma interface pequena (`FrameSource`) com as duas implementações.

Se for usar `VideoFrame`: **todo frame precisa de `frame.close()`**. Frames não
fechados esgotam o pool do decoder e a câmera trava em segundos. Guarde no
máximo um frame pendente e feche o anterior ao substituir.

### 3.4 Latest-frame-wins explícito

A guarda `isInferring` (`:144`/`:187`) hoje descarta frames por omissão. Torne a
política explícita: guarde sempre **o frame mais recente** enquanto a inferência
roda, e ao terminar use esse — não o que chegou primeiro. Reduz a latência
percebida em até um frame inteiro de câmera sem custo nenhum.

---

## Fase 4 — Desacoplar o desenho da inferência

Hoje `drawOverlay` só roda quando a inferência termina
(`src/components/DetectionView.tsx:164`). Vídeo fluido, caixas a 3,7 FPS. Esta
fase não reduz milissegundo nenhum e é a que mais muda a sensação de uso.

### 4.1 Canvas em camadas

Se você redesenhar tudo a 60 FPS ingenuamente, vai fazer `putImageData` de
1.2 MB sessenta vezes por segundo para uma máscara que só muda 3,7 vezes por
segundo. Separe:

| camada | conteúdo | atualiza |
|--------|----------|----------|
| `<video>` | vídeo | compositor, 30-60 FPS |
| canvas-máscara | `results.masks` | só quando chega inferência |
| canvas-caixas | caixas + labels | todo rAF |

A camada de máscara vira um `drawImage` de `ImageBitmap` por inferência; a de
caixas é vetorial e barata.

### 4.2 Opacidade pelo compositor, não pelo JS

`src/lib/overlay.ts:55-57` usa `globalAlpha` + `drawImage`, e
`DetectionView.tsx:80` existe só para redesenhar quando o slider mexe. Com a
máscara em camada própria, opacidade vira uma propriedade CSS:

```css
.mask-layer { opacity: var(--mask-opacity); will-change: opacity; }
```

Mexer no slider passa a ser trabalho de compositor, sem repintura, sem JS. **O
`useEffect` de `DetectionView.tsx:74-81` desaparece inteiro**, e junto com ele a
razão de `showMasks`/`maskOpacity` estarem em ref.

### 4.3 Predição de movimento, não só suavização

Com 272 ms de inferência, a caixa desenhada descreve onde o objeto estava ~¼ de
segundo atrás. Suavizar (EMA) tira o tremor mas **aumenta** o atraso. O que
resolve é um modelo de velocidade constante no tracker, extrapolando entre
inferências:

```ts
// src/lib/tracker.ts — o Track já guarda a caixa anterior
interface Track { id: number; cls: number; box: Box;
                  vx: number; vy: number; missedFrames: number }

// na inferência: estima velocidade em px/ms
const dt = now - track.lastSeenAt;
const vx = (next.x1 - track.box.x1) / dt;

// no rAF de desenho: projeta para o instante atual
const age = performance.now() - track.lastSeenAt;
const x1 = track.box.x1 + track.vx * age;
```

Limite a extrapolação (ex.: no máximo 150 ms) para não deixar caixas viajando
quando a detecção some. Combine com EMA **na velocidade**, não na posição.

Isso ataca na raiz o que hoje é compensado por fora: `IOU_THRESHOLD = 0.3`
baixo e `COUNT_STABILITY_FRAMES = 3` existem porque a caixa pula muito entre
inferências.

### 4.4 Higiene no caminho da máscara

`src/lib/overlay.ts:52` aloca ~1.2 MB por inferência:

```ts
const image = new ImageData(new Uint8ClampedArray(masks), width, height);
```

Enquanto a Fase 2 não chega, guarde um `ImageData` persistente junto do canvas
auxiliar e use `image.data.set(masks)`. Depois da Fase 2 isso vira
`createImageBitmap` no worker e some.

---

## Fase 5 — Inferência adaptativa

Com o custo por inferência fixo, a alavanca que resta é **inferir menos vezes,
nas horas certas**.

### 5.1 Motion gating

Apontar a câmera para uma estante é um caso quase estático: o usuário segura o
telefone parado. Rodar 272 ms de rede sobre um frame idêntico ao anterior é
desperdício puro de bateria e de calor (e calor vira throttling, que piora os
272 ms).

Detector de movimento barato, na ordem de microssegundos:

```ts
// canvas persistente 32x32, desenha o frame reduzido e compara com o anterior
ctx32.drawImage(video, 0, 0, 32, 32);
const cur = ctx32.getImageData(0, 0, 32, 32).data;
let sad = 0;
for (let i = 0; i < cur.length; i += 4) sad += Math.abs(cur[i] - prev[i]);
if (sad < MOTION_THRESHOLD) { /* pula a inferência, reusa o último resultado */ }
```

Com o telefone parado, a taxa de inferência cai perto de zero e a contagem
continua estável. Quando o usuário move, volta ao máximo. Casa perfeitamente
com a Fase 4.3: parado, não há o que extrapolar.

### 5.2 Cadência em malha fechada

`DETECTION_INTERVAL_MS = 100` (`DetectionView.tsx:10`) é um chute fixo que hoje
nem tem efeito — a inferência leva 272 ms, sempre maior que o intervalo. Troque
por um controlador sobre a média móvel do tempo real de inferência:

```ts
// EMA do custo observado; alvo de ocupação ~70% para sobrar main thread
emaInferMs = emaInferMs * 0.8 + results.speed.inference * 0.2;
const targetIntervalMs = emaInferMs / 0.7;
```

Isso faz o app se adaptar sozinho a aparelho fraco, throttling térmico e bateria
baixa, em vez de assumir um número.

### 5.3 Escada de degradação

Defina explicitamente o que cai primeiro quando `emaInferMs` estourar um limite:

1. desliga a máscara (o `postprocess` full-res é o segundo maior custo);
2. reduz a resolução de captura;
3. aumenta o intervalo alvo;
4. congela a contagem e só mostra o último valor estável.

Melhor decidir isso agora do que descobrir num iPhone quente na frente do
usuário.

---

## Fase 6 — Startup e carregamento

O `.tflite` tem 13.3 MB e é baixado a cada abertura antes da primeira detecção.

- **Service Worker + Cache API** com estratégia cache-first para
  `/models/*.tflite` e `/litert/*`. Atenção ao aviso do README: qualquer proxy
  que recomprima ou trunque o `.tflite` quebra o ZIP de metadata no fim do
  arquivo. O Cache API guarda os bytes como vieram — é seguro, desde que o
  fetch original seja byte a byte.
- **Nome com hash + `Cache-Control: immutable`** para o modelo, para não
  revalidar 13 MB.
- **`<link rel="preload" as="fetch" crossorigin>`** do modelo no `index.html`,
  para o download começar em paralelo com o bundle JS em vez de depois dele.
- **Carregar modelo e pedir câmera em paralelo.** Hoje o modelo carrega na
  montagem e a câmera só no clique do botão (`App.tsx`), o que é razoável — mas
  a compilação do LiteRT pode ser disparada antes do primeiro clique.

---

## Fase 7 — Avançado: dirigir o LiteRT diretamente

Só faça isso se as Fases 1-5 não bastarem. É trocar ~40 linhas de wrapper por
algumas centenas de código de pré e pós-processamento — e assumir a manutenção.

O que abre:

- **Prototypes de máscara.** O `yolov8n-seg` devolve `output0` `[1,37,8400]`
  (caixas + 32 coeficientes) e `output1` `[1,160,160,32]` (protos). Combinar
  proto×coef e fazer o upscale **num shader** elimina o `postprocess` full-res do
  wasm e melhora a qualidade da borda (bilinear na GPU em vez de nearest na CPU).
  **Mas a medição mostrou que esse `postprocess` custa 13 ms de um ciclo de
  406 ms.** O ganho de tempo é marginal; sobra o argumento de qualidade de
  imagem, que sozinho não paga a reescrita.
- **Tensores residentes na GPU.** `Tensor.copyTo('webgpu')` e
  `Tensor.toGpuBuffer()` permitem que a saída nunca volte para a CPU: protos
  ficam na GPU e o shader de composição lê direto.
- **`cpuOptions: { numThreads }` explícito** em vez do padrão.
- **`accelerator: 'webnn'`.** O `CompileOptions` do `@litertjs/core` aceita, com
  `devicePreference: 'cpu' | 'gpu' | 'npu'`. O wrapper `@ultralytics/yolo` não
  expõe. Numa NPU de celular isso é outra ordem de grandeza — mas o suporte a
  WebNN ainda é irregular, então é aposta, não plano.
- **NMS e escala de coordenadas sob seu controle**, incluindo reaproveitar
  buffers em vez de alocar por frame.

Custo: reimplementar letterbox, NMS, escala de caixas e combinação de máscara.
Tudo está documentado no código Python do Ultralytics, mas é trabalho real e é
onde bugs sutis de coordenada aparecem.

---

## Ordem recomendada

| # | Ação | Onde | Esforço | Efeito |
|---|------|------|---------|--------|
| 0 | Instrumentar 3 estágios + `crossOriginIsolated` + FPS real | `DetectionView`, `DiagnosticsPanel` | 30 min | habilita o resto |
| 1 | COOP/COEP + self-host wasm e `@litertjs/core` | `vite.config.ts`, `public/`, `useYoloModel` | 1 dia | **272 → 80-140 ms** |
| 2 | Constraints de câmera (`width`/`height`/`frameRate`) | `useWebcam.ts:27` | 10 min | evita frame gigante no iOS |
| 3 | `ImageData` persistente na entrada do `predict` | `DetectionView` | 1 h | −1 canvas/inferência |
| 4 | `ImageData` reaproveitado no overlay | `overlay.ts:52` | 15 min | −1.2 MB/inferência |
| 5 | rVFC + latest-frame-wins | `DetectionView:116,133` | 2 h | −latência, −rAF vazio |
| 6 | Camadas de canvas + opacidade em CSS | `DetectionView`, `overlay.ts`, CSS | meio dia | slider instantâneo |
| 7 | rAF de desenho + velocidade no tracker | `DetectionView`, `tracker.ts` | 1 dia | **overlay a 60 FPS** |
| 8 | Motion gating + cadência adaptativa | `DetectionView` | meio dia | bateria, calor |
| 9 | Worker + OffscreenCanvas + transferables | novo módulo | 2-3 dias | UI nunca trava |
| 10 | Service Worker para o modelo | novo | meio dia | abertura instantânea |
| 11 | WebCodecs no Chrome/Android | `FrameSource` | 1-2 dias | zero-copy onde dá |
| 12 | LiteRT direto (protos em shader, WebNN) | reescrita | 1-2 semanas | teto do que dá pra fazer |

Itens 0-8 são o núcleo: nenhum deles mexe no modelo e juntos devem levar de
**3,7 FPS de detecção com overlay travado** para **~8-12 FPS de detecção com
overlay a 60 FPS e UI responsiva**. Os itens 9-12 são para quando isso não
bastar.

---

## O que não vale a pena

- **Otimizar `src/lib/tracker.ts`.** O casamento guloso é O(tracks × boxes) com
  dezenas de caixas — ruído perto de 272 ms. O que falta ali é o modelo de
  velocidade (4.3), não performance.
- **`React.memo` / memoização.** O `DetectionView` só remonta quando `model` ou
  `stream` mudam, e o loop vive num efeito com estado local. A regra que importa
  é outra: **nada por frame pode passar por estado do React.** O
  `setDiagnostics` a cada inferência já re-renderiza o `App`, mas só com
  `?debug=1`; se virar permanente, escreva no DOM por ref.
- **`COEP: credentialless`.** Não existe no Safari e não está no roadmap.
- **Servidor de inferência.** Não há servidor; o round-trip de rede sairia pior
  que os 80-140 ms locais depois da Fase 1.
- **Recombinar máscaras em shader mantendo o `@ultralytics/yolo`.** O wrapper
  entrega a máscara já composta em RGBA full-res; só há acesso aos protos indo
  para o LiteRT direto (Fase 7).
