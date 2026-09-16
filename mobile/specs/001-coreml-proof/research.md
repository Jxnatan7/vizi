# Fase 0 — Pesquisa

Cinco incógnitas. As três primeiras podem reprovar o marco; as duas últimas só
afetam quanto trabalho ele dá.

Ordenadas por risco. Cada uma tem um experimento que a fecha — nenhuma se
resolve lendo documentação, porque este projeto já aprendeu que tabela de
compatibilidade mente e o teste no aparelho é a verdade.

---

## R1 — RESOLVIDO (15/09/2026)

App instalado e aberto no iPhone 14 Plus, iOS 26. O maior risco do marco caiu.

O caminho que funcionou: fork `jaakkopalvaila/AltServer-Linux` release
`ng-2026-09-13`, com `ALTSERVER_ANISETTE_SERVER=https://ani.sidestore.io`.

**As duas coisas que quase derrubaram:**

1. **Todo servidor de anisette público padrão está morto.** O embutido no
   AltServer e o do Sideloadly devolvem HTTP 502. O sintoma engana: o AltServer
   tenta ler a página de erro como JSON e reclama de `Content-Type`, sem dizer
   que o problema é o servidor de anisette.
2. **A Apple bloqueia `com.apple.dt.Xcode` no header de client-info desde
   setembro de 2026**, com HTTP 503. Isso quebrou AltServer, AltStore e
   SideStore ao mesmo tempo. Só o fork NG contorna, trocando por
   `com.apple.akd`. O upstream está quebrado.

**Beco sem saída evitado:** `nyamisty/alt_anisette_server` roda Wine com iCloud
para Windows e automatiza login por AutoHotkey — exige credenciais Apple
próprias no container e não serve como servidor local trivial.

### Aparelho confirmado (16/09/2026)

Primeira leitura real do `probe()` no alvo:

| | |
|---|---|
| sistema | iOS 26.5 (23F75) |
| núcleos | 6 — A15, 2 performance + 4 eficiência |
| memória | 5684 MB |

Confirma o alvo da arquitetura e descarta a hipótese de mock: nenhum desses
valores vem do JavaScript.

### Achado colateral: Debug e Release não são intercambiáveis

A inspeção do `.ipa` instalado mostrou `main.jsbundle` embutido e **nenhum
`EXDevLauncher`**. O workflow compilava só em Release.

Consequência: aquele build **não satisfaz o SC-004** — não há como alterar
JavaScript e ver no aparelho sem recompilar, porque o JS está embutido e o dev
client não existe no pacote.

E o inverso também vale, e é mais perigoso: **um build Debug não serve para
medir.** O Swift compila com `-Onone`, então `Decode.swift` roda sem otimização
e o `cycleMs` sai inflado. Medir o portão (SC-001) em Debug produziria um
número falso — e, por ser falso *para pior*, poderia reprovar o marco sem
motivo.

O workflow passou a compilar **os dois**, em matriz:

| configuração | para quê |
|---|---|
| `Debug` | dev launcher + Metro; é o que permite iterar em JS (SC-004) |
| `Release` | JS embutido, Swift otimizado; é o único válido para medir (SC-001) |

Runners macOS são gratuitos em repositório público, então o custo é tempo de
fila, não dinheiro.

---

## R1 — o registro original

**Risco: o mais alto do marco.** Se não fechar, nada roda no aparelho e o
projeto inteiro para.

**Incógnita.** O procedimento de obter certificado de desenvolvimento e perfil
de provisionamento com Apple ID gratuito, a partir de Linux, sem nenhum Mac.

**Candidatos.** Ferramentas de código aberto do ecossistema de sideload
(AltServer-Linux, SideStore) automatizam a conversa com a Apple usando as
credenciais da conta. `libimobiledevice` cuida da comunicação com o aparelho,
e `zsign` assina o pacote.

**Como fechar.** Instalar um app trivial qualquer no aparelho antes de escrever
uma linha do app de verdade. Se isso não funcionar, o marco muda de forma.

**Incerteza declarada.** Esse ecossistema muda rápido e não tenho estado atual
verificado. O experimento é a única fonte confiável.

**Plano B.** Conta Apple paga resolve o problema em minutos. É a saída, não a
primeira tentativa.

---

## Resolvido antes do prazo — export (15/09/2026)

O export fechou parte de R2 e R3, e **derrubou uma premissa do plano**.

### A entrada retangular foi revertida

O primeiro export usou `imgsz=[640, 480]`, seguindo a recomendação da
arquitetura de casar a entrada com o sensor 4:3 e economizar 25% da computação.
Funcionou tecnicamente — entrada `480×640`, 6300 âncoras coerentes com os
strides.

**Mas o dataset é 640×640.** O modelo foi treinado em quadrado, e exportar
retangular comprime os objetos em 25% horizontalmente contra tudo que ele viu.
Mudança de proporção degrada em silêncio: nenhum erro, só resultado pior.

A economia continua disponível, mas pelo caminho certo — **retreinar** em
480×640 — e isso é decisão para depois de haver um número de latência.

