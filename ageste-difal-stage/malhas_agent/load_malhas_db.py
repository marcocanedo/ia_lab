from __future__ import annotations

import argparse
import hashlib
import json
import uuid
from dataclasses import asdict, dataclass, replace
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import duckdb
import pandas as pd

from app_db import init_management_tables


ROOT = Path(__file__).resolve().parents[1]
WORKSPACE_ROOT = Path(__file__).resolve().parent
DEFAULT_DB_PATH = WORKSPACE_ROOT / "db" / "malhas.duckdb"


@dataclass(frozen=True)
class SourceSpec:
    name: str
    raw_table: str
    stg_table: str
    default_file: Path
    sheet_prefixes: tuple[str, ...] = ("chunks",)
    optional: bool = False


SOURCES: dict[str, SourceSpec] = {
    "tbNFe": SourceSpec(
        name="tbNFe",
        raw_table="raw_tbNFe",
        stg_table="stg_tbNFe",
        default_file=ROOT
        / "tb_nfe"
        / "outputs"
        / "tb_nfe_2022-04-05_a_2025-12-31.xlsx",
    ),
    "tbNFeItens": SourceSpec(
        name="tbNFeItens",
        raw_table="raw_tbNFeItens",
        stg_table="stg_tbNFeItens",
        default_file=ROOT
        / "tb_nfe"
        / "outputs"
        / "tb_nfe_itens_top20_2022-04-05_a_2025-12-31.xlsx",
        sheet_prefixes=("itens_top20",),
    ),
    "tbCadastro": SourceSpec(
        name="tbCadastro",
        raw_table="raw_tbCadastro",
        stg_table="stg_tbCadastro",
        default_file=ROOT / "tb_cadastro" / "outputs" / "tb_cadastro.xlsx",
        optional=True,
    ),
    "tbGia": SourceSpec(
        name="tbGia",
        raw_table="raw_tbGia",
        stg_table="stg_tbGia",
        default_file=ROOT / "tb_gia" / "outputs" / "tb_gia_2022-04-01_a_2025-12-31.parquet",
    ),
    "tbRec": SourceSpec(
        name="tbRec",
        raw_table="raw_tbRec",
        stg_table="stg_tbRec",
        default_file=ROOT / "tb_rec" / "outputs" / "tb_rec.parquet",
    ),
    "extracao_4": SourceSpec(
        name="extracao_4",
        raw_table="raw_extracao_4",
        stg_table="stg_extracao_4",
        default_file=ROOT / "extracao_4" / "outputs" / "extracao_4.xlsx",
        optional=True,
    ),
    "extracao_5": SourceSpec(
        name="extracao_5",
        raw_table="raw_extracao_5",
        stg_table="stg_extracao_5",
        default_file=ROOT / "extracao_5" / "outputs" / "extracao_5.xlsx",
        optional=True,
    ),
}

DEFAULT_SOURCE_NAMES = ["tbNFe", "tbNFeItens", "tbGia", "tbRec"]


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _qident(identifier: str) -> str:
    return '"' + identifier.replace('"', '""') + '"'


def _digits_expr(column: str) -> str:
    quoted = _qident(column)
    return f"NULLIF(regexp_replace(CAST({quoted} AS VARCHAR), '[^0-9]', '', 'g'), '')"


def _money_expr(column: str) -> str:
    quoted = _qident(column)
    clean = f"regexp_replace(CAST({quoted} AS VARCHAR), '[^0-9,.-]', '', 'g')"
    return (
        f"CASE WHEN CAST({quoted} AS VARCHAR) LIKE '%,%' "
        f"THEN try_cast(replace(replace({clean}, '.', ''), ',', '.') AS DOUBLE) "
        f"ELSE try_cast(regexp_replace(CAST({quoted} AS VARCHAR), '[^0-9.-]', '', 'g') AS DOUBLE) END"
    )


def _file_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _resolve_source_file(spec: SourceSpec) -> Path:
    if spec.default_file.exists():
        return spec.default_file

    parent = spec.default_file.parent
    if spec.name == "tbNFeItens" and parent.exists():
        candidates = sorted(parent.glob("tb_nfe_itens_top*.xlsx"))
        if not candidates:
            candidates = sorted(parent.glob("tb_nfe_itens_lote_*.xlsx"))
        non_empty = [candidate for candidate in candidates if candidate.is_file() and candidate.stat().st_size > 0]
        if non_empty:
            return max(non_empty, key=lambda candidate: (candidate.stat().st_size, candidate.stat().st_mtime))

    return spec.default_file


def _read_workbook_rows(path: Path, prefixes: tuple[str, ...]) -> pd.DataFrame:
    sheets = pd.read_excel(path, sheet_name=None, dtype=object)
    selected: list[pd.DataFrame] = []
    for sheet_name, frame in sheets.items():
        lower_name = str(sheet_name).lower()
        if any(lower_name.startswith(prefix.lower()) for prefix in prefixes):
            selected.append(frame)

    if not selected and sheets:
        selected.append(next(iter(sheets.values())))

    if not selected:
        return pd.DataFrame()

    data = pd.concat(selected, ignore_index=True)
    data = data.dropna(how="all")
    data.columns = [str(column).strip() for column in data.columns]
    return data.where(pd.notna(data), None)


def _read_parquet_rows(path: Path) -> pd.DataFrame:
    data = pd.read_parquet(path, engine="pyarrow")
    data = data.dropna(how="all")
    data.columns = [str(column).strip() for column in data.columns]
    return data.where(pd.notna(data), None)


