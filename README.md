# React + TypeScript + Vite

This template provides a minimal setup to get React working in Vite with HMR and some ESLint rules.

Currently, two official plugins are available:

- [@vitejs/plugin-react](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react) uses [Oxc](https://oxc.rs)
- [@vitejs/plugin-react-swc](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react-swc) uses [SWC](https://swc.rs/)

## React Compiler

The React Compiler is not enabled on this template because of its impact on dev & build performances. To add it, see [this documentation](https://react.dev/learn/react-compiler/installation).

## Expanding the ESLint configuration

If you are developing a production application, we recommend updating the configuration to enable type-aware lint rules:

```js
export default defineConfig([
  globalIgnores(['dist']),
  {
    files: ['**/*.{ts,tsx}'],
    extends: [
      // Other configs...

      // Remove tseslint.configs.recommended and replace with this
      tseslint.configs.recommendedTypeChecked,
      // Alternatively, use this for stricter rules
      tseslint.configs.strictTypeChecked,
      // Optionally, add this for stylistic rules
      tseslint.configs.stylisticTypeChecked,

      // Other configs...
    ],
    languageOptions: {
      parserOptions: {
        project: ['./tsconfig.node.json', './tsconfig.app.json'],
        tsconfigRootDir: import.meta.dirname,
      },
      // other options...
    },
  },
])

```

You can also install [eslint-plugin-react-x](https://npmx.dev/package/eslint-plugin-react-x) and [eslint-plugin-react-dom](https://npmx.dev/package/eslint-plugin-react-dom) for React-specific lint rules:

```js
// eslint.config.js
import reactX from 'eslint-plugin-react-x'
import reactDom from 'eslint-plugin-react-dom'

export default defineConfig([
  globalIgnores(['dist']),
  {
    files: ['**/*.{ts,tsx}'],
    extends: [
      // Other configs...
      // Enable lint rules for React
      reactX.configs['recommended-typescript'],
      // Enable lint rules for React DOM
      reactDom.configs.recommended,
    ],
    languageOptions: {
      parserOptions: {
        project: ['./tsconfig.node.json', './tsconfig.app.json'],
        tsconfigRootDir: import.meta.dirname,
      },
      // other options...
    },
  },
])

```

## Modelo de detecção

O app roda um YOLOv8 próprio (`public/models/yolo.tflite`) no browser via
[`@ultralytics/yolo`](https://www.npmjs.com/package/@ultralytics/yolo), que
executa `.tflite` através do LiteRT.js.

- **Classe única:** `Bookshelf-counter` (nome de exibição em `DetectionView.tsx`).
- **Metadata embutido:** `task`, `names` e `imgsz` são lidos de um ZIP anexado ao
  fim do próprio `.tflite`. Qualquer proxy/CDN que recomprima ou trunque o
  arquivo quebra `model.names` — o arquivo precisa ser servido byte a byte.
- **Device:** `auto` (WebGPU quando disponível, senão CPU/wasm). O device que
  rodou de fato aparece na tela inicial.
- **Resolução do `@litertjs/core`:** o `@ultralytics/yolo` o importa por
  especificador indireto marcado com `@vite-ignore`, então o bundler não o
  resolveria. Havia um import map no `index.html` para isso; foi substituído pelo
  plugin `vizi:resolve-litert-in-workers` (`vite.config.ts`), que reescreve
  aquela linha para um import literal e deixa o Vite empacotar. O motivo da troca
  é que **import maps não valem em Web Worker**, e mover a inferência para um
  worker é o caminho de performance (`docs/PERFORMANCE.md` § E7). O plugin falha
  o build se o trecho mudar numa atualização da lib.
  Por causa disso o `@ultralytics/yolo` está em `optimizeDeps.exclude`: sem isso
  o Vite serve em dev uma versão pré-empacotada onde o transform não roda.
- **WASM:** os binários do LiteRT são self-hostados em `public/litert/`, copiados
  de `node_modules` por `npm run vendor` (roda no `predev`/`prebuild`) e apontados
  por `litertWasmUrl` no `YOLO.load()`. Não vêm mais do CDN: tira um terceiro do
  caminho crítico do load e fixa a versão junto com o `package.json`.
- **COOP/COEP:** não habilite sem ler `docs/PERFORMANCE.md` § Fase 1. Foi testado
  e revertido — o WebKit do iPhone não tem relaxed SIMD, que o LiteRT exige para
  o build wasm multi-thread, e o wrapper transforma isso em erro de load.
- **Licença:** `@ultralytics/yolo` e o modelo exportado são AGPL-3.0.
