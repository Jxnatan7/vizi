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

React Native + Expo, com um Expo Module nativo que faz o trabalho pesado:
câmera, Core ML, overlay, captura e retificação. O iOS vem primeiro, medido num
iPhone 14 Plus; o Android fica para o fim e ainda não começou.

O que existe hoje, spec a spec:

- **A premissa se sustentou.** A inferência custa **3,1 ms** de mediana no
  Neural Engine — 90× mais rápida que o protótipo web no mesmo aparelho.
- **Câmera ao vivo a 60 fps**, com inferência em todo frame e telemetria
  construída no próprio app: sem Mac, não há Instruments.
- **Caixas e máscaras** desenhadas sobre a imagem sem perder um quadro.
- **Apontar, apertar, contar.** Uma foto de 12 MP conta os livros, endireita a
  estante e guarda o resultado num histórico.
- **Faixa de interesse.** A pessoa escolhe com os dedos a prateleira que conta.
- **Releitura do recorte.** A contagem é a da imagem na tela: o recorte
  endireitado, lido por último pelo modelo, com as caixas sobre ele.
- **Modo coleta.** Grava capturas e quadros marcados com a contagem real ao
  lado, e exporta tudo num zip — o gabarito para medir e retreinar o modelo.

As quatro últimas têm o código completo e ainda fecham portões no aparelho. O
estado de cada spec, com as medições, está em [mobile/README.md](mobile/README.md).

Tudo sai do Linux, sem Mac: o GitHub Actions compila, e a assinatura e a
instalação no iPhone são locais.

O desenvolvimento é **dirigido por spec**, com
[GitHub Spec Kit](https://github.com/github/spec-kit). Nada é implementado fora
do ciclo `perguntar → specify → plan → tasks → implement`, e uma spec só fecha
com o portão medido no aparelho. As regras estão na
[constituição](mobile/.specify/memory/constitution.md).

```bash
cd mobile && claude      # as skills vivem em mobile/.claude/skills/
```

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