def _read_source_rows(path: Path, prefixes: tuple[str, ...]) -> pd.DataFrame:
    suffix = path.suffix.lower()
    if suffix == ".parquet":
        return _read_parquet_rows(path)
    if suffix in {".xlsx", ".xlsm", ".xls"}:
        return _read_workbook_rows(path, prefixes)
    raise ValueError(f"Formato de origem nao suportado: {path.suffix}")


def _table_exists(conn: duckdb.DuckDBPyConnection, table_name: str) -> bool:
    result = conn.execute(
        "SELECT count(*) FROM information_schema.tables WHERE table_name = ?",
        [table_name],
    ).fetchone()
    return bool(result and result[0])


def _table_columns(conn: duckdb.DuckDBPyConnection, table_name: str) -> list[str]:
    if not _table_exists(conn, table_name):
        return []
    rows = conn.execute(f"DESCRIBE {_qident(table_name)}").fetchall()
    return [str(row[0]) for row in rows]


def _has_columns(conn: duckdb.DuckDBPyConnection, table_name: str, columns: list[str]) -> bool:
    current = set(_table_columns(conn, table_name))
    return all(column in current for column in columns)


def _ensure_empty_raw_table(conn: duckdb.DuckDBPyConnection, table_name: str) -> None:
    conn.execute(
        f"""
        CREATE TABLE IF NOT EXISTS {_qident(table_name)} (
            run_id VARCHAR,
            source_file VARCHAR,
            loaded_at VARCHAR
        )
        """
    )


def _register_manifest(
    conn: duckdb.DuckDBPyConnection,
    *,
    run_id: str,
    source_name: str,
    source_file: Path,
    source_hash: str,
    status: str,
    started_at: str,
    finished_at: str,
    rows_loaded: int,
    raw_table: str,
    error: str = "",
) -> None:
    conn.execute(
        """
        INSERT INTO manifest_execucoes (
            run_id, source_name, source_file, source_hash, status,
            started_at, finished_at, rows_loaded, raw_table, error
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [
            run_id,
            source_name,
            str(source_file),
            source_hash,
            status,
            started_at,
            finished_at,
            rows_loaded,
            raw_table,
            error,
        ],
    )


def create_control_tables(conn: duckdb.DuckDBPyConnection) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS manifest_execucoes (
            run_id VARCHAR,
            source_name VARCHAR,
            source_file VARCHAR,
            source_hash VARCHAR,
            status VARCHAR,
            started_at VARCHAR,
            finished_at VARCHAR,
            rows_loaded BIGINT,
            raw_table VARCHAR,
            error VARCHAR
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS quality_checks (
            run_id VARCHAR,
            checked_at VARCHAR,
            check_name VARCHAR,
            table_name VARCHAR,
            severity VARCHAR,
            rows_affected BIGINT,
            details VARCHAR
        )
        """
    )
    init_management_tables(conn)


def load_source(conn: duckdb.DuckDBPyConnection, spec: SourceSpec, source_file: Path) -> dict[str, Any]:
    run_id = str(uuid.uuid4())
    started_at = _now_iso()
    source_file = _resolve_source_file(replace(spec, default_file=source_file))
    if not source_file.exists():
        _ensure_empty_raw_table(conn, spec.raw_table)
        _register_manifest(
            conn,
            run_id=run_id,
            source_name=spec.name,
            source_file=source_file,
            source_hash="",
            status="missing",
            started_at=started_at,
            finished_at=_now_iso(),
            rows_loaded=0,
            raw_table=spec.raw_table,
            error="Arquivo de origem nao encontrado." if not spec.optional else "Arquivo opcional de origem nao encontrado.",
        )
        status = "missing_optional" if spec.optional else "missing"
        return {"source": spec.name, "status": status, "rows_loaded": 0, "file": str(source_file)}

    try:
        frame = _read_source_rows(source_file, spec.sheet_prefixes)
        frame = frame.astype("string").where(pd.notna(frame), None)
        loaded_at = _now_iso()
        frame.insert(0, "loaded_at", loaded_at)
        frame.insert(0, "source_file", str(source_file))
        frame.insert(0, "run_id", run_id)

        existing_columns = _table_columns(conn, spec.raw_table)
        if existing_columns:
            for column in frame.columns:
                if column not in existing_columns:
                    conn.execute(f"ALTER TABLE {_qident(spec.raw_table)} ADD COLUMN {_qident(column)} VARCHAR")
                    existing_columns.append(column)
            for column in existing_columns:
                if column not in frame.columns:
                    frame[column] = None
            frame = frame[existing_columns]
            conn.register("incoming_rows", frame)
            conn.execute(f"INSERT INTO {_qident(spec.raw_table)} SELECT * FROM incoming_rows")
            conn.unregister("incoming_rows")
        else:
            conn.register("incoming_rows", frame)
            conn.execute(f"CREATE TABLE {_qident(spec.raw_table)} AS SELECT * FROM incoming_rows")
            conn.unregister("incoming_rows")

        source_hash = _file_hash(source_file)
        _register_manifest(
            conn,
            run_id=run_id,
            source_name=spec.name,
            source_file=source_file,
            source_hash=source_hash,
            status="ok",
            started_at=started_at,
            finished_at=_now_iso(),
            rows_loaded=len(frame),
            raw_table=spec.raw_table,
        )
        return {"source": spec.name, "status": "ok", "rows_loaded": len(frame), "file": str(source_file)}
    except Exception as exc:
        _ensure_empty_raw_table(conn, spec.raw_table)
        _register_manifest(
            conn,
            run_id=run_id,
            source_name=spec.name,
            source_file=source_file,
            source_hash="",
            status="error",
            started_at=started_at,
            finished_at=_now_iso(),
            rows_loaded=0,
            raw_table=spec.raw_table,
            error=str(exc),
        )
        return {"source": spec.name, "status": "error", "rows_loaded": 0, "file": str(source_file), "error": str(exc)}


