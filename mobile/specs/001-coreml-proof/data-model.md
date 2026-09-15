# Fase 1 — Modelo de dados

Três entidades. Nenhuma é persistida: todas vivem durante uma sessão do app.

---

## Modelo

O artefato de segmentação embarcado no pacote do aplicativo.

| Atributo | Descrição |
|----------|-----------|
| identificador | nome da variante, para distinguir medições de modelos diferentes |
| formato de entrada | dimensões e disposição de canais esperadas |
| classes | mapa de índice para nome |
| normalização | como os valores de pixel são escalados antes da execução |

**Regra.** Estes valores são lidos dos **metadados do próprio modelo**.
**Nenhum é duplicado em código** — um shape escrito à mão em TypeScript que
discorde do modelo é um erro que só aparece como resultado silenciosamente
errado.

Não há `manifest.json` separado: o modelo exportado já carrega `names`, `imgsz`,
`stride` e `task` em `userDefined`. Um manifesto ao lado seria uma segunda
fonte da verdade, exatamente o que a regra proíbe.

### Shapes reais do modelo exportado

Medidos em 15/09/2026, `vizi-seg.mlpackage`, 6,5 MB:

| | Valor | Leitura |
|---|---|---|
| entrada | `imageType 640×640 RGB` | **não é multiArray** — o Core ML aceita buffer de pixel direto e faz conversão no caminho acelerado |
| detecção | `[1, 37, 8400]` fp32 | 37 = 4 caixa + 1 classe + 32 coeficientes; 8400 âncoras = 80² + 40² + 20² |
| protótipos | `[1, 32, 160, 160]` fp32 | entrada ÷ 4 |
| classes | `{0: "book"}` | classe única |
| pesos | fp16 | `quantize: 16` |

Detalhe completo em `models/vizi-seg.shapes.md`.

**Consequência de fronteira.** Detecção crua ≈ 1,2 MB e protótipos ≈ 3,2 MB por
execução. Ambos ordens de grandeza acima do limite de 64 KB do princípio II —
confirmando que a decodificação tem de acontecer no lado nativo.

---

## Amostra de referência

Imagem fixa versionada, com a saída que a ferramenta de treino produziu para
ela.

| Atributo | Descrição |
|----------|-----------|
| imagem | recurso embarcado, do conjunto de validação |
| instâncias esperadas | lista de detecções de referência |
| tolerância | desvio aceito de posição ao comparar |

**Por que existe.** Sem ela, uma conversão de modelo degradada passaria
despercebida: a latência pareceria ótima e a saída estaria errada. É o que
sustenta a história P3.

---

## Registro de medição

O resultado de uma sequência, com o contexto que a torna comparável.

| Atributo | Descrição |
|----------|-----------|
| repetições | quantas execuções a sequência fez |
| descartadas | quantas foram tratadas como aquecimento |
| latência da primeira | custo da primeira execução, isolado (**FR-004**) |
| mediana, p95, mínimo | agregados sobre as execuções válidas |
| latência de ciclo completo | mesmos agregados incluindo preparação e decodificação (**FR-014**) |
| condição térmica | estado do aparelho no momento (**FR-005**) |
| unidade de execução | onde o modelo rodou, ou declaração de indisponível (**FR-006**, **FR-015**) |
| instâncias detectadas | saída decodificada, para comparar com a referência |

**Regra de fronteira.** Este registro é a **única** coisa que atravessa para o
JavaScript. É um objeto de dezenas de campos e algumas dezenas de instâncias —
na casa de um kilobyte. A imagem, os tensores de saída e os protótipos ficam do
lado nativo, conforme o princípio II.
