# Fase 1 — Modelo de dados

O que vai no zip está no [formato](./contracts/zip-format.md); o que atravessa a
ponte, no [contrato](./contracts/collection.md). Aqui ficam as entidades novas,
o arquivo das prateleiras e os estados da câmera com a coleta aberta.

## Prateleira

Um lugar da casa. Vive em `Documents/shelves.json`, fora das sessões (R49).

| Atributo | Regra |
|---|---|
| id | gerado ao cadastrar, `s-<tempo em base 36>-<aleatório>`; nunca muda |
| nome | obrigatório, sem repetir (ignorando maiúsculas e espaços nas pontas) |
| número | inteiro ≥ 0 — o inventário, pela [regra de contagem](../../models/regra-de-contagem.md) |
| criada em | milissegundos desde a época |

- **Renomear e mudar o número** valem dali em diante. Os itens já gravados
  guardam nome e número do momento (`tags.shelf`).
- **Apagar** tira a prateleira da lista, da escolha e do guia. O contador dela
  some junto.
- **"Sem livros"** não é uma prateleira: é a escolha `background` (FR-008), sem
  id, sem número e sem cadastro.

## Guia

Para cada prateleira, luz e célula, quantas capturas de treino foram gravadas;
e quantas fotos sem livros, por luz.

| Célula | Valores |
|---|---|
| distância | `near` (perto), `mid` (média), `far` (longe) |
| ângulo | `left` (esquerda), `front` (frente), `right` (direita) |
| luz | `day`, `night` — a da sessão |

São 9 células por luz e 18 por prateleira. A ordem, os rótulos e as descrições
vêm de `src/collection/policy.ts` (FR-014); a diagonal da foto inteira (R53)
usa os índices dessa ordem.

**Sobe** quando uma captura de treino volta com `collectionItemId`. **Não
desce** quando uma sessão é apagada (FR-012). Uma célula está "feita" com uma
captura ou mais; o número aparece para a pessoa saber que repetiu.

## O arquivo `shelves.json`

```json
{
  "version": 1,
  "shelves": [
    { "id": "s-mf2k1x-4f", "name": "sala 1", "count": 22, "createdAt": 1792600000000 }
  ],
  "coverage": {
    "s-mf2k1x-4f": { "day": { "near-front": 2, "mid-left": 1 }, "night": {} }
  },
  "background": { "day": 4, "night": 0 }
}
```

- **Sem arquivo** não é erro: nenhuma prateleira, guia vazio.
- **Uma escrita por vez**, em fila, como o índice do histórico: duas capturas
  seguidas leriam o mesmo arquivo, e a segunda escrita apagaria a primeira.
- **`version`** muda quando um campo muda de significado. Um arquivo com versão
  que o app não conhece não é sobrescrito: a Medição diz que não conseguiu ler.

## A escolha na câmera

O que a próxima captura vai gravar como `tags`. Vive na tela, enquanto a sessão
estiver aberta, e **persiste de uma captura para a outra** (FR-002).

| Sessão | O que precisa estar escolhido para capturar (FR-003) |
|---|---|
| treino | uma prateleira **e** uma célula; ou "sem livros" |
| prova | uma prateleira |
| sem tipo (aberta antes desta versão do app) | nada — o fluxo da 007 |
| nenhuma | nada — fora do modo |

- Trocar de prateleira mantém a célula; escolher "sem livros" a esquece.
- Uma prateleira apagada enquanto escolhida deixa a escolha vazia.
- Fechar a sessão esquece a escolha. A próxima sessão começa vazia: escolher é
  um toque, e começar com a escolha de ontem gravaria a prateleira errada sem
  ninguém ver.

## Os estados da câmera

```
                          capturar (treino)
         ┌──────────────────────────────────────────────┐
         │                                              ▼
       live ── capturar (prova, sem tipo, fora) ──▶ capturing ──▶ result ── voltar ──▶ live
         ▲                                              │
         └──── dismissResult imediato, sem 'result' ────┘
                        (treino: R48)
```

- **No treino**, `capturing` volta direto a `live`: o resultado não é
  mostrado, a pergunta não aparece, "salvar no histórico" não existe. O
  indicador recebe a nota da captura — gravada, com prateleira e célula; ou o
  motivo de não ter sido.
- **Na prova**, o fluxo é o da 007, e a pergunta vem preenchida com
  `tags.shelf.count`, mostrando também a contagem do app (FR-009).
- **Ligar o modo** passa por uma escolha antes de abrir: treino de dia, treino
  de noite ou prova. Cancelar não abre sessão.

## Pacote e relatório

Saídas da [ferramenta](./contracts/ferramentas.md), fora do app. Nada delas
volta ao aparelho.

- **Pacote**: imagens e um `_annotations.coco.json`. Cada imagem sabe de qual
  sessão, item, prateleira, célula e luz veio, pelo nome.
- **Relatório da prova**: por captura e por prateleira, a contagem do app
  contra o gabarito, e as prateleiras sem captura.
