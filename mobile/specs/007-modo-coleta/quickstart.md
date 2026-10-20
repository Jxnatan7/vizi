# Quickstart — validar o modo coleta

Build e instalação seguem o [marco 1](../001-coreml-proof/quickstart.md).
**Medir em Release**, pelas razões de sempre.

O portão tem duas metades: o aparelho (fluidez, tempo, comportamento) e o zip
(fidelidade). A segunda roda fora do aparelho, com
[`tools/check-zip.py`](./tools/check-zip.py), que lê o
[formato](./contracts/zip-format.md) e refaz cada contagem.

## No aparelho, em ordem

**1. Ligar.** Na câmera, ligar o modo coleta. O indicador aparece: ponto,
tempo, 0 marcas, 0 capturas, alguns kB. Iniciar a câmera depois de ligar
também vale — a coleta não depende dela.

**2. Marcar.** Com a faixa sobre uma prateleira, tocar em marcar. A tela para
no quadro, com as mesmas caixas e a mesma faixa, e pede a contagem real
preenchida com o número da pílula. Corrigir com +/− e confirmar: a câmera
volta e o indicador conta 1 marca. Repetir pulando, e repetir com a faixa
desligada — o pedido vem com a contagem do quadro.

**3. Marcar em movimento.** Dez marcas com o aparelho se movendo devagar ao
longo da estante. Elas são o **SC-005**, conferido no zip (passo 12).

**4. Marcar quando não pode.** Com um resultado na tela, durante uma captura e
com o modo desligado, não há como marcar (FR-010).

**5. Capturar.** Dez capturas da mesma prateleira, com o modo ligado,
respondendo a contagem real. O resultado aparece como sempre; o pedido vem
preenchido com a contagem do cartão. Anotar o `toque → pronto` de cada uma —
**SC-004**, abaixo de 1,5 s nas dez. Salvar uma no histórico e não salvar as
outras: o histórico ganha só a salva.

**6. Sair sem responder.** Uma captura, voltar à câmera sem responder. Uma
marca, trocar de aba com o quadro parado. As duas ficam sem `truth.json`.

**7. A sessão de 5 minutos — SC-001.** Uma sessão de pelo menos 5 min com pelo
menos 10 marcas e 10 capturas (os passos 2 a 6 contam). A telemetria fica no
próprio zip (`telemetry.jsonl`): fora dos instantes de captura, `fpsCaptured`
em 60; depois de cada captura e de cada marca, de volta a 60. O cartão de
telemetria da câmera mostra o mesmo ao vivo.

**8. Fechar.** Desligar o modo. A sessão aparece na Medição com marcas,
capturas, respostas e tamanho. Ligar e desligar sem fazer nada: nenhuma sessão
nova na lista (FR-019).

**9. Aba e segundo plano.** Com o modo ligado, ir ao Histórico e voltar: o
indicador continua contando. Na Medição, a sessão aparece em andamento, sem
exportar. Mandar o app para segundo plano: ao voltar, o modo está desligado e a
sessão fechada. Puxar a Central de Controle **não** fecha.

**10. Encerrado à força — SC-006.** Com o modo ligado, três marcas e uma
captura, e encerrar o app pelo seletor logo depois da captura. Ao abrir de
novo, a sessão está fechada e exportável, com os itens que terminaram de
gravar, e nenhum pela metade.

**11. Exportar.** Dar um nome à sessão do passo 7 e exportar. O menu de
compartilhar abre com o zip; mandar para o Linux (AirDrop para outro aparelho,
Arquivos, ou `ifuse --documents com.jxnatan7.vizi` em `collection/`). Exportar
de novo funciona, e a sessão continua na lista. Apagar outra sessão: some da
lista e da pasta.

**12. Espaço.** Num build de desenvolvimento, subir `minFreeBytes` em
`src/collection/policy.ts` para algo maior que o disco e recarregar o
JavaScript — sem rebuild nativo: marcar é recusado com aviso, e a captura
acontece com um aviso de que não foi gravada (FR-020). Voltar o valor.

**13. Diagnóstico e recusa.** Uma captura com o diagnóstico ligado e uma da
faixa sobre uma parede vazia: as duas gravadas, com as imagens que existiram e
o motivo nos dados.

## No zip

```bash
python3 specs/007-modo-coleta/tools/check-zip.py ~/Downloads/vizi-coleta-*.zip
```

O script lê o `FORMAT.md` de dentro do zip só para conferir a versão, e
então, item por item:

| Confere | Critério |
|---|---|
| a contagem refeita a partir de `box`, `band` e `reread.core` é a que a tela mostrou — `result.count` nas capturas, `frameCount` nas marcas | **SC-002**, 100% dos itens |
| cada `truth.json` está na pasta do item a que foi dado, e as respostas dos passos 2, 5 e 6 batem com o que foi digitado | **SC-002** |
| toda captura com `crop.jpg` tem as quatro imagens; as outras dizem por quê (`result.declineReason`, `result.countSource`) | **SC-003** |
| as caixas das dez marcas do passo 3, desenhadas sobre `square.jpg`, caem sobre os livros — o script grava as imagens com as caixas para olhar | **SC-005** |
| nenhuma `.tmp-*`, e toda pasta de item tem `item.json` e as imagens que ele lista | **SC-006** |

Ele também imprime, para cada item com resposta, a contagem do app contra a
real, e quantas detecções abaixo do limiar havia — o primeiro número de
verdade sobre o modelo, que é o motivo de tudo isso.
