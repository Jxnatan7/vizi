# Contrato — faixa de interesse

```ts
startSession(options: SessionOptions): Promise<SessionInfo>
// SessionOptions.band: BandPolicy — a sessão começa com a faixa padrão

setBandMode(mode: BandMode): Promise<void>
setOverlayStyle(style: OverlayStyle): Promise<void>
// OverlayStyle ganha a aparência da faixa

// evento
onBandChange(state: BandState): void
```

```ts
type BandMode = 'off' | 'horizontal' | 'vertical';

type BandState = {
  mode: BandMode;
  /** No eixo em que a faixa anda, de 0 a 1. */
  center: number;
  /** Fração da imagem nesse eixo, de 0 a 1. */
  thickness: number;
};
```

Os campos de `BandPolicy` e da aparência estão no
[modelo de dados](../data-model.md), com os valores iniciais.

## `setBandMode` — o que a cápsula chama

| de → para | efeito |
|---|---|
| desligada → orientação | volta à última faixa ligada da sessão, virando se for a outra orientação |
| uma orientação → a outra | vira mantendo centro e espessura |
| ligada → `off` | a faixa se abre até a moldura e some |
| para o modo atual | nada |

Sempre animado. O retorno tátil é do nativo, venha a troca da cápsula ou do
gesto. `onBandChange` dispara ao terminar.

## `CaptureResult`

| Campo novo | Regra |
|---|---|
| `outsideBandCount` | detecções da foto descartadas pela faixa; zero com a faixa desligada |

A contagem, a geometria e o recorte já chegam filtrados: `count` passa a ser a
contagem **da faixa**.

## Gestos — o contrato de interface

| gesto | onde | efeito | retorno tátil |
|---|---|---|---|
| arrastar com um dedo | na imagem, fora das bordas | move a faixa no eixo livre | ao encostar no limite |
| arrastar com um dedo | sobre uma borda (44 pt) | move só aquela borda | no mínimo e no limite |
| dois dedos | na imagem | seguram as bordas: posição e espessura juntas | — |
| girar os dois dedos além da diagonal | — | vira a faixa | ao virar |
| afastar os dois dedos além da imagem | — | desliga | ao desligar |
| dois dedos com a faixa desligada | na imagem | cria a faixa entre eles | ao criar |
| dois toques | na faixa | volta ao centro e à espessura padrão | ao voltar |
| cápsula | abaixo da imagem | imagem toda · horizontal · vertical | ao trocar |

Um toque simples não faz nada. Nenhum gesto sobre a imagem rola a tela.

## Regras invioláveis

1. **O nativo é a fonte da verdade.** O JavaScript espelha o estado para
   desenhar a cápsula; nunca o dirige quadro a quadro (princípio III).
2. **Nada atravessa durante o arrasto.** `onBandChange` só em mudança discreta.
3. **Uma faixa só**, nas coordenadas da imagem canônica, para o ao vivo e para a
   captura.
4. **A captura lê a faixa no toque do botão** e filtra antes da geometria.
5. **Sessão nova, faixa nova:** horizontal, no centro, `defaultThickness`.
