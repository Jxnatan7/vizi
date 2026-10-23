# Quickstart — validar a coleta para treino e prova

Build e instalação seguem o [marco 1](../001-coreml-proof/quickstart.md).
**Medir em Release.** A ferramenta roda no Linux:
[`mobile/tools/coleta.py`](../../tools/coleta.py), pelo
[contrato](./contracts/ferramentas.md).

## No aparelho

**1. Prateleiras.** Na Medição, cadastrar três prateleiras com o número do
inventário. Renomear uma, mudar o número de outra, fechar e abrir o app: as
três continuam, com as mudanças.

**2. Ligar o treino.** Na câmera, ligar o modo coleta: o app pergunta treino de
dia, treino de noite ou prova. Escolher treino de dia. Capturar está desligado,
e a tela diz que falta escolher a prateleira.

**3. Treino rápido — SC-001.** Escolher uma prateleira e uma célula no guia, e
capturar. A câmera volta sem resultado nem pergunta; o indicador diz "c0001 ·
sala 1 · perto · frente", e a célula fica marcada. Fazer **20 capturas
seguidas**, mudando a célula, com **duas** em "sem livros". Anotar a volta ao
vivo de cada uma: abaixo de 1,5 s. A telemetria do zip mostra 60 fps de volta
depois de cada uma.

**4. Guia — SC-006.** Desligar. Na Medição, a prateleira mostra quantas das 9
têm foto de dia. Fazer uma sessão de treino de noite com três células, desligar
e apagar as duas sessões: o guia continua igual.

**5. Prova — SC-005.** Ligar como prova. Para cada prateleira cadastrada,
escolher e capturar duas vezes. O resultado aparece; a pergunta vem com o
número do inventário e diz quanto o app contou. Confirmar. Desligar.

**6. Fora do modo — SC-007.** Com o modo desligado, cinco capturas: resultado
como antes, abaixo de 1,5 s, e salvar no histórico funciona.

**7. Exportar** as sessões do passo 3 e do 5 e levá-las ao Linux.

## No Linux

```bash
cd mobile
uv run tools/coleta.py pacote ~/vizi-coleta-<treino>.zip --saida /tmp/pacote
uv run tools/coleta.py pacote ~/vizi-coleta-<prova>.zip --saida /tmp/x    # recusa
uv run tools/coleta.py pacote ../vizi-coleta-2026-10-20T10-41-44 --saida /tmp/y  # recusa
uv run tools/coleta.py pacote ../vizi-coleta-2026-10-20T10-41-44 --sem-tipo --saida /tmp/antigas
uv run tools/coleta.py prova ~/vizi-coleta-<prova>.zip
```

| Confere | Critério |
|---|---|
| o pacote do treino traz o recorte de toda captura com recorte, a foto de uma em cada três por prateleira e a das duas sem livros, com os nomes do contrato | **SC-002** |
| o resumo não recusa nenhuma imagem na conferência de equivalência | **SC-003** |
| a prova e a sessão sem tipo são recusadas; com `--sem-tipo`, a de 20/10 vira pacote de 12 recortes | **SC-004** |
| o relatório traz as capturas da prova, com o inventário como gabarito, e nenhuma prateleira faltando | **SC-005** |

## No Roboflow — SC-002

1. No projeto do dataset (segmentação, classe `book`), **Upload**: soltar
   primeiro o `_annotations.coco.json`, depois as imagens da pasta. Esperar a
   associação terminar antes de salvar.
2. Nenhuma imagem recusada. Abrir **10 imagens sorteadas**: os contornos caem
   sobre os livros, um por livro, nenhum repetido.
3. **Conferir as fotos sem livros:** se chegaram como imagens vazias ("null")
   ou como "não anotadas". No segundo caso, marcá-las como vazias e anotar isso
   no README (research, R54).
4. Buscar por `sala-1` no nome: aparecem as imagens daquela prateleira.
5. **Não gerar versão ainda.** A versão nova vem depois de corrigir os
   contornos, com a mesma redução do dataset — esticar para 640×640.