def _create_empty_staging(conn: duckdb.DuckDBPyConnection, table_name: str, columns: dict[str, str]) -> None:
    column_sql = ", ".join(f"{_qident(name)} {kind}" for name, kind in columns.items())
    conn.execute(f"CREATE OR REPLACE TABLE {_qident(table_name)} ({column_sql})")


def rebuild_staging_tables(conn: duckdb.DuckDBPyConnection) -> None:
    if _has_columns(conn, "raw_tbCadastro", ["NU_CNPJ_CPF", "NU_IE_ST", "NU_CNPJ8", "NU_CNPJ", "NU_IE"]):
        conn.execute(
            f"""
            CREATE OR REPLACE TABLE stg_tbCadastro AS
            WITH latest AS (
                SELECT * FROM raw_tbCadastro
                WHERE loaded_at = (SELECT max(loaded_at) FROM raw_tbCadastro)
            )
            SELECT
                run_id,
                loaded_at,
                {_digits_expr('NU_CNPJ_CPF')} AS cnpj_cpf_norm,
                {_digits_expr('NU_CNPJ')} AS cnpj_norm,
                {_digits_expr('NU_CNPJ8')} AS cnpj8_norm,
                {_digits_expr('NU_IE')} AS ie_norm,
                {_digits_expr('NU_IE_ST')} AS ie_st_norm,
                concat(coalesce({_digits_expr('NU_CNPJ_CPF')}, ''), '|', coalesce({_digits_expr('NU_IE_ST')}, '')) AS chave_cnpj_ie_st,
                "CD_PESSOA",
                "CD_DRR",
                "NM_PESSOA",
                "NM_FANTASIA",
                "DT_FIM_ATIV",
                CASE WHEN NULLIF(CAST("DT_FIM_ATIV" AS VARCHAR), '') IS NOT NULL THEN TRUE ELSE FALSE END AS contribuinte_baixado
            FROM latest
            """
        )
    else:
        _create_empty_staging(
            conn,
            "stg_tbCadastro",
            {
                "run_id": "VARCHAR",
                "loaded_at": "VARCHAR",
                "cnpj_cpf_norm": "VARCHAR",
                "cnpj_norm": "VARCHAR",
                "cnpj8_norm": "VARCHAR",
                "ie_norm": "VARCHAR",
                "ie_st_norm": "VARCHAR",
                "chave_cnpj_ie_st": "VARCHAR",
                "CD_PESSOA": "VARCHAR",
                "CD_DRR": "VARCHAR",
                "NM_PESSOA": "VARCHAR",
                "NM_FANTASIA": "VARCHAR",
                "DT_FIM_ATIV": "VARCHAR",
                "contribuinte_baixado": "BOOLEAN",
            },
        )

    if _has_columns(conn, "raw_tbGia", ["NU_CNPJ", "NU_IE", "NU_IE_ST", "Difal"]):
        conn.execute(
            f"""
            CREATE OR REPLACE TABLE stg_tbGia AS
            WITH latest AS (
                SELECT * FROM raw_tbGia
                WHERE loaded_at = (SELECT max(loaded_at) FROM raw_tbGia)
            )
            SELECT
                run_id,
                loaded_at,
                {_digits_expr('NU_CNPJ')} AS cnpj_norm,
                {_digits_expr('NU_IE')} AS ie_norm,
                {_digits_expr('NU_IE_ST')} AS ie_st_norm,
                {_money_expr('Difal')} AS difal_gia,
                "CD_MUN_ANALIT",
                "NM_MUN_IBGE",
                "CD_UF",
                "CD_SIGLA_UF",
                "CD_DRR",
                "DS_DRR"
            FROM latest
            """
        )
    else:
        _create_empty_staging(
            conn,
            "stg_tbGia",
            {
                "run_id": "VARCHAR",
                "loaded_at": "VARCHAR",
                "cnpj_norm": "VARCHAR",
                "ie_norm": "VARCHAR",
                "ie_st_norm": "VARCHAR",
                "difal_gia": "DOUBLE",
                "CD_MUN_ANALIT": "VARCHAR",
                "NM_MUN_IBGE": "VARCHAR",
                "CD_UF": "VARCHAR",
                "CD_SIGLA_UF": "VARCHAR",
                "CD_DRR": "VARCHAR",
                "DS_DRR": "VARCHAR",
            },
        )

    if _has_columns(conn, "raw_tbRec", ["CD_INSCRICAO_CNPJ_CPF", "TotalRec"]):
        conn.execute(
            f"""
            CREATE OR REPLACE TABLE stg_tbRec AS
            WITH latest AS (
                SELECT * FROM raw_tbRec
                WHERE loaded_at = (SELECT max(loaded_at) FROM raw_tbRec)
            )
            SELECT
                run_id,
                loaded_at,
                {_digits_expr('CD_INSCRICAO_CNPJ_CPF')} AS inscricao_norm,
                {_money_expr('TotalRec')} AS valor_recolhido
            FROM latest
            """
        )
    else:
        _create_empty_staging(
            conn,
            "stg_tbRec",
            {
                "run_id": "VARCHAR",
                "loaded_at": "VARCHAR",
                "inscricao_norm": "VARCHAR",
                "valor_recolhido": "DOUBLE",
            },
        )

    if _has_columns(conn, "raw_tbNFe", ["CNPJEmit", "NmEmit", "UFEmit", "QTD_DOC", "TOTAL_ITEM", "DIFAL_DEST"]):
        conn.execute(
            f"""
            CREATE OR REPLACE TABLE stg_tbNFe AS
            WITH latest AS (
                SELECT * FROM raw_tbNFe
                WHERE loaded_at = (SELECT max(loaded_at) FROM raw_tbNFe)
            )
            SELECT
                max(run_id) AS run_id,
                max(loaded_at) AS loaded_at,
                {_digits_expr('CNPJEmit')} AS cnpj_norm,
                max("NmEmit") AS nome_emitente,
                max("UFEmit") AS uf_emitente,
                sum(coalesce({_money_expr('QTD_DOC')}, 0)) AS qtd_doc,
                sum(coalesce({_money_expr('TOTAL_ITEM')}, 0)) AS total_item,
                sum(coalesce({_money_expr('DIFAL_DEST')}, 0)) AS difal_nfe
            FROM latest
            GROUP BY cnpj_norm
            """
        )
    else:
        _create_empty_staging(
            conn,
            "stg_tbNFe",
            {
                "run_id": "VARCHAR",
                "loaded_at": "VARCHAR",
                "cnpj_norm": "VARCHAR",
                "nome_emitente": "VARCHAR",
                "uf_emitente": "VARCHAR",
                "qtd_doc": "DOUBLE",
                "total_item": "DOUBLE",
                "difal_nfe": "DOUBLE",
            },
        )

    item_required_columns = [
        "IdNFe",
        "DtEmissao",
        "NmEmit",
        "CNPJEmit",
        "CadICMSEmit",
        "UFEmit",
        "CD_CNPJ_CPF_PARTICIPANTE",
        "CD_IE_PARTICIPANTE",
        "UF_PARTICIPANTE",
        "NCM",
        "CEST",
        "CST",
        "CFOP",
        "GTINItem",
        "DescItem",
        "VlTotalItem",
        "VlBaseCalculoICMS",
        "AliquotaICMS",
        "VlICMS",
        "VlBaseCalculoICMSST",
        "AliquotaICMSST",
        "VlICMSST",
        "VL_ALIQ_UF_DEST",
        "VL_ICMS_UF_DEST",
        "VL_ICMS_FCP_UF_DEST",
    ]
    if _has_columns(conn, "raw_tbNFeItens", item_required_columns):
        conn.execute(
            f"""
            CREATE OR REPLACE TABLE stg_tbNFeItens AS
            WITH latest AS (
                SELECT * FROM raw_tbNFeItens
                WHERE loaded_at = (SELECT max(loaded_at) FROM raw_tbNFeItens)
            )
            SELECT
                run_id,
                loaded_at,
                source_file,
                "IdNFe",
                "DtEmissao",
                "ModeloDoc",
                "SerieDoc",
                "NrDoc",
                "CdFinalidadeNFe",
                "TpOperacao",
                "NmEmit",
                {_digits_expr('CNPJEmit')} AS cnpj_emit_norm,
                {_digits_expr('CadICMSEmit')} AS ie_emit_norm,
                "MunicipioEmit",
                "UFEmit",
                "NM_PARTICIPANTE",
                {_digits_expr('CD_CNPJ_CPF_PARTICIPANTE')} AS cnpj_participante_norm,
                {_digits_expr('CD_IE_PARTICIPANTE')} AS ie_participante_norm,
                "MUNIC_PARTICIPANTE",
                "UF_PARTICIPANTE",
                "CD_TIPO_IE_DEST",
                "NrItem",
                {_digits_expr('GTINItem')} AS gtin_norm,
                "CdItem",
                "DescItem",
                lower(regexp_replace(CAST("DescItem" AS VARCHAR), '\\s+', ' ', 'g')) AS desc_item_norm,
                {_digits_expr('NCM')} AS ncm_norm,
                {_digits_expr('CEST')} AS cest_norm,
                {_digits_expr('CST')} AS cst_norm,
                {_digits_expr('CFOP')} AS cfop_norm,
                {_money_expr('QtdComercial')} AS qtd_comercial,
                "UnidadeTributavel",
                {_money_expr('VlUnitComercial')} AS vl_unit_comercial,
                {_money_expr('VlTotalItem')} AS vl_total_item,
                {_money_expr('QtdTributavel')} AS qtd_tributavel,
                {_money_expr('VlUnitarioTributacao')} AS vl_unit_tributacao,
                {_money_expr('VlFrete')} AS vl_frete,
                {_money_expr('VlSeguro')} AS vl_seguro,
                {_money_expr('VlDesconto')} AS vl_desconto,
                {_money_expr('VlOutro')} AS vl_outro,
                {_money_expr('AliquotaIPI')} AS aliquota_ipi,
                {_money_expr('VlIPI')} AS vl_ipi,
                "CdOrigemMercadoria",
                {_money_expr('VlBaseCalculoICMS')} AS vl_base_calculo_icms,
                {_money_expr('AliquotaICMS')} AS aliquota_icms,
                {_money_expr('VlICMS')} AS vl_icms,
                {_money_expr('PercMVAICMSST')} AS perc_mva_icms_st,
                {_money_expr('PercReducaoBaseCalculoICMSST')} AS perc_reducao_base_icms_st,
                {_money_expr('VlBaseCalculoICMSST')} AS vl_base_calculo_icms_st,
                {_money_expr('AliquotaICMSST')} AS aliquota_icms_st,
                {_money_expr('VlICMSST')} AS vl_icms_st,
                {_money_expr('VL_ALIQ_UF_DEST')} AS vl_aliq_uf_dest,
                {_money_expr('VL_ICMS_UF_DEST')} AS vl_icms_uf_dest,
                {_money_expr('VL_ICMS_FCP_UF_DEST')} AS vl_icms_fcp_uf_dest,
                CASE
                    WHEN coalesce({_money_expr('VlBaseCalculoICMS')}, 0) > 0
                    THEN coalesce({_money_expr('VL_ICMS_UF_DEST')}, 0) / {_money_expr('VlBaseCalculoICMS')} * 100
                    ELSE NULL
                END AS aliquota_efetiva_difal,
                {_money_expr('TotVlBaseCalculoICMS')} AS tot_vl_base_calculo_icms,
                {_money_expr('TotVlICMS')} AS tot_vl_icms,
                {_money_expr('TotVlBaseCalculoICMSST')} AS tot_vl_base_calculo_icms_st,
                {_money_expr('TotVlICMSST')} AS tot_vl_icms_st,
                {_money_expr('TotVlTotalItem')} AS tot_vl_total_item,
                {_money_expr('TotVlFrete')} AS tot_vl_frete,
                {_money_expr('TotVlSeguro')} AS tot_vl_seguro,
                {_money_expr('TotVlDesconto')} AS tot_vl_desconto,
                {_money_expr('TotVlIPI')} AS tot_vl_ipi,
                {_money_expr('TotVlTotalDoc')} AS tot_vl_total_doc
            FROM latest
            """
        )
    else:
        _create_empty_staging(
            conn,
            "stg_tbNFeItens",
            {
                "run_id": "VARCHAR",
                "loaded_at": "VARCHAR",
                "source_file": "VARCHAR",
                "IdNFe": "VARCHAR",
                "DtEmissao": "VARCHAR",
                "NmEmit": "VARCHAR",
                "cnpj_emit_norm": "VARCHAR",
                "ie_emit_norm": "VARCHAR",
                "UFEmit": "VARCHAR",
                "cnpj_participante_norm": "VARCHAR",
                "ie_participante_norm": "VARCHAR",
                "UF_PARTICIPANTE": "VARCHAR",
                "ncm_norm": "VARCHAR",
                "cest_norm": "VARCHAR",
                "cst_norm": "VARCHAR",
                "cfop_norm": "VARCHAR",
                "gtin_norm": "VARCHAR",
                "CdItem": "VARCHAR",
                "DescItem": "VARCHAR",
                "desc_item_norm": "VARCHAR",
                "qtd_comercial": "DOUBLE",
                "UnidadeTributavel": "VARCHAR",
                "vl_unit_comercial": "DOUBLE",
                "vl_total_item": "DOUBLE",
                "qtd_tributavel": "DOUBLE",
                "vl_unit_tributacao": "DOUBLE",
                "vl_frete": "DOUBLE",
                "vl_seguro": "DOUBLE",
                "vl_desconto": "DOUBLE",
                "vl_outro": "DOUBLE",
                "aliquota_ipi": "DOUBLE",
                "vl_ipi": "DOUBLE",
                "CdOrigemMercadoria": "VARCHAR",
                "vl_base_calculo_icms": "DOUBLE",
                "aliquota_icms": "DOUBLE",
                "vl_icms": "DOUBLE",
                "perc_mva_icms_st": "DOUBLE",
                "perc_reducao_base_icms_st": "DOUBLE",
                "vl_base_calculo_icms_st": "DOUBLE",
                "aliquota_icms_st": "DOUBLE",
                "vl_icms_st": "DOUBLE",
                "vl_aliq_uf_dest": "DOUBLE",
                "vl_icms_uf_dest": "DOUBLE",
                "vl_icms_fcp_uf_dest": "DOUBLE",
                "aliquota_efetiva_difal": "DOUBLE",
                "tot_vl_base_calculo_icms": "DOUBLE",
                "tot_vl_icms": "DOUBLE",
                "tot_vl_base_calculo_icms_st": "DOUBLE",
                "tot_vl_icms_st": "DOUBLE",
                "tot_vl_total_item": "DOUBLE",
                "tot_vl_frete": "DOUBLE",
                "tot_vl_seguro": "DOUBLE",
                "tot_vl_desconto": "DOUBLE",
                "tot_vl_ipi": "DOUBLE",
                "tot_vl_total_doc": "DOUBLE",
            },
        )

    for spec_name in ("extracao_4", "extracao_5"):
        spec = SOURCES[spec_name]
        if _table_exists(conn, spec.raw_table):
            conn.execute(
                f"""
                CREATE OR REPLACE TABLE {_qident(spec.stg_table)} AS
                SELECT * FROM {_qident(spec.raw_table)}
                WHERE loaded_at = (SELECT max(loaded_at) FROM {_qident(spec.raw_table)})
                """
            )
        else:
            _create_empty_staging(conn, spec.stg_table, {"run_id": "VARCHAR", "loaded_at": "VARCHAR"})