**Lição:** "casar a entrada com o sensor" é argumento sobre a câmera. A
geometria de export é decidida pelo **treino**, não pelo sensor.

Reexportado em `imgsz=640`. Shapes verificados com `coremltools`:

| | Valor |
|---|---|
| entrada | `imageType` 640×640 RGB |
| detecção | `[1, 37, 8400]` |
| protótipos | `[1, 32, 160, 160]` |

### O que veio de graça

- **As duas saídas sobreviveram.** O ramo de máscara existe; o marco 5 tem
  matéria-prima.
- **A entrada é do tipo imagem, não multiArray.** O Core ML aceita um buffer de
  pixel direto e faz conversão no caminho acelerado. **Isso elimina um estágio
  inteiro de pré-processamento** que o plano presumia necessário.
- **A imagem de referência dispensa tratamento.** Sendo 640×640 do dataset, ela
  entra sem redimensionar nos dois caminhos — o `predict` não faz letterbox e o
  Core ML não estica. A comparação da US3 mede só a conversão.

**O que continua aberto em R2:** saber se o grafo roda de fato no acelerador
dedicado. O export ter funcionado não diz nada sobre isso — só a medição no
aparelho dirá.

---

## R2 — O Neural Engine executa o grafo de segmentação?

**Risco: alto.** É a premissa da arquitetura.

**Incógnita.** Um modelo de segmentação tem, além do caminho de detecção, um
ramo de protótipos de máscara. Nem toda operação tem implementação no
acelerador dedicado, e o compilador pode empurrar parte do grafo para unidades
mais lentas — arrastando junto as camadas vizinhas por causa do custo de
transferência.

**Como fechar.** Medir com as unidades de computação irrestritas e comparar com
execuções forçadas a caminhos mais lentos. Se a diferença for pequena, o
acelerador não está sendo usado de fato.

**A investigar.** Versões recentes do sistema expõem uma API de plano de
computação que informa a atribuição por operação. Se existir e funcionar no
aparelho alvo, é a resposta direta ao **FR-006** e dispensa inferir por
comparação de tempos. **Precisa ser confirmado no aparelho** — não assumir que
existe.

**Se falhar.** O ramo de máscara é separado do de detecção em dois modelos, com
os protótipos indo para a GPU. Custa trabalho, não inviabiliza.

---

## R3 — Embarcar e carregar o modelo num módulo nativo do Expo

**Risco: médio.** Problema de mecânica, não de viabilidade.

**Incógnita.** O Core ML consome um modelo compilado, não o pacote exportado
direto. A compilação pode acontecer durante o build ou em tempo de execução, na
primeira abertura.

**A tensão.** Compilar em tempo de execução simplifica o build mas coloca um
custo grande na primeira abertura do app — e esse custo é justamente o que o
**FR-004** manda reportar separadamente. Compilar durante o build exige que o
projeto gerado pelo `prebuild` inclua o modelo como recurso, o que precisa ser
feito por config plugin, já que a pasta nativa não é versionada.

**Como fechar.** Medir a compilação em tempo de execução primeiro, por ser mais
simples. Se o custo de primeira abertura for inaceitável, mover para o build.

**Atualização (15/09/2026).** O modelo está em `mobile/models/vizi-seg.mlpackage`,
6,5 MB — pequeno o bastante para versionar sem atrito. O que resta de R3 é só a
mecânica de incluí-lo no bundle por config plugin e compilá-lo.

---

## R4 — Compilar sem assinatura e empacotar no CI

**Risco: baixo.** Caminho conhecido, só precisa ser montado.

**Incógnita.** A sequência exata para produzir um pacote instalável num runner
macOS sem nenhuma credencial da Apple: desabilitar a assinatura na compilação,
e montar o pacote manualmente a partir do aplicativo compilado.

**Como fechar.** Um workflow que compila e publica o artefato. Repositório é
público, então os minutos de macOS são gratuitos e ilimitados — não há
orçamento de build a otimizar neste marco.

---

## R5 — Quantas execuções de aquecimento descartar

**Risco: baixo**, mas mede errado se ignorado.

**Incógnita.** Quantas primeiras execuções são atípicas. A primeira certamente
é — carrega e prepara o modelo. Se a segunda e a terceira também forem, uma
mediana sobre tudo fica contaminada.

**Como fechar.** Registrar as latências individuais das primeiras 20 execuções
de uma sequência e olhar onde a curva estabiliza. O número de descarte sai daí,
medido, e vira constante em TypeScript — não em Swift, pelo princípio IV.

---

## Decisões que não precisam de pesquisa

Já fixadas pela constituição ou pelas respostas do autor:

| Decisão | Valor |
|---------|-------|
| Export do modelo | roda no Colab; o repositório recebe o artefato pronto |
| Resultado esperado da referência | gerado uma vez no Colab, versionado como JSON |
| Saída da medição | apenas na tela do app; sem exportação nem envio |
| Navegação | nenhuma; uma tela |
| Android | fora do escopo |
