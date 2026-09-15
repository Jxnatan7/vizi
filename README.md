# vizi

Detecção e segmentação de objetos em tempo real com YOLO, on-device.

O repositório guarda dois projetos independentes que compartilham o assunto, os
modelos e o aprendizado — mas nenhuma linha de código.

```
web/      protótipo em React + Vite  ·  encerrado, mantido como referência
mobile/   app React Native + Expo    ·  em construção
```

## web/ — o protótipo

Roda YOLO no navegador via `@ultralytics/yolo` sobre LiteRT. **Está encerrado**,
e é mantido porque a investigação de performance registrada em
[web/docs/PERFORMANCE.md](web/docs/PERFORMANCE.md) e
[web/docs/PREMIUM.md](web/docs/PREMIUM.md) é o que fundamenta as decisões do app
mobile.

O resumo do que ele provou: o caminho wasm/CPU do Safari no iOS é single-thread
(sem relaxed SIMD em ARM, threads são inalcançáveis), a inferência custa ~280 ms
e nenhuma API web chega ao Neural Engine. O teto é estrutural, não de
implementação.

```bash
npm run web          # dev server
npm run web:build    # build de produção
npm run web:lint
```

## mobile/ — o app

React Native + Expo, com módulo nativo para inferência: Core ML na ANE no iOS,
LiteRT com delegate de GPU no Android.

Ainda não implementado. O projeto está configurado para **Spec-Driven
Development** com [GitHub Spec Kit](https://github.com/github/spec-kit): a
constituição e os marcos estão escritos, e nada é implementado fora do ciclo
`specify → clarify → plan → tasks → implement`.

```bash
cd mobile && claude      # as skills vivem em mobile/.claude/skills/
```

Ver [mobile/README.md](mobile/README.md) e
[a constituição](mobile/.specify/memory/constitution.md).

## Por que não há workspaces

Cada projeto instala as próprias dependências, com o próprio lockfile. Não há
workspaces de npm e isso é deliberado:

- os dois projetos **não compartilham nenhuma dependência** — um é Vite, o outro
  é Metro;
- o hoisting de workspaces é a causa mais comum de quebra em projetos React
  Native, e resolver isso custaria configuração de Metro sem entregar nada.

Monorepo aqui significa um repositório com dois projetos, não um grafo de
pacotes. Se algum dia surgir código realmente compartilhado, workspaces entram
junto com ele.

```bash
npm install --prefix web      # instala as dependências do protótipo web
```

Os scripts na raiz são apenas atalhos com `--prefix`; `npm install` na raiz não
instala nada.