def rebuild_marts(conn: duckdb.DuckDBPyConnection) -> None:
    conn.execute(
        """
        CREATE OR REPLACE TABLE mart_potencial_arrecadacao AS
        WITH gia AS (
            SELECT cnpj_norm, ie_st_norm, sum(coalesce(difal_gia, 0)) AS difal_gia
            FROM stg_tbGia
            GROUP BY cnpj_norm, ie_st_norm
        ),
        rec AS (
            SELECT inscricao_norm, sum(coalesce(valor_recolhido, 0)) AS valor_recolhido
            FROM stg_tbRec
            GROUP BY inscricao_norm
        )
        SELECT
            coalesce(nfe.cnpj_norm, cad.cnpj_norm, gia.cnpj_norm) AS cnpj_norm,
            cad.cnpj_cpf_norm,
            cad.ie_norm,
            cad.ie_st_norm,
            cad.chave_cnpj_ie_st,
            cad."CD_PESSOA",
            cad."CD_DRR",
            coalesce(cad."NM_PESSOA", nfe.nome_emitente) AS nome_pessoa,
            nfe.uf_emitente,
            coalesce(nfe.qtd_doc, 0) AS qtd_doc,
            coalesce(nfe.total_item, 0) AS total_item,
            coalesce(nfe.difal_nfe, 0) AS difal_nfe,
            coalesce(gia.difal_gia, 0) AS difal_gia,
            coalesce(rec_cnpj.valor_recolhido, rec_ie.valor_recolhido, rec_ie_st.valor_recolhido, 0) AS valor_recolhido,
            coalesce(nfe.difal_nfe, 0) - coalesce(gia.difal_gia, 0) AS gap_nfe_vs_gia,
            coalesce(gia.difal_gia, 0) - coalesce(rec_cnpj.valor_recolhido, rec_ie.valor_recolhido, rec_ie_st.valor_recolhido, 0) AS gap_gia_vs_rec,
            greatest(
                coalesce(nfe.difal_nfe, 0) - coalesce(rec_cnpj.valor_recolhido, rec_ie.valor_recolhido, rec_ie_st.valor_recolhido, 0),
                coalesce(gia.difal_gia, 0) - coalesce(rec_cnpj.valor_recolhido, rec_ie.valor_recolhido, rec_ie_st.valor_recolhido, 0),
                0
            ) AS potencial_arrecadacao,
            cad.contribuinte_baixado,
            CASE WHEN cad.cnpj_norm IS NULL THEN TRUE ELSE FALSE END AS sem_cadastro_drr17,
            CASE WHEN coalesce(rec_cnpj.valor_recolhido, rec_ie.valor_recolhido, rec_ie_st.valor_recolhido, 0) > 0 THEN TRUE ELSE FALSE END AS possui_recolhimento
        FROM stg_tbNFe nfe
        FULL OUTER JOIN stg_tbCadastro cad
        ON nfe.cnpj_norm = cad.cnpj_norm
        FULL OUTER JOIN gia
        ON coalesce(nfe.cnpj_norm, cad.cnpj_norm) = gia.cnpj_norm
        LEFT JOIN rec rec_cnpj
        ON coalesce(nfe.cnpj_norm, cad.cnpj_norm, gia.cnpj_norm) = rec_cnpj.inscricao_norm
        LEFT JOIN rec rec_ie
        ON cad.ie_norm = rec_ie.inscricao_norm
        LEFT JOIN rec rec_ie_st
        ON coalesce(cad.ie_st_norm, gia.ie_st_norm) = rec_ie_st.inscricao_norm
        """
    )
    conn.execute(
        """
        CREATE OR REPLACE TABLE mart_casos_malha AS
        SELECT
            *,
            concat_ws(
                '; ',
                CASE WHEN sem_cadastro_drr17 THEN 'sem cadastro DRR 17' END,
                CASE WHEN contribuinte_baixado THEN 'contribuinte baixado' END,
                CASE WHEN possui_recolhimento THEN 'recolhimento localizado' END,
                CASE WHEN coalesce(cnpj_norm, '') = '' THEN 'sem CNPJ normalizado' END,
                CASE WHEN coalesce(ie_st_norm, '') = '' THEN 'sem IE-ST normalizada' END
            ) AS sinais_falso_positivo,
            CASE
                WHEN potencial_arrecadacao <= 0 THEN 'sem_potencial_aparente'
                WHEN sem_cadastro_drr17 THEN 'revisar_chave'
                WHEN contribuinte_baixado THEN 'revisar_cadastro'
                WHEN possui_recolhimento THEN 'revisar_recolhimento'
                ELSE 'priorizar'
            END AS status_triagem,
            CASE
                WHEN potencial_arrecadacao >= 100000 THEN 100
                WHEN potencial_arrecadacao >= 50000 THEN 80
                WHEN potencial_arrecadacao >= 10000 THEN 60
                WHEN potencial_arrecadacao > 0 THEN 40
                ELSE 0
            END AS score_priorizacao
        FROM mart_potencial_arrecadacao
        ORDER BY potencial_arrecadacao DESC, difal_nfe DESC
        """
    )
    rebuild_item_marts(conn)


