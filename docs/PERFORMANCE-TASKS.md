# Tarefas — melhoria de performance

Quebra executável de [PERFORMANCE.md](./PERFORMANCE.md). O modelo não muda:
`yolov8n-seg`, `imgsz 640`, fp32, ~272 ms de inferência é constante.

Cada tarefa tem **arquivos**, **o que fazer**, **pronto quando** e
**depende de**. Tarefas sem dependência podem ir em paralelo.

> **Atualizado pela medição de 14/09/2026** (ver
> [PERFORMANCE.md § Medições](./PERFORMANCE.md#medições)). O baseline real —
> `infer 279ms`, `post 13ms`, `draw 1.0ms`, `ciclo 406ms`, `coi não`, 4 núcleos —
> rebaixou T2.3 e E9, e confirmou E1 como prioridade única. Status marcado em
> cada tarefa afetada.

Legenda de tamanho: `P` até 1h · `M` até meio dia · `G` 1-3 dias · `GG` 1+ semana

---

## E0 — Instrumentação

Bloqueia a validação de todo o resto. Faça primeiro.

### T0.1 — Expandir o painel de diagnóstico `P`
**Arquivos:** `src/components/DiagnosticsPanel.tsx`, `src/components/DetectionView.tsx`

Hoje o painel mostra só `results.speed.inference`, descartando os outros dois
estágios que o `Results` já carrega.

Adicionar ao tipo `Diagnostics` e ao painel:
- `preprocessMs`, `postprocessMs` (de `results.speed`)
- `drawMs` — `performance.now()` em volta da chamada de `drawOverlay`
- `intervalMs` — tempo real entre o início de duas inferências
- `detectFps` — `1000 / intervalMs`, média móvel
- `crossOriginIsolated` — `globalThis.crossOriginIsolated`
- `cores` — `navigator.hardwareConcurrency`

**Pronto quando:** abrindo `?debug=1` no celular, os seis valores aparecem e
`preprocess + inference + postprocess + draw` fecha perto do `intervalMs`.

---

### T0.2 — Registrar o baseline `P`
**Arquivos:** `docs/PERFORMANCE.md` (nova seção "Medições")
**Depende de:** T0.1

Rodar no aparelho alvo (iOS) e num desktop, anotar os números de T0.1 numa
tabela datada. Sem isso não há como afirmar que qualquer tarefa abaixo funcionou.

**Pronto quando:** tabela commitada com aparelho, browser, e os seis valores.

---

## E1 — Cross-origin isolation ❌ TENTADA E REVERTIDA

> **Resultado negativo.** O WebKit do iPhone não tem relaxed SIMD, que o LiteRT
> exige para o build threaded — e sem ele o iOS já rodava no build `compat`, então
> o isolamento não traria ganho mesmo sem o erro. Ver
> [PERFORMANCE.md § Fase 1](./PERFORMANCE.md). Self-host mantido; headers revertidos.

Destrava `litert_wasm_threaded_internal.wasm`. As quatro primeiras tarefas
precisam entrar **juntas** — meio caminho quebra o carregamento do modelo.
Trabalhe numa branch e só mescle depois de T1.5.

### T1.2 — Self-hostar o wasm do LiteRT `P` — ✅ feito e MANTIDO
**Arquivos:** `package.json`, `.gitignore`, `src/hooks/useYoloModel.ts`

Script de cópia (não commitar binário; gerar no `predev`/`prebuild`):

```json
"scripts": {
  "copy:litert": "cp -r node_modules/@litertjs/core/wasm public/litert",
  "predev": "npm run copy:litert",
  "prebuild": "npm run copy:litert"
}
```

Adicionar `public/litert/` ao `.gitignore` e apontar o loader:

```ts
YOLO.load(MODEL_URL, {
  device: deviceOverride,
  litertWasmUrl: new URL('/litert/', location.origin).href,
})
```

**Pronto quando:** `npm run dev` copia os quatro `.wasm` e o app carrega o
modelo sem tocar no jsDelivr (confirmar na aba Network).

---

### T1.3 — Self-hostar o `@litertjs/core` `M` — ✅ feito e MANTIDO
**Arquivos:** `index.html`, `package.json`, `public/`

O import map aponta para `https://cdn.jsdelivr.net/npm/@litertjs/core@2.5.3/+esm`.
Sob `COEP: require-corp` isso para de carregar.

✅ Resolvido **sem baixar nada e sem bundler**: o `dist/` do `@litertjs/core`
tem exatamente um import externo (`@litertjs/wasm-utils`), que já está em
`node_modules` e é autocontido. Então são duas cópias e duas entradas no import
map — que vale para todo o grafo de módulos da página, inclusive para o import
feito de dentro de um módulo do próprio origin:

```json
{ "imports": {
  "@litertjs/core": "/vendor/litert-core.js",
  "@litertjs/wasm-utils": "/vendor/litert-wasm-utils.js"
} }
```

Isso substitui a entrada única que apontava para o bundle `+esm` do jsDelivr
(que trazia o `wasm-utils` embutido).

**Verificado:** dev e preview servem os dois arquivos com `Content-Type:
text/javascript`, e o import cru sobrevive à cópia.

---

### T1.1 — Headers COOP/COEP no Vite `P` — ❌ revertida
**Arquivos:** `vite.config.ts`
**Depende de:** T1.2, T1.3

```ts
const coi = {
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Embedder-Policy': 'require-corp',
}
// aplicar em server.headers e preview.headers
```

**Não usar `credentialless`** — o Safari não implementa e não pretende.

**Pronto quando:** `crossOriginIsolated === true` no painel de T0.1, em dev.

---

### T1.4 — Headers em produção `P` — ❌ revertida
**Arquivos:** conforme o host (`public/_headers`, `vercel.json`, nginx)
**Depende de:** T1.1

**Pronto quando:** `crossOriginIsolated === true` na URL de produção, no celular.

---

### T1.5 — Validar o ganho e decidir `P` — ✅ feito: reverter
**Depende de:** T1.1-T1.4, T0.2

Comparar `inferenceMs` com o baseline. Esperado: 264-279 → 90-150 ms com os
4 núcleos do aparelho.

**Isto é a única parte da E1 que não dá para fazer sem o celular.** Abrir com
`?debug=1` e conferir, nesta ordem:

1. `coi` mostra **sim** (se não, os headers não chegaram — ngrok repassa os do
   vite, então seria problema de config);
2. o modelo carregou (se falhar, é o import map ou o `litertWasmUrl`);
3. `infer` caiu.

### Como reverter

Tudo está em quatro lugares e nada é destrutivo:

- `vite.config.ts` — remover `headers` de `server`/`preview`
- `public/_headers` — apagar o bloco `/*`
- `index.html` — voltar o import map para o jsDelivr
- `src/hooks/useYoloModel.ts` — remover `litertWasmUrl`

O `npm run vendor` e o `.gitignore` podem ficar: cópias em `public/` não
atrapalham nada se não forem usadas.

Se **não** melhorar, investigar nesta ordem: (a) `crossOriginIsolated` é mesmo
`true`? (b) o LiteRT escolheu o build threaded? (c) `navigator.hardwareConcurrency`
no aparelho. Se o iOS não ganhar nada, documentar e manter mesmo assim — o
isolamento é pré-requisito da E7.

**Pronto quando:** número novo na tabela de T0.2, com decisão registrada.

---

## E2 — Custos evitáveis por inferência

Independentes entre si e de E1. Ganho pequeno cada, mas quase sem risco.

### T2.1 — Fixar as constraints da câmera `P` — ❌ revertida
**Arquivos:** `src/hooks/useWebcam.ts:27`

```ts
video: {
  facingMode: mode,
  width:  { ideal: 640 },
  height: { ideal: 480 },
  frameRate: { ideal: 30 },
}
```

Sem isso, um iPhone pode entregar 1920×1080 e fazer o wasm compor uma máscara de
8 MB por frame. O modelo reduz para 640 de qualquer jeito.

**Pronto quando:** o campo `frame` do painel mostra `640x480` no iOS.

---

### T2.2 — Entregar `ImageData` ao `predict` `P` — ❌ descartada
**Arquivos:** `src/components/DetectionView.tsx`

`toImageData` do `@ultralytics/yolo` (`dist/index.js:110-137`) aloca um
`OffscreenCanvas` **a cada chamada** quando recebe um `<video>`, mas tem
early-return para `ImageData`. Assumir esse passo:

- criar um canvas de captura persistente num ref (como o `offscreenRef` de `:45`)
- por inferência: `ctx.drawImage(video, 0, 0)` → `ctx.getImageData(...)` → passar
  ao `predict`
- `getContext('2d', { willReadFrequently: true })`

❌ **Medido: `extra` = 8 ms de um ciclo de 400 ms.** O `speed.preprocess` não
media isso (`toImageData` roda fora do engine, `dist/index.js:459`), então foi
preciso instrumentar o `predict` por fora para descobrir. Descoberto: a alocação
de `OffscreenCanvas` por chamada, o `drawImage`, o `getImageData` e a cópia dos
resultados custam 8 ms somados. Não vale o refactor.

**Com T2.2 e T2.3 descartadas, a E2 inteira se reduz a T2.1.**

---

### T2.3 — Reaproveitar o `ImageData` do overlay `P` — ❌ descartada
**Arquivos:** `src/lib/overlay.ts:52`

`new ImageData(new Uint8ClampedArray(masks), w, h)` aloca ~1.2 MB por inferência.
Guardar um `ImageData` persistente junto do canvas auxiliar e usar
`image.data.set(masks)`.

Como `drawOverlay` hoje recebe o canvas por parâmetro, o `ImageData` persistente
precisa morar no mesmo lugar — considere trocar o par
`(offscreen, ImageData)` por um pequeno objeto criado uma vez.

❌ **Medido: `draw` custa 1.0 ms do ciclo de 406 ms.** Todo o caminho de máscara
em JS — alocação de 1.2 MB, `putImageData` e `drawImage` — cabe em 1 ms. Não há
ganho de tempo a colher. Fica só o argumento de pressão de GC, que não apareceu
como problema. Manter registrado como descartada para não ser redescoberta.

---

## E3 — Agendamento de frames

### T3.1 — `requestVideoFrameCallback` com fallback `P`
**Arquivos:** `src/components/DetectionView.tsx:116`

Trocar o `requestAnimationFrame` do agendador de inferência por rVFC
(iOS 15.4+), mantendo rAF como fallback. Extrair para um helper `scheduleFrame`.

**Pronto quando:** o loop não acorda mais 60x/s sem fazer nada (visível no
Performance panel) e o comportamento é idêntico no Safari.

---

### T3.2 — Latest-frame-wins explícito `P`
**Arquivos:** `src/components/DetectionView.tsx:133-144`
**Depende de:** T3.1

A guarda `isInferring` hoje descarta frames por omissão. Passar a guardar sempre
o frame mais recente durante a inferência e usar **esse** ao terminar, em vez do
primeiro que chegar depois.

**Pronto quando:** `intervalMs` continua igual e a latência percebida ao mover a
câmera diminui.

---

### T3.0 — Flag `?interval=N` para medir o throttle `P` — ✅ feito

**Arquivos:** `src/lib/debugFlags.ts`, `src/components/DetectionView.tsx`

Tarefa nova, criada para **decidir se a E7 se paga antes de pagá-la**. O
`ocioso` é 106-107 ms em todas as medições; zerá-lo daria ~2.5 → ~3.4 fps, mas
custa o respiro da main thread. Em vez de assumir, `?interval=0` mede os dois
extremos no aparelho real.

**Pronto quando:** existe um número dizendo o quanto a UI piora sem throttle —
é o que justifica (ou dispensa) 2-3 dias de worker.

---

### T3.1b — Remover o throttle `P` — ✅ feito

**Medido no aparelho com `?interval=0`: a UI continuou respondendo bem.** Então
o padrão virou 0 e os ~106 ms de ociosidade por ciclo saíram. O flag
`?interval=N` fica para reintroduzir respiro num aparelho mais fraco sem
recompilar.

O que protege o aparelho agora não é ociosidade cega, é a T5.1.

---

### T3.3 — Guarda térmica `P` — ✅ feito (versão reduzida)

Eu tinha rebaixado esta tarefa achando que o motion gating tornaria a cadência
irrelevante. **A calibração mostrou o contrário:** segurando o aparelho na mão a
leitura de movimento fica em 3.0-10.0 contra um limiar de 0.5, ou seja, o gating
**nunca** dispara em uso normal — ele só protege o aparelho apoiado. Sem
throttle e sem gating, uso normal = inferência back-to-back = calor.

Implementada uma versão mínima em vez do controlador de ocupação original:
guarda o melhor tempo de inferência da sessão (proxy do aparelho frio) e, quando
a média móvel passa dele por 25%, devolve 25% do ciclo como ociosidade. Solta-se
sozinha quando esfria. O painel só mostra a linha `térmico` quando está agindo.
**Arquivos:** `src/components/DetectionView.tsx:10,133`
**Depende de:** T0.1

⬆ **Medido: o throttle custa 106 ms de um ciclo de 400 ms — 26%.** É o segundo
maior item do ciclo, atrás só da inferência. Zerá-lo daria 2.5 → 3.4 fps.

⚠️ **Mas só depois da E1.** Esses 106 ms são o respiro da main thread, que a
inferência wasm single-thread bloqueia. Hoje a UI tem 26% do tempo; sem throttle
teria 4%. Com a E1 baixando a inferência para ~90 ms, o ciclo vira ~226 ms com
47% de folga, e aí dá para reduzir o throttle sem sacrificar o toque.

Substituir por EMA do custo observado com alvo de ocupação:

```ts
emaInferMs = emaInferMs * 0.8 + results.speed.inference * 0.2;
const targetIntervalMs = emaInferMs / 0.7;   // ~70% de ocupação
```

Manter um teto absoluto configurável para modo economia.

**Pronto quando:** o app se estabiliza sozinho em aparelhos diferentes, sem
constante fixa no código.

---

## E4 — Render desacoplado da inferência

O bloco que mais muda a sensação de uso. Fazer na ordem.

### T4.1 — Separar overlay em duas camadas `M` — ✅ feito
**Arquivos:** `src/lib/overlay.ts`, `src/components/DetectionView.tsx`, `src/App.css`

Quebrar `drawOverlay` em `drawMask` e `drawBoxes`, e o canvas único em dois
elementos empilhados: máscara (atualiza por inferência) e caixas (atualiza por
rAF). Sem isso, desenhar a 60 FPS significaria `putImageData` de 1.2 MB sessenta
vezes por segundo para uma máscara que muda 3,7 vezes.

**Pronto quando:** visual idêntico ao atual, com dois `<canvas>` no DOM.

---

### T4.2 — Opacidade da máscara pelo compositor `P` — ✅ feito
**Arquivos:** `src/App.css`, `src/components/DetectionView.tsx:74-81`, `src/lib/overlay.ts:55-57`
**Depende de:** T4.1

Com a máscara em camada própria, `maskOpacity` vira CSS:

```css
.mask-layer { opacity: var(--mask-opacity); will-change: opacity; }
```

Some o `globalAlpha` do `overlay.ts` e **some inteiro o `useEffect` de redesenho
imediato** (`DetectionView.tsx:74-81`) — junto com a razão de `showMasks` e
`maskOpacity` viverem em `optionsRef`.

**Pronto quando:** arrastar o slider é instantâneo e não dispara repintura de
canvas (conferir no Performance panel).

---

### T4.3 — Loop de desenho independente `M` — ✅ feito
**Arquivos:** `src/components/DetectionView.tsx`
**Depende de:** T4.1

Separar em dois loops: o de inferência (rVFC, T3.1) e um rAF que desenha as
caixas todo frame a partir do último resultado.

**Pronto quando:** as caixas se movem a 60 FPS enquanto `detectFps` continua em
~3,7 (ou o que a E1 tiver entregue).

---

### T4.4 — Velocidade e extrapolação no tracker `M` — ✅ feito
**Arquivos:** `src/lib/tracker.ts`
**Depende de:** T4.3

Adicionar `vx, vy, lastSeenAt` ao `Track`, estimar velocidade em px/ms na
inferência e expor uma função que projeta a caixa para um instante `t` — usada
pelo loop de desenho.

Detalhes que importam:
- limitar a extrapolação (ex.: 150 ms) para caixas não viajarem quando a
  detecção some
- aplicar EMA **na velocidade**, não na posição (EMA na posição aumenta o atraso,
  que já é de ~272 ms)

**Pronto quando:** ao girar o telefone devagar, as caixas acompanham os livros em
vez de correr atrás deles.

---

### T4.5 — Recalibrar os limiares do tracker `P` — ⏸ precisa do aparelho
**Arquivos:** `src/lib/tracker.ts:13,17`, `src/components/DetectionView.tsx:14`
**Depende de:** T4.4

⏸ **Deixada por último de propósito: é a única tarefa que depende de julgamento
visual, e chutar valores já saiu caro duas vezes** (constraints de câmera,
limiar de movimento). Os valores atuais continuam os originais.

O que a T4.4 já corrigiu sem chute: o `MAX_MISSED_FRAMES = 5` virou
`MAX_MISSED_MS = 500`. O comentário antigo afirmava que 5 frames davam "meio
segundo a uma inferência por 100ms", mas o ciclo medido é de 300-470ms — os 5
frames valiam 1.5 a 2.3 segundos, tempo de sobra para um livro voltar com o id de
outro. Contado em tempo, o comportamento não muda quando a taxa de inferência
varia (gating, guarda térmica, aparelho mais lento).

Ainda em aberto, para calibrar olhando a tela:
- `IOU_THRESHOLD = 0.3` — agora o casamento é feito contra a posição
  **projetada**, não a última medida, então dá para subir sem perder tracks num
  pan. Tentar 0.4-0.5.
- `COUNT_STABILITY_FRAMES = 3` — a ~3 fps isso atrasa a contagem em ~1s. Tentar 2.
- `MAX_EXTRAPOLATION_MS = 150` — se a caixa "deslizar" demais ao parar o
  movimento, baixar.

---

## E5 — Inferência adaptativa

### T5.1 — Motion gating `M` — ✅ feito (limiar calibrado: 0.5)
**Arquivos:** `src/components/DetectionView.tsx`, novo `src/lib/motion.ts`
**Depende de:** T3.3

Canvas persistente 32×32; desenhar o frame reduzido, somar diferença absoluta
contra o anterior, e pular a inferência abaixo de um limiar — reusando o último
resultado.

Expor o valor de SAD e o estado (`gated` / `active`) no painel de debug, para
calibrar o limiar no aparelho real em vez de chutar.

**Calibrado no aparelho:** parado sobre a mesa 0.1, na mão 3.0-10.0. Limiar
fixado em **0.5** — 5x acima do ruído, 6x abaixo do movimento mais fraco. O
chute inicial de 4.0 caía dentro da faixa de movimento real e congelava a
detecção no meio de um pan lento.

⚠️ **Alcance real menor do que eu projetei:** como a mão sempre passa do limiar,
o gating só economiza com o aparelho apoiado ou escorado. A proteção térmica de
uso normal ficou com a T3.3.

---

### T5.2 — Escada de degradação `M`
**Arquivos:** `src/components/DetectionView.tsx`
**Depende de:** T3.3, T5.1

Quando `emaInferMs` passar de um limite (throttling térmico, aparelho fraco),
degradar nesta ordem: (1) desligar máscara, (2) reduzir resolução de captura,
(3) aumentar o intervalo alvo, (4) congelar a contagem no último valor estável.

**Pronto quando:** rodando o app por 10 min até esquentar, a UI continua
responsiva e o painel mostra em que degrau está.

---

## E6 — Startup

O `.tflite` são 13.3 MB baixados antes da primeira detecção.

### T6.1 — Preload do modelo `P` — ✅ feito
**Arquivos:** `index.html`

`<link rel="preload" as="fetch" crossorigin>` para o modelo, começando o download
em paralelo com o bundle JS em vez de depois dele.

**Pronto quando:** na aba Network, modelo e bundle começam juntos.

---

### T6.2 — Cache imutável para o modelo `P` — ✅ feito
**Arquivos:** config do host, `public/models/`

Nome com hash + `Cache-Control: public, max-age=31536000, immutable`.

**Cuidado:** o README avisa que qualquer proxy que recomprima ou trunque o
`.tflite` quebra o ZIP de metadata no fim do arquivo. Verificar que o host serve
byte a byte.

**Pronto quando:** segunda visita não revalida os 13 MB.

---

### T6.3 — Service Worker cache-first `M` — ✅ feito
**Arquivos:** novo `public/sw.js`, `src/main.tsx`
**Depende de:** T6.2

Cache-first para `/models/*.tflite`, `/litert/*` e `/vendor/*`. O Cache API
guarda os bytes como vieram, então é seguro para o ZIP de metadata.

**Pronto quando:** app abre e detecta offline, depois da primeira visita.

---

## E7 — Worker de inferência ⬇ PERDEU A JUSTIFICATIVA

A E7 existia para permitir cortar o throttle sem travar a UI. **Medido: a UI não
trava sem o throttle** (`?interval=0` no aparelho), então o throttle já saiu sem
worker nenhum, e o ganho que a E7 justificaria foi coletado por 3 linhas.

O que sobra para o worker é o jank residual durante os ~300 ms de inferência —
real, mas o teste no aparelho mostrou que é tolerável. Não vale 2-3 dias agora.

**Reabrir se:** aparecer uma interação que precise de resposta imediata durante a
inferência (um gesto de arrastar, uma animação contínua), ou se a inferência
ficar mais lenta em algum aparelho.

O bloqueador técnico já está resolvido de qualquer forma: o plugin
`vizi:resolve-litert-in-workers` faz o `@litertjs/core` ser empacotável, então
começar a E7 no futuro não esbarra mais em import map.

### T7.1 — Extrair o loop do React `M`
**Arquivos:** novo `src/lib/detectionLoop.ts`, `src/components/DetectionView.tsx`

Tirar o loop de dentro do `useEffect` e transformar num módulo puro com
`start()`/`stop()` e callbacks. Pré-requisito do worker e do que o torna testável.

**Pronto quando:** `DetectionView` só monta os elementos e liga o loop; nenhum
comportamento muda.

---

### T7.2 — Mover a inferência para um worker `G`
**Arquivos:** novo `src/workers/inference.worker.ts`, `src/lib/detectionLoop.ts`
**Depende de:** T7.1, T1.3

Protocolo mínimo: main envia frame (transferível), worker devolve
`{ boxes, maskBitmap, speed }`. O tracker pode ficar no worker.

**Pronto quando:** a main thread não tem mais tarefas longas de 272 ms no
Performance panel, e a UI responde ao toque durante a inferência.

---

### T7.3 — Máscara como `ImageBitmap` transferível `M`
**Arquivos:** `src/workers/inference.worker.ts`, `src/lib/overlay.ts`
**Depende de:** T7.2

Worker faz `createImageBitmap(imageData)` (assíncrono, fora da main thread) e
transfere o bitmap. A main thread só faz `drawImage` — sem `putImageData`, sem
cópia de 1.2 MB.

**Pronto quando:** `drawMs` cai e T2.3 vira desnecessária.

---

## E8 — Zero-copy onde o browser deixa

### T8.1 — Abstrair a fonte de frames `M`
**Arquivos:** novo `src/lib/frameSource.ts`
**Depende de:** T7.1

Interface `FrameSource` com a implementação atual (`<video>` + rVFC + canvas
persistente), que é a única que funciona no iOS.

---

### T8.2 — Implementação WebCodecs `G`
**Arquivos:** `src/lib/frameSource.ts`
**Depende de:** T8.1, T7.2

`MediaStreamTrackProcessor` → `ReadableStream<VideoFrame>` pipeado direto para o
worker, com `frame.copyTo(buffer, { format: 'RGBA' })` num `ArrayBuffer`
reaproveitado.

**Não existe no Safari** (nem iOS nem macOS, bug WebKit 241124 aberto) — é
enhancement progressivo, com detecção de feature e fallback para T8.1.

**Crítico:** todo `VideoFrame` precisa de `close()`. Frames não fechados esgotam o
pool do decoder e a câmera trava em segundos. Guardar no máximo um pendente e
fechar o anterior ao substituir.

**Pronto quando:** no Chrome Android, `preprocessMs` vai perto de zero; no iOS o
comportamento é idêntico ao de antes; e a câmera roda 10 min sem travar.

---

## E9 — LiteRT direto (só se necessário)

### T9.1 — Spike: rodar o modelo sem o wrapper `G`
**Arquivos:** novo, descartável

`loadAndCompile()` + `CompiledModel.run()`, ler `output0` `[1,37,8400]` e
`output1` `[1,160,160,32]`, e comparar as caixas com as do `@ultralytics/yolo` no
mesmo frame. **Timebox de 2 dias.** Objetivo: descobrir se vale, não entregar.

Medir também `accelerator: 'webnn'` e `cpuOptions: { numThreads }` explícito, que
o wrapper não expõe.

**Pronto quando:** existe um número dizendo quanto se ganha tirando o
`postprocess` full-res do wasm — ou a constatação de que não compensa.

---

### T9.2 — Composição de máscara em shader `GG` — ⬇ rebaixada
**Depende de:** T9.1 com resultado positivo

⬇ **Medido: o `postprocess` que isso elimina custa 13 ms de 406 ms.** O ganho de
tempo não paga semanas de trabalho. Sobra o argumento de qualidade da borda.

Combinar proto×coeficientes e fazer o upscale num shader, com os tensores
residentes na GPU (`Tensor.copyTo('webgpu')`, `Tensor.toGpuBuffer()`).

Exige reimplementar letterbox, NMS e escala de coordenadas. É onde bugs sutis de
coordenada aparecem.

---

## Sequência sugerida de PRs

| PR | Tarefas | Por quê juntas |
|----|---------|----------------|
| 1 | T0.1, T0.2 | Sem medição nada abaixo é verificável |
| 2 | T2.1, T2.3 | Duas linhas cada, risco zero, ganho imediato |
| 3 | T1.2, T1.3, T1.1, T1.4, T1.5 | Precisam entrar juntas ou o modelo não carrega |
| 4 | T2.2, T3.1, T3.2, T3.3 | Todas no agendador/entrada do `predict` |
| 5 | T4.1, T4.2 | Refactor de camadas + o que ele destrava |
| 6 | T4.3, T4.4, T4.5 | Render a 60 FPS só faz sentido com predição |
| 7 | T5.1, T5.2 | Adaptação, depois que a cadência existe |
| 8 | T6.1, T6.2, T6.3 | Startup, independente de tudo |
| 9 | T7.1, T7.2, T7.3 | Worker |
| 10 | T8.1, T8.2 | WebCodecs |
| — | T9.x | Só com decisão explícita depois do spike |

PRs 1, 2 e 8 não dependem de nada e podem ir a qualquer momento.
