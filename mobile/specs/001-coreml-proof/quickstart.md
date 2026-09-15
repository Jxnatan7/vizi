# Quickstart — do repositório limpo ao app medindo no iPhone

Satisfaz o **SC-007**: repetível do zero sem consultar histórico de conversa.

> Os passos marcados 🔬 dependem de incógnitas abertas em
> [research.md](./research.md) e serão preenchidos com o procedimento exato
> quando os experimentos fecharem. O restante já está determinado.

---

## Parte 1 — Exportar o modelo (Colab, uma vez por mudança de modelo)

Roda onde vivem o dataset e os pesos. O repositório recebe só o resultado.

```python
!pip install -U ultralytics coremltools

from ultralytics import YOLO

model = YOLO("best.pt")

model.export(
    format="coreml",
    imgsz=640,          # quadrado: a geometria em que o modelo foi treinado
    half=True,          # fp16: formato nativo do acelerador
    nms=False,          # NMS embutido tira operacoes do acelerador
)
```

**Por que quadrado e não retangular.** A câmera entrega 4:3, e exportar em
480×640 economizaria 25% da computação. Mas **o dataset é 640×640**, e o modelo
aprendeu essa proporção. Exportar retangular comprimiria os livros em 25%
horizontalmente em relação a tudo que ele viu no treino — mudança de proporção,
não de escala, e a degradação seria silenciosa.

A economia continua disponível, pelo caminho certo: **retreinar** em 480×640.
Isso é decisão para depois de haver um número de latência, não antes.

**Por que `nms=False`:** o NMS embutido insere operações que o compilador não
coloca no acelerador dedicado, e arrasta camadas vizinhas junto. A decodificação
acontece em Swift, onde custa uma fração de milissegundo.

**Conferir logo após exportar**, ainda no Colab:

```python
import coremltools as ct
m = ct.models.MLModel("best.mlpackage")
print(m.get_spec().description)
```

Um modelo de segmentação deve expor **duas saídas** — detecção e protótipos de
máscara. Se só houver uma, o ramo de máscara não veio e o marco 5 fica sem
matéria-prima. Anotar os shapes em `models/vizi-seg.shapes.md`: são a fonte da
verdade para o módulo nativo.

### A imagem de referência

**Uma imagem do conjunto de validação, em 640×640** — o mesmo formato do
dataset e da entrada do modelo.

Por que isso importa: com a imagem já no formato exato da entrada, **nenhum dos
dois caminhos redimensiona**. O `predict` não faz letterbox e o Core ML não
estica. Os dois veem pixels idênticos, e a comparação da US3 mede só o que
deveria — se a conversão preservou o comportamento, e não uma diferença de
geometria.

Escolher uma com quantidade média de instâncias: poucas não exercitam a
decodificação, muitas tornam a comparação frágil porque detecções na borda da
confiança entram e saem.

Gerar a saída de referência na mesma sessão:

```python
r = model.predict("reference.jpg", imgsz=640, conf=0.25)[0]

import json
json.dump({
    "classes":     r.boxes.cls.tolist(),
    "confidences": r.boxes.conf.tolist(),
    "boxes_xyxy":  r.boxes.xyxy.tolist(),
}, open("reference-expected.json", "w"), indent=2)
```

Baixar do Colab (o `.mlpackage` é uma **pasta**, então compactar antes):

```python
!zip -r vizi-seg.mlpackage.zip best.mlpackage
from google.colab import files
files.download("vizi-seg.mlpackage.zip")
files.download("reference-expected.json")
```

Commitar:

```
mobile/models/vizi-seg.mlpackage/     <- versionado de proposito
mobile/models/vizi-seg.shapes.md
mobile/assets/reference.jpg
mobile/assets/reference-expected.json
```

---

## Parte 2 — Preparar o ambiente local (uma vez)

```bash
cd mobile && npm install
```

🔬 Ferramentas de assinatura e instalação — ver R1.

---

## Parte 3 — Compilar (a cada mudança nativa, raro)

Disparado por push na branch. O runner macOS executa:

```
expo prebuild --platform ios     # gera ios/ a partir de app.config.js
pod install
xcodebuild  (sem assinatura)
empacota o app compilado em um .ipa
```

O artefato fica disponível para download. Repositório público, runners macOS
gratuitos e ilimitados — não há orçamento de build a economizar.

---

## Parte 4 — Assinar e instalar (a cada compilação, e a cada 7 dias)

🔬 Procedimento exato depende de R1.

A forma será: baixar o artefato, assinar localmente com o certificado da conta
Apple gratuita, instalar no aparelho conectado por USB.

**A cada 7 dias** a assinatura expira e o app para de abrir. A recuperação
repete **apenas esta parte** — sem recompilar (**SC-006**).

---

## Parte 5 — Iterar no JavaScript (o ciclo normal)

```bash
cd mobile && npx expo start
```

Abrir o app no aparelho e conectar. Alterações em `src/` e `App.tsx` aparecem
sem recompilar (**SC-004**). Só `modules/vizi-vision/` e dependências nativas
exigem voltar à Parte 3.

---

## Parte 6 — Medir

1. Aparelho o mais frio possível. Fechar outros apps.
2. Abrir o app e anotar a **latência da primeira execução** — ela inclui
   preparação do modelo e não se repete.
3. Disparar a sequência de 100 repetições.
4. Ler mediana, p95, condição térmica e unidade de execução.
5. Conferir as instâncias detectadas contra `reference-expected.json`.

**O portão:** mediana < 30 ms e p95 < 40 ms, com o aparelho em temperatura
normal, e instâncias batendo com a referência.

**Se o aparelho estiver quente,** a medição não é comparável com uma anterior a
frio. O protótipo web mediu variação de 264 a 317 ms no mesmo modelo por causa
de temperatura — cerca de 20%. Abaixo disso, diferença não é distinguível de
ruído.
