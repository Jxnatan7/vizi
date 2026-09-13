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
- **Import map (`index.html`):** o `@ultralytics/yolo` importa o `@litertjs/core`
  por especificador indireto marcado com `@vite-ignore`, então o bundler não o
  resolve — quem resolve é o import map. Sem ele o app quebra com
  `Failed to resolve module specifier '@litertjs/core'`, tanto em dev quanto em
  produção. A versão no import map precisa acompanhar a do `package.json`.
- **WASM:** os binários do LiteRT vêm do CDN padrão (jsDelivr). Se um dia a
  página ficar `cross-origin-isolated` (COOP/COEP), o CDN para de funcionar e é
  preciso self-hostar `node_modules/@litertjs/core/wasm/` apontando
  `litertWasmUrl` no `YOLO.load()`.
- **Licença:** `@ultralytics/yolo` e o modelo exportado são AGPL-3.0.
