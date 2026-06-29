# tbNFe Export Workspace

Workspace isolado para baixar os dados do relatorio `tbNFe - DIFAL NF-e por emitente`
em chunks, usando o motor Freeform SQL ja existente no projeto.

## O que foi reaproveitado

- `../src/difal_report_chunks.py`: login, pagina, execucao em chunks e escrita do workbook.

## Arquivos

- `download_tb_nfe.py`: CLI para executar o download.
- `download_tb_nfe_itens_top.py`: CLI para baixar itens apenas dos contribuintes priorizados no top da `tbNFe`.
- `notebooks/tb_nfe_chunks.ipynb`: notebook de operacao e inspecao rapida.
- `sql/tb_nfe.sql`: SQL base validada no MicroStrategy.
- `outputs/`: saida local dos workbooks gerados.

## Como usar

Dry run:

```bash
uv run python tb_nfe/download_tb_nfe.py --dry-run
```

Execucao padrao:

```bash
uv run python tb_nfe/download_tb_nfe.py
```

Baixar itens dos top selecionados:

```bash
uv run python tb_nfe/download_tb_nfe_itens_top.py --top-n 20
```

Esse comando lê `outputs/tb_nfe_2022-04-05_a_2025-12-31.xlsx`, seleciona os maiores potenciais do `consolidado` e busca no MicroStrategy apenas os itens desses CNPJs. A saída padrão é:

```text
outputs/tb_nfe_itens_top20_2022-04-05_a_2025-12-31.xlsx
```

Para carregar esses itens na tela gerencial:

```bash
uv run python malhas_agent/load_malhas_db.py --only tbNFeItens --source-dir .
```

## Estrategia de chunks

- Primeiro tenta mensal.
- Se houver falha, reprocessa com 15 dias.
- Se ainda houver falha, tenta 7 dias.
- O workbook final e salvo em `outputs/`.

## Observacoes

- O SQL base fica preservado no arquivo `.sql`; o script injeta apenas as datas do periodo informado.
- A pasta `outputs/` fica ignorada por git para nao misturar artefatos gerados com o codigo.
