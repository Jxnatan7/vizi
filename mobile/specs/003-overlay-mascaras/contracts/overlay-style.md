# Contrato — estilo do overlay

A mitigação do princípio IV. O nativo desenha; o TypeScript decide como.

```ts
setOverlayStyle(style: OverlayStyle): Promise<void>
```

| Campo | Regra |
|---|---|
| `showBoxes` | liga e desliga as caixas (FR-003) |
| `showMasks` | liga e desliga as máscaras (FR-003) |
| `boxWidth` | espessura em pixels de imagem, não de tela |
| `maskOpacity` | 0 a 1 |
| `palette` | lista de cores; a atribuição por objeto é do nativo |
| `minConfidence` | abaixo disto não desenha — independente do limiar da detecção |

**Por que `minConfidence` é separado.** O limiar da detecção decide o que
*existe*; este decide o que *aparece*. Separá-los permite ver o efeito de cada
um sem recompilar — e é a diferença entre um overlay poluído e um legível.

**Espessura em pixels de imagem.** O overlay vive no espaço 640×640 do modelo,
ampliado pelo compositor. Espessura em pixels de tela mudaria com o tamanho da
view; em pixels de imagem, a proporção é estável.

## Regras invioláveis

1. **Nenhum pixel de máscara atravessa a fronteira.** O JavaScript envia estilo
   e recebe contagem. Nada mais.
2. **Aplicar estilo não reinicia a sessão.** Trocar cor ou opacidade em execução
   não pode custar um frame sequer.
3. **O desenho não bloqueia a fila da câmera** (princípio I, R12).
4. **O overlay nunca apaga por falta de resultado novo** (FR-009).
