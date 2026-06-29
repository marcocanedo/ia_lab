# tbRec Export Workspace

Workspace para extrair os recolhimentos efetuados no periodo da malha.

## O que ele entrega

- `tb_rec.parquet`: base completa de recolhimentos por `CD_INSCRICAO_CNPJ_CPF`.
- `tb_rec_resumo.xlsx`: Excel leve para inspeção, com resumo, amostra, `top_n` e `manifest`.

## Como usar

Dry run:

```bash
uv run python tb_rec/download_tb_rec.py --dry-run
```

Execução:

```bash
uv run python tb_rec/download_tb_rec.py
```

## Regra da extração

A SQL soma `VL_REC` em `P_ACCDB.FAT_GUIA_RECOL`, no período de `2022-04-05` a `2025-12-31`, agrupando por `CD_INSCRICAO_CNPJ_CPF`.

O arquivo principal é Parquet para acelerar a carga no DuckDB. O Excel é apenas uma visão operacional pequena.
