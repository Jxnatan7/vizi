# vizi-seg.mlpackage — shapes verificados

Lidos com `coremltools` em 15/09/2026. Fonte da verdade para o módulo nativo.

| | Valor |
|---|---|
| entrada | `image` — `imageType` 640×640 RGB |
| detecção | `var_1011` — `[1, 37, 8400]` fp32 |
| protótipos | `var_1049` — `[1, 32, 160, 160]` fp32 |
| pesos | fp16 (`quantize: 16`) |
| classes | `{0: "book"}` |
| stride | 32 |
| nms | `False` — decodificação em Swift |

**37** = 4 caixa + 1 classe + 32 coeficientes de máscara.
**8400** âncoras = 80² + 40² + 20², dos strides 8/16/32 sobre 640.
**160×160** = entrada ÷ 4.

**Os nomes `var_1011` e `var_1049` são automáticos e mudam entre exports.**
Resolver por forma: 3 dimensões é detecção, 4 dimensões são protótipos.
Ver `specs/001-coreml-proof/contracts/vizi-vision.md`.