def rebuild_item_marts(conn: duckdb.DuckDBPyConnection) -> None:
    conn.execute(
        """
        CREATE OR REPLACE TABLE mart_itens_detalhe AS
        SELECT
            *,
            concat_ws(
                '; ',
                CASE WHEN coalesce(vl_base_calculo_icms, 0) <= 0 THEN 'base ICMS zerada ou nula' END,
                CASE WHEN coalesce(vl_aliq_uf_dest, 0) <= 0 THEN 'aliquota UF destino zerada ou nula' END,
                CASE WHEN coalesce(vl_base_calculo_icms_st, 0) > 0 OR coalesce(vl_icms_st, 0) > 0 THEN 'ST presente' END,
                CASE WHEN coalesce(vl_icms_fcp_uf_dest, 0) > 0 THEN 'FCP presente' END,
                CASE WHEN coalesce(vl_desconto, 0) > greatest(coalesce(vl_total_item, 0) * 0.3, 0) THEN 'desconto relevante' END,
                CASE WHEN cst_norm IN ('40', '41', '50', '51', '60') THEN 'CST potencialmente nao tributado' END,
                CASE WHEN coalesce(ncm_norm, '') = '' THEN 'NCM ausente' END,
                CASE WHEN coalesce(cest_norm, '') = '' AND (coalesce(vl_base_calculo_icms_st, 0) > 0 OR coalesce(vl_icms_st, 0) > 0) THEN 'CEST ausente em item com ST' END,
                CASE WHEN coalesce(gtin_norm, '') = '' THEN 'GTIN ausente' END,
                CASE WHEN coalesce(cnpj_participante_norm, '') = '' OR coalesce(ie_participante_norm, '') = '' THEN 'chave participante incompleta' END,
                CASE WHEN coalesce(vl_total_item, 0) > 0 AND coalesce(vl_icms_uf_dest, 0) / vl_total_item > 0.4 THEN 'DIFAL alto sobre valor do item' END,
                CASE WHEN aliquota_efetiva_difal IS NOT NULL AND coalesce(vl_aliq_uf_dest, 0) > 0 AND abs(aliquota_efetiva_difal - vl_aliq_uf_dest) > 5 THEN 'divergencia aliquota efetiva' END
            ) AS sinais_falso_positivo_item
        FROM stg_tbNFeItens
        """
    )
    conn.execute(
        """
        CREATE OR REPLACE TABLE mart_itens_por_ncm_cfop_cst AS
        SELECT
            ncm_norm,
            cfop_norm,
            cst_norm,
            count(*) AS qtd_itens,
            count(DISTINCT "IdNFe") AS qtd_docs,
            count(DISTINCT cnpj_emit_norm) AS qtd_emitentes,
            sum(coalesce(vl_total_item, 0)) AS vl_total_item,
            sum(coalesce(vl_icms_uf_dest, 0)) AS vl_icms_uf_dest,
            sum(coalesce(vl_icms_fcp_uf_dest, 0)) AS vl_icms_fcp_uf_dest,
            avg(aliquota_efetiva_difal) AS aliquota_efetiva_media,
            count(*) FILTER (WHERE coalesce(sinais_falso_positivo_item, '') <> '') AS qtd_itens_com_sinal
        FROM mart_itens_detalhe
        GROUP BY ncm_norm, cfop_norm, cst_norm
        ORDER BY vl_icms_uf_dest DESC
        """
    )
    conn.execute(
        """
        CREATE OR REPLACE TABLE mart_itens_por_descricao AS
        SELECT
            desc_item_norm,
            any_value("DescItem") AS exemplo_descricao,
            count(*) AS qtd_itens,
            count(DISTINCT "IdNFe") AS qtd_docs,
            count(DISTINCT cnpj_emit_norm) AS qtd_emitentes,
            sum(coalesce(vl_total_item, 0)) AS vl_total_item,
            sum(coalesce(vl_icms_uf_dest, 0)) AS vl_icms_uf_dest,
            sum(coalesce(vl_icms_fcp_uf_dest, 0)) AS vl_icms_fcp_uf_dest,
            count(*) FILTER (WHERE coalesce(sinais_falso_positivo_item, '') <> '') AS qtd_itens_com_sinal
        FROM mart_itens_detalhe
        GROUP BY desc_item_norm
        ORDER BY vl_icms_uf_dest DESC
        """
    )
    conn.execute(
        """
        CREATE OR REPLACE TABLE mart_itens_por_emitente AS
        SELECT
            cnpj_emit_norm,
            any_value("NmEmit") AS nome_emitente,
            any_value("UFEmit") AS uf_emitente,
            count(*) AS qtd_itens,
            count(DISTINCT "IdNFe") AS qtd_docs,
            sum(coalesce(vl_total_item, 0)) AS vl_total_item,
            sum(coalesce(vl_icms_uf_dest, 0)) AS vl_icms_uf_dest,
            sum(coalesce(vl_icms_fcp_uf_dest, 0)) AS vl_icms_fcp_uf_dest,
            count(*) FILTER (WHERE coalesce(sinais_falso_positivo_item, '') <> '') AS qtd_itens_com_sinal
        FROM mart_itens_detalhe
        GROUP BY cnpj_emit_norm
        ORDER BY vl_icms_uf_dest DESC
        """
    )
    conn.execute(
        """
        CREATE OR REPLACE TABLE mart_sinais_falso_positivo_itens AS
        SELECT sinal, count(*) AS qtd_itens, sum(coalesce(vl_icms_uf_dest, 0)) AS vl_icms_uf_dest
        FROM (
            SELECT
                unnest(string_split(sinais_falso_positivo_item, '; ')) AS sinal,
                vl_icms_uf_dest
            FROM mart_itens_detalhe
            WHERE coalesce(sinais_falso_positivo_item, '') <> ''
        )
        WHERE coalesce(sinal, '') <> ''
        GROUP BY sinal
        ORDER BY vl_icms_uf_dest DESC
        """
    )


