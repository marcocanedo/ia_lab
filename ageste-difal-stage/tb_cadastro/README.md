# tbCadastro Snapshot

Workspace isolado para o snapshot de `DIM_PESSOA` x `DIM_DRR` usado como base de cruzamento.
Ele foi desenhado para ser consumido junto com a extracao anterior e com mais duas bases que ainda virao.

## O que ele entrega

- Snapshot unico, sem recorte temporal.
- Colunas brutas preservadas no workbook.
- Visao canonica no inicio do conjunto de colunas, com a chave de cruzamento `NU_CNPJ_CPF` + `NU_IE_ST`.
- Consolidacao deduplicada por `NU_CNPJ_CPF` e `NU_IE_ST`.

## Arquivos

- `download_tb_cadastro.py`: CLI para executar o snapshot.
- `notebooks/tb_cadastro.ipynb`: notebook de operacao e inspecao rapida.
- `sql/tb_cadastro.sql`: SQL base validada no MicroStrategy.
- `outputs/`: saida local dos workbooks gerados.

## Como usar

Dry run:

```bash
uv run python tb_cadastro/download_tb_cadastro.py --dry-run
```

Execucao padrao:

```bash
uv run python tb_cadastro/download_tb_cadastro.py
```

## Regra de consolidacao

- O snapshot pagina tudo em uma unica execucao.
- `consolidado` remove duplicidade por `NU_CNPJ_CPF` + `NU_IE_ST`.
- `top_n` e apenas uma visao de apoio para leitura rapida.

## Observacoes

- O workbook final e gravado em `outputs/tb_cadastro.xlsx` por padrao.
- A pasta `outputs/` fica ignorada por git para nao misturar artefatos gerados com o codigo.
