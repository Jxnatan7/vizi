# mobile

App React Native + Expo de detecção e segmentação em tempo real. **Ainda não
foi criado** — esta pasta é o lugar reservado para ele.

## O que vai aqui

```
app/                    telas (Expo Router)
src/vision/             pipeline, tracker, render, controle adaptativo
modules/vizi-vision/    Expo Module nativo — Core ML (iOS) / LiteRT (Android)
models/                 .mlpackage + manifest
tools/                  export e avaliação do modelo (Python)
```

## Decisões já tomadas

- **Expo com Continuous Native Generation** — a pasta `ios/` não é versionada.
  Toda configuração nativa vive em config plugins no `app.config.js`, porque sem
  Mac não há como editar um projeto Xcode.
- **`expo-dev-client`**, não Expo Go. Expo Go é um binário pré-compilado e não
  aceita módulo nativo próprio.
- **Build no GitHub Actions** (runner macOS, sem assinatura), assinatura local
  com `zsign` e instalação com `ideviceinstaller`.
- **Três relógios independentes**: câmera, inferência e display. O loop de
  desenho nunca espera o resultado do modelo.

## Primeiro marco

Carregar o modelo Core ML e medir a inferência sobre uma imagem fixa embutida —
sem câmera, sem overlay, sem tracking. Mais a cadeia de build inteira.

**Portão de saída:** inferência < 30 ms no iPhone 14 Plus. Se falhar, a premissa
do projeto está errada e a arquitetura muda.