def run_quality_checks(conn: duckdb.DuckDBPyConnection, run_id: str | None = None) -> list[dict[str, Any]]:
    check_run_id = run_id or str(uuid.uuid4())
    checked_at = _now_iso()
    checks = [
        ("cadastro_sem_chave", "stg_tbCadastro", "warning", "cnpj_cpf_norm IS NULL OR ie_st_norm IS NULL"),
        ("cadastro_chave_duplicada", "stg_tbCadastro", "warning", None),
        ("gia_sem_chave", "stg_tbGia", "warning", "cnpj_norm IS NULL AND ie_st_norm IS NULL AND ie_norm IS NULL"),
        ("gia_valor_negativo", "stg_tbGia", "warning", "difal_gia < 0"),
        ("rec_sem_inscricao", "stg_tbRec", "warning", "inscricao_norm IS NULL"),
        ("rec_valor_negativo", "stg_tbRec", "warning", "valor_recolhido < 0"),
        ("nfe_sem_cnpj", "stg_tbNFe", "warning", "cnpj_norm IS NULL"),
        ("casos_sem_chave_confiavel", "mart_casos_malha", "warning", "cnpj_norm IS NULL AND ie_st_norm IS NULL"),
    ]
    rows: list[dict[str, Any]] = []
    conn.execute("DELETE FROM quality_checks WHERE run_id = ?", [check_run_id])

    for check_name, table_name, severity, predicate in checks:
        if not _table_exists(conn, table_name):
            affected = 0
            details = "Tabela nao existe."
        elif check_name == "cadastro_chave_duplicada":
            affected = conn.execute(
                """
                SELECT count(*) FROM (
                    SELECT chave_cnpj_ie_st
                    FROM stg_tbCadastro
                    WHERE chave_cnpj_ie_st IS NOT NULL AND chave_cnpj_ie_st <> '|'
                    GROUP BY chave_cnpj_ie_st
                    HAVING count(*) > 1
                )
                """
            ).fetchone()[0]
            details = "Quantidade de chaves NU_CNPJ_CPF + NU_IE_ST duplicadas."
        else:
            affected = conn.execute(f"SELECT count(*) FROM {_qident(table_name)} WHERE {predicate}").fetchone()[0]
            details = str(predicate)

        row = {
            "run_id": check_run_id,
            "checked_at": checked_at,
            "check_name": check_name,
            "table_name": table_name,
            "severity": severity,
            "rows_affected": int(affected),
            "details": details,
        }
        rows.append(row)
        conn.execute(
            """
            INSERT INTO quality_checks (
                run_id, checked_at, check_name, table_name, severity, rows_affected, details
            )
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            list(row.values()),
        )

    return rows


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Carrega extracoes de malhas em um banco DuckDB local.")
    parser.add_argument("--db-path", default=str(DEFAULT_DB_PATH), help="Caminho do banco DuckDB.")
    parser.add_argument("--source-dir", default=str(ROOT), help="Raiz dos workspaces de extracao.")
    parser.add_argument("--rebuild", action="store_true", help="Remove o banco existente antes de carregar.")
    parser.add_argument("--only", choices=sorted(SOURCES), action="append", help="Carrega apenas uma fonte. Pode repetir.")
    parser.add_argument("--source-file", help="Arquivo especifico para carregar. Use com exatamente um --only.")
    parser.add_argument("--quality-checks", action="store_true", help="Executa apenas staging, marts e checks no banco atual.")
    parser.add_argument("--dry-run", action="store_true", help="Mostra fontes e arquivos esperados sem carregar.")
    return parser


def _spec_with_source_dir(spec: SourceSpec, source_dir: Path) -> SourceSpec:
    relative_files = {
        "tbCadastro": Path("tb_cadastro") / "outputs" / "tb_cadastro.xlsx",
        "tbGia": Path("tb_gia") / "outputs" / "tb_gia_2022-04-01_a_2025-12-31.parquet",
        "tbRec": Path("tb_rec") / "outputs" / "tb_rec.parquet",
        "tbNFe": Path("tb_nfe")
        / "outputs"
        / "tb_nfe_2022-04-05_a_2025-12-31.xlsx",
        "tbNFeItens": Path("tb_nfe")
        / "outputs"
        / "tb_nfe_itens_top20_2022-04-05_a_2025-12-31.xlsx",
        "extracao_4": Path("extracao_4") / "outputs" / "extracao_4.xlsx",
        "extracao_5": Path("extracao_5") / "outputs" / "extracao_5.xlsx",
    }
    relative_file = relative_files.get(spec.name)
    if relative_file is None:
        return spec
    return replace(spec, default_file=source_dir / relative_file)


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    db_path = Path(args.db_path)
    source_dir = Path(args.source_dir)
    selected_names = args.only or DEFAULT_SOURCE_NAMES
    selected_specs = [_spec_with_source_dir(SOURCES[name], source_dir) for name in selected_names]
    if args.source_file:
        if len(selected_specs) != 1:
            raise SystemExit("--source-file exige exatamente um --only.")
        selected_specs = [replace(selected_specs[0], default_file=Path(args.source_file))]

    if args.dry_run:
        print(
            json.dumps(
                {
                    "db_path": str(db_path),
                    "sources": [asdict(replace(spec, default_file=_resolve_source_file(spec))) for spec in selected_specs],
                },
                ensure_ascii=False,
                indent=2,
                default=str,
            )
        )
        return 0

    if args.rebuild and db_path.exists():
        db_path.unlink()
        wal_path = db_path.with_suffix(db_path.suffix + ".wal")
        wal_path.unlink(missing_ok=True)

    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = duckdb.connect(str(db_path))
    try:
        create_control_tables(conn)
        load_results: list[dict[str, Any]] = []
        if not args.quality_checks:
            for spec in selected_specs:
                load_results.append(load_source(conn, spec, spec.default_file))

        rebuild_staging_tables(conn)
        rebuild_marts(conn)
        quality_rows = run_quality_checks(conn)
        summary = {
            "db_path": str(db_path),
            "loaded": load_results,
            "quality_checks": quality_rows,
            "mart_casos_malha_rows": conn.execute("SELECT count(*) FROM mart_casos_malha").fetchone()[0],
            "mart_potencial_arrecadacao_rows": conn.execute("SELECT count(*) FROM mart_potencial_arrecadacao").fetchone()[0],
        }
        print(json.dumps(summary, ensure_ascii=False, indent=2, default=str))
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
