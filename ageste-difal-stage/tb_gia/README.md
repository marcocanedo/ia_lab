# tbGia Export Workspace

Workspace isolado para baixar a GIA-ST declarada em chunks mensais e prepará-la para ingestão no DuckDB.

## O que ele entrega

- `tb_gia_2022-04-01_a_2025-12-31.parquet`: arquivo principal, com todas as linhas retornadas por período.
- `tb_gia_2022-04-01_a_2025-12-31_resumo.xlsx`: Excel leve para inspeção manual, com resumo, amostra, `top_n` e `manifest`.
- `top_n`: maiores valores de `Difal`, com desempate determinístico.
- `manifest`: registro de tentativas, status e quantidade de linhas.

## Arquivos

- `download_tb_gia.py`: CLI para executar o download.
- `notebooks/tb_gia_chunks.ipynb`: notebook de operação e inspeção rápida.
- `sql/tb_gia.sql`: SQL base validada no MicroStrategy.
- `outputs/`: saída local dos workbooks gerados.

## Como usar

Dry run:

```bash
uv run python tb_gia/download_tb_gia.py --dry-run
```

Execução padrão:

```bash
uv run python tb_gia/download_tb_gia.py
```

O formato principal é Parquet porque a extração completa pode passar de milhões de linhas. Excel continua existindo apenas como resumo operacional para abrir rapidamente.

## Estratégia de chunks

- Primeiro tenta mensal.
- Se houver falha, reprocessa com 15 dias.
- Se ainda houver falha, tenta 7 dias.
- O Parquet final e o Excel de resumo são salvos em `outputs/`.

## Observações

- A janela padrão cobre `2022-04-01` a `2025-12-31`.
- A SQL converte esse intervalo em `DT_ANO_MES_REF` no formato `YYYYMM`.
- A pasta `outputs/` fica ignorada por git para não misturar artefatos gerados com o código.
