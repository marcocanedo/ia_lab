from __future__ import annotations

import calendar
import re
import time
from copy import deepcopy
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path
from typing import Any, Callable, Iterable

import pandas as pd

from microstrategy_client import MicroStrategyRestClient


BASE_REPORT_ID = "E3A48DB8244D60DA4AD889A02668C5F2"
EFD_SAIDA_REPORT_ID = "AF599D9F6D4FC4B0463F5F907D5B5220"
FREEFORM_EFD_SAIDA_REPORT_ID = "__freeform_sql_efd_saida__"
AI_AUTO_REPORT_ID = "__ai_auto__"
DEFAULT_REPORT_ID = BASE_REPORT_ID
REPORTS = {
    "base": {
        "id": BASE_REPORT_ID,
        "name": "RASCUNHO - SQL 01 - DIFAL NF-e por emitente",
    },
    "efd_saida": {
        "id": EFD_SAIDA_REPORT_ID,
        "name": "RASCUNHO - SQL 01 - DIFAL NF-e por emitente - com EFD Saida",
    },
    "efd_saida_sql": {
        "id": FREEFORM_EFD_SAIDA_REPORT_ID,
        "name": "DIFAL NF-e por emitente - Freeform SQL com EFD Saida",
    },
    "ai_auto": {
        "id": AI_AUTO_REPORT_ID,
        "name": "IA local - escolha automatica MicroStrategy ou Freeform SQL",
    },
}
FOLDER_ID = "8027596BD54BF03981CA8A8C637C88CE"
TERADATA_DATASOURCE_ID = "2FA79BF04DD8149F9CDC60B981EB70E4"
COMMON_ID_FORM_ID = "45C11FA478E745FEA08D781CEA190FE5"
DATE_ATTRIBUTE_ID = "285C0A8D447F128DD2492B8375A9248D"
DIFAL_METRIC_ID = "4C395EEC4F673154D33732BF979F8FD8"

ATTR_NOME_ID = "8099FA2A471AC00EFF61C4B96CB94724"
ATTR_CNPJ_ID = "22DC161D4B7CC052583C21A68F948A7A"
ATTR_UF_ID = "3E535211437246F3AA8CA2B60C13BECC"

METRIC_QTD_DOC_ID = "70C737B76EC240EC8992E6C4294E8FEA"
METRIC_TOTAL_ITEM_ID = "1DC9BA25484AB2680473BC93298EF3F3"

ATTRIBUTE_COLUMNS = {
    ATTR_NOME_ID: "NOME_EMITENTE",
    ATTR_CNPJ_ID: "CNPJ_CPF_EMITENTE",
    ATTR_UF_ID: "UF_EMITENTE",
}

METRIC_COLUMNS = {
    METRIC_QTD_DOC_ID: "QTD_DOC",
    METRIC_TOTAL_ITEM_ID: "TOTAL_ITEM",
    DIFAL_METRIC_ID: "DIFAL_DEST",
}

OUTPUT_COLUMNS = [
    "MES_REF",
    "CHUNK_INICIO",
    "CHUNK_FIM",
    "NOME_EMITENTE",
    "CNPJ_CPF_EMITENTE",
    "UF_EMITENTE",
    "QTD_DOC",
    "TOTAL_ITEM",
    "DIFAL_DEST",
]

CONSOLIDATED_COLUMNS = [
    "NOME_EMITENTE",
    "CNPJ_CPF_EMITENTE",
    "UF_EMITENTE",
    "QTD_DOC",
    "TOTAL_ITEM",
    "DIFAL_DEST",
]

MANIFEST_COLUMNS = [
    "MES_REF",
    "CHUNK_INICIO",
    "CHUNK_FIM",
    "STATUS",
    "TENTATIVA",
    "LINHAS",
    "TOTAL_API",
    "INSTANCE_ID",
    "ERRO",
    "INICIO_EXECUCAO",
    "FIM_EXECUCAO",
]

EXCEL_MAX_ROWS = 1_048_576

ITEM_DETAIL_COLUMNS = [
    "IdNFe",
    "DtEmissao",
    "ModeloDoc",
    "SerieDoc",
    "NrDoc",
    "CdFinalidadeNFe",
    "TpOperacao",
    "NmEmit",
    "CNPJEmit",
    "CadICMSEmit",
    "MunicipioEmit",
    "UFEmit",
    "NM_PARTICIPANTE",
    "CD_CNPJ_CPF_PARTICIPANTE",
    "CD_IE_PARTICIPANTE",
    "MUNIC_PARTICIPANTE",
    "UF_PARTICIPANTE",
    "CD_TIPO_IE_DEST",
    "NrItem",
    "GTINItem",
    "CdItem",
    "DescItem",
    "NCM",
    "CEST",
    "CST",
    "CFOP",
    "QtdComercial",
    "UnidadeTributavel",
    "VlUnitComercial",
    "VlTotalItem",
    "QtdTributavel",
    "VlUnitarioTributacao",
    "VlFrete",
    "VlSeguro",
    "VlDesconto",
    "VlOutro",
    "AliquotaIPI",
    "VlIPI",
    "CdOrigemMercadoria",
    "VlBaseCalculoICMS",
    "AliquotaICMS",
    "VlICMS",
    "PercMVAICMSST",
    "PercReducaoBaseCalculoICMSST",
    "VlBaseCalculoICMSST",
    "AliquotaICMSST",
    "VlICMSST",
    "VL_ALIQ_UF_DEST",
    "VL_ICMS_UF_DEST",
    "VL_ICMS_FCP_UF_DEST",
    "TotVlBaseCalculoICMS",
    "TotVlICMS",
    "TotVlBaseCalculoICMSST",
    "TotVlICMSST",
    "TotVlTotalItem",
    "TotVlFrete",
    "TotVlSeguro",
    "TotVlDesconto",
    "TotVlIPI",
    "TotVlTotalDoc",
]

ANALYSIS_SHEETS = [
    "ranking_top20",
    "itens_top20",
    "recolhimento",
    "confronto",
    "possiveis_devedores",
    "falsos_positivos_sinais",
    "manifest",
]


@dataclass(frozen=True)
class MonthWindow:
    start: date
    end: date

    @property
    def label(self) -> str:
        if self.start == self.end:
            return self.start.isoformat()
        return f"{self.start.isoformat()}_a_{self.end.isoformat()}"


@dataclass(frozen=True)
class ExportResult:
    output_path: Path
    chunks: pd.DataFrame
    consolidated: pd.DataFrame
    top_n: pd.DataFrame
    manifest: pd.DataFrame


def parse_date(value: str | date | None) -> date | None:
    if value is None or isinstance(value, date):
        return value
    return date.fromisoformat(str(value))


def month_windows(start_date: str | date, end_date: str | date) -> list[MonthWindow]:
    start = parse_date(start_date)
    end = parse_date(end_date)
    if start is None or end is None:
        raise ValueError("Informe start_date e end_date, ou use o periodo atual do relatorio.")
    if start > end:
        raise ValueError("start_date nao pode ser maior que end_date.")

    windows: list[MonthWindow] = []
    current = date(start.year, start.month, 1)
    while current <= end:
        last_day = calendar.monthrange(current.year, current.month)[1]
        month_start = current
        month_end = date(current.year, current.month, last_day)
        windows.append(MonthWindow(max(start, month_start), min(end, month_end)))

        if current.month == 12:
            current = date(current.year + 1, 1, 1)
        else:
            current = date(current.year, current.month + 1, 1)

    return windows


def date_windows(
    start_date: str | date,
    end_date: str | date,
    *,
    chunk_days: int | None = None,
) -> list[MonthWindow]:
    if chunk_days is None:
        return month_windows(start_date, end_date)
    if chunk_days < 1:
        raise ValueError("chunk_days deve ser maior ou igual a 1.")

    start = parse_date(start_date)
    end = parse_date(end_date)
    if start is None or end is None:
        raise ValueError("Informe start_date e end_date, ou use o periodo atual do relatorio.")
    if start > end:
        raise ValueError("start_date nao pode ser maior que end_date.")

    windows: list[MonthWindow] = []
    current = start
    while current <= end:
        chunk_end = min(end, date.fromordinal(current.toordinal() + chunk_days - 1))
        windows.append(MonthWindow(current, chunk_end))
        current = date.fromordinal(chunk_end.toordinal() + 1)
    return windows


def get_report_definition(client: MicroStrategyRestClient, report_id: str) -> dict[str, Any]:
    response = client.request(
        "GET",
        f"/model/reports/{report_id}",
        params={"showExpressionAs": "tree"},
    )
    _raise_for_status(response, "Leitura da definicao do relatorio")
    return response.json()


def get_current_report_date_window(report_definition: dict[str, Any]) -> tuple[date, date]:
    predicate = _find_date_predicate(report_definition)
    params = predicate["predicateTree"]["parameters"]
    return (
        date.fromisoformat(params[0]["constant"]["value"]),
        date.fromisoformat(params[1]["constant"]["value"]),
    )


def patch_report_definition_for_window(
    report_definition: dict[str, Any],
    window: MonthWindow,
    *,
    remove_rank: bool = True,
) -> tuple[dict[str, Any], int]:
    patched = deepcopy(report_definition)
    filter_node = _get_filter_node(patched)
    children = filter_node["tree"].get("children") or []

    date_found = False
    rank_removed = 0
    old_date_text = None
    new_date_text = None
    rank_texts: list[str] = []
    new_children: list[dict[str, Any]] = []

    for child in children:
        if _is_date_predicate(child):
            date_found = True
            old_date_text = child.get("predicateText")
            new_date_text = _patch_date_predicate(child, window)

        if remove_rank and _is_rank_predicate(child):
            rank_removed += 1
            if child.get("predicateText"):
                rank_texts.append(child["predicateText"])
            continue

        new_children.append(child)

    if not date_found:
        raise RuntimeError("Filtro de Data de Emissao - Documento Fiscal nao encontrado.")

    filter_node["tree"]["children"] = new_children
    filter_node["text"] = _patch_filter_text(
        filter_node.get("text") or "",
        old_date_text,
        new_date_text,
        rank_texts,
    )
    filter_node.pop("tokens", None)
    return patched, rank_removed


def run_monthly_export(
    *,
    start_date: str | date | None = None,
    end_date: str | date | None = None,
    report_id: str = DEFAULT_REPORT_ID,
    output_dir: str | Path = "outputs/difal_emitente_chunks",
    output_path: str | Path | None = None,
    top_n: int | None = 20,
    chunk_days: int | None = None,
    page_size: int = 5000,
    max_attempts: int = 2,
    sleep_between_attempts: int = 5,
    continue_on_error: bool = True,
    verbose: bool = False,
    log: Callable[[str], None] | None = None,
    client: MicroStrategyRestClient | None = None,
) -> ExportResult:
    if report_id == FREEFORM_EFD_SAIDA_REPORT_ID:
        return run_freeform_efd_saida_export(
            start_date=start_date,
            end_date=end_date,
            output_dir=output_dir,
            output_path=output_path,
            top_n=top_n,
            chunk_days=chunk_days,
            page_size=page_size,
            max_attempts=max_attempts,
            sleep_between_attempts=sleep_between_attempts,
            continue_on_error=continue_on_error,
            verbose=verbose,
            log=log,
            client=client,
        )

    own_client = client is None
    client = client or MicroStrategyRestClient()
    logger = _make_logger(verbose, log)

    if own_client:
        logger("Autenticando no MicroStrategy REST.")
        client.login()

    try:
        logger(f"Lendo definicao do relatorio {report_id}.")
        report_definition = get_report_definition(client, report_id)
        current_start, current_end = get_current_report_date_window(report_definition)
        start = parse_date(start_date) or current_start
        end = parse_date(end_date) or current_end

        windows = date_windows(start, end, chunk_days=chunk_days)
        logger(
            "Periodo de execucao: "
            f"{start.isoformat()} a {end.isoformat()} ({len(windows)} chunk(s))."
        )
        chunk_frames: list[pd.DataFrame] = []
        manifest_rows: list[dict[str, Any]] = []

        for index, window in enumerate(windows, start=1):
            logger(
                f"[{index}/{len(windows)}] Iniciando chunk {window.label}: "
                f"{window.start.isoformat()} a {window.end.isoformat()}."
            )
            df, manifest = _run_window_with_retries(
                client=client,
                report_id=report_id,
                report_definition=report_definition,
                window=window,
                page_size=page_size,
                max_attempts=max_attempts,
                sleep_between_attempts=sleep_between_attempts,
                logger=logger,
            )
            manifest_rows.append(manifest)
            if not df.empty:
                chunk_frames.append(df)
            logger(
                f"[{index}/{len(windows)}] Chunk {window.label} finalizado com "
                f"status={manifest['STATUS']}, linhas={manifest['LINHAS']}, "
                f"total_api={manifest['TOTAL_API']}."
            )
            if manifest["STATUS"] != "ok" and not continue_on_error:
                logger("Interrompendo execucao porque continue_on_error=False.")
                break

        logger("Consolidando chunks em pandas.")
        chunks = _concat_or_empty(chunk_frames, OUTPUT_COLUMNS)
        consolidated = consolidate_chunks(chunks)
        top_frame = build_top_n(consolidated, top_n)
        manifest_df = pd.DataFrame(manifest_rows, columns=MANIFEST_COLUMNS)

        final_path = _resolve_output_path(output_dir, output_path, start, end)
        logger(f"Gravando Excel em {final_path}.")
        write_excel_output(final_path, chunks, consolidated, top_frame, manifest_df)
        logger(
            "Exportacao concluida: "
            f"{len(chunks)} linha(s) mensal(is), {len(consolidated)} linha(s) consolidada(s)."
        )

        return ExportResult(
            output_path=final_path,
            chunks=chunks,
            consolidated=consolidated,
            top_n=top_frame,
            manifest=manifest_df,
        )
    finally:
        if own_client:
            logger("Encerrando sessao REST.")
            client.logout()


def run_temporary_microstrategy_report_export(
    *,
    report_objects: list[dict[str, Any]],
    start_date: str | date,
    end_date: str | date,
    base_report_id: str = BASE_REPORT_ID,
    output_dir: str | Path = "outputs/ai_microstrategy_chunks",
    output_path: str | Path | None = None,
    top_n: int | None = 20,
    chunk_days: int | None = None,
    page_size: int = 5000,
    max_attempts: int = 1,
    sleep_between_attempts: int = 5,
    continue_on_error: bool = True,
    verbose: bool = False,
    log: Callable[[str], None] | None = None,
    client: MicroStrategyRestClient | None = None,
    fetch_all_pages: bool = True,
    max_rows: int | None = None,
    report_name_prefix: str = "TMP AI MicroStrategy",
) -> ExportResult:
    """Create a temporary semantic report from planned objects and run it in chunks."""

    start = parse_date(start_date)
    end = parse_date(end_date)
    if start is None or end is None:
        raise ValueError("Informe start_date e end_date para executar o relatorio IA MicroStrategy.")

    own_client = client is None
    client = client or MicroStrategyRestClient()
    logger = _make_logger(verbose, log)
    temp_report_id = ""

    if own_client:
        logger("Autenticando no MicroStrategy REST.")
        client.login()

    try:
        logger(f"Lendo definicao base {base_report_id} para criar relatorio temporario IA.")
        base_definition = get_report_definition(client, base_report_id)
        attributes, metrics = _split_semantic_report_objects(report_objects)
        output_columns = _semantic_output_columns(attributes, metrics)
        report_name = f"{report_name_prefix} {int(time.time())}"
        temp_definition = _semantic_temp_report_definition(
            base_definition=base_definition,
            name=report_name,
            attributes=attributes,
            metrics=metrics,
        )
        logger(
            "Criando relatorio MicroStrategy temporario com "
            f"{len(attributes)} atributo(s) e {len(metrics)} metrica(s)."
        )
        temp_report_id = _create_semantic_temp_report(
            client=client,
            name=report_name,
            report_definition=temp_definition,
        )
        logger(f"Relatorio MicroStrategy temporario {temp_report_id} criado.")

        windows = date_windows(start, end, chunk_days=chunk_days)
        logger(
            "Periodo de execucao MicroStrategy IA: "
            f"{start.isoformat()} a {end.isoformat()} ({len(windows)} chunk(s))."
        )
        logger(
            "Politica de leitura: "
            f"fetch_all_pages={fetch_all_pages}, page_size={page_size}, max_rows={max_rows}, "
            f"max_attempts={max_attempts}."
        )

        chunk_frames: list[pd.DataFrame] = []
        manifest_rows: list[dict[str, Any]] = []
        for index, window in enumerate(windows, start=1):
            logger(
                f"[{index}/{len(windows)}] Iniciando chunk MicroStrategy IA {window.label}: "
                f"{window.start.isoformat()} a {window.end.isoformat()}."
            )
            df, manifest = _run_semantic_window_with_retries(
                client=client,
                report_id=temp_report_id,
                report_definition=temp_definition,
                window=window,
                output_columns=output_columns,
                page_size=page_size,
                max_attempts=max_attempts,
                sleep_between_attempts=sleep_between_attempts,
                logger=logger,
                fetch_all_pages=fetch_all_pages,
                max_rows=max_rows,
            )
            manifest_rows.append(manifest)
            if not df.empty:
                chunk_frames.append(df)
            logger(
                f"[{index}/{len(windows)}] Chunk MicroStrategy IA {window.label} finalizado com "
                f"status={manifest['STATUS']}, linhas={manifest['LINHAS']}, "
                f"total_api={manifest['TOTAL_API']}."
            )
            if manifest["STATUS"] != "ok" and not continue_on_error:
                logger("Interrompendo execucao porque continue_on_error=False.")
                break

        chunks = _concat_or_empty(chunk_frames, output_columns)
        consolidated = _consolidate_semantic_chunks(chunks, attributes, metrics)
        top_frame = _build_semantic_top_n(consolidated, metrics, top_n)
        manifest_df = pd.DataFrame(manifest_rows, columns=MANIFEST_COLUMNS)
        final_path = _resolve_output_path(output_dir, output_path, start, end)
        logger(f"Gravando Excel MicroStrategy IA em {final_path}.")
        write_excel_output(final_path, chunks, consolidated, top_frame, manifest_df)
        return ExportResult(
            output_path=final_path,
            chunks=chunks,
            consolidated=consolidated,
            top_n=top_frame,
            manifest=manifest_df,
        )
    finally:
        if temp_report_id:
            logger(f"Apagando relatorio MicroStrategy temporario {temp_report_id}.")
            _delete_report_object(client, temp_report_id)
        if own_client:
            logger("Encerrando sessao REST.")
            client.logout()


def run_freeform_efd_saida_export(
    *,
    start_date: str | date | None = None,
    end_date: str | date | None = None,
    output_dir: str | Path = "outputs/difal_emitente_chunks",
    output_path: str | Path | None = None,
    top_n: int | None = 20,
    chunk_days: int | None = None,
    page_size: int = 5000,
    max_attempts: int = 2,
    sleep_between_attempts: int = 5,
    continue_on_error: bool = True,
    verbose: bool = False,
    log: Callable[[str], None] | None = None,
    client: MicroStrategyRestClient | None = None,
) -> ExportResult:
    own_client = client is None
    client = client or MicroStrategyRestClient()
    logger = _make_logger(verbose, log)

    if own_client:
        logger("Autenticando no MicroStrategy REST.")
        client.login()

    try:
        if start_date is None or end_date is None:
            logger("Periodo nao informado; lendo periodo salvo no relatorio base.")
            report_definition = get_report_definition(client, BASE_REPORT_ID)
            current_start, current_end = get_current_report_date_window(report_definition)
        else:
            current_start, current_end = None, None

        start = parse_date(start_date) or current_start
        end = parse_date(end_date) or current_end
        if start is None or end is None:
            raise ValueError("Informe start_date e end_date para a variante Freeform SQL.")

        windows = date_windows(start, end, chunk_days=chunk_days)
        logger(
            "Periodo de execucao Freeform SQL EFD Saida: "
            f"{start.isoformat()} a {end.isoformat()} ({len(windows)} chunk(s))."
        )
        chunk_frames: list[pd.DataFrame] = []
        manifest_rows: list[dict[str, Any]] = []

        for index, window in enumerate(windows, start=1):
            logger(
                f"[{index}/{len(windows)}] Iniciando chunk SQL {window.label}: "
                f"{window.start.isoformat()} a {window.end.isoformat()}."
            )
            df, manifest = _run_freeform_window_with_retries(
                client=client,
                window=window,
                page_size=page_size,
                max_attempts=max_attempts,
                sleep_between_attempts=sleep_between_attempts,
                logger=logger,
            )
            manifest_rows.append(manifest)
            if not df.empty:
                chunk_frames.append(df)
            logger(
                f"[{index}/{len(windows)}] Chunk SQL {window.label} finalizado com "
                f"status={manifest['STATUS']}, linhas={manifest['LINHAS']}, "
                f"total_api={manifest['TOTAL_API']}."
            )
            if manifest["STATUS"] != "ok" and not continue_on_error:
                logger("Interrompendo execucao porque continue_on_error=False.")
                break

        logger("Consolidando chunks em pandas.")
        chunks = _concat_or_empty(chunk_frames, OUTPUT_COLUMNS)
        consolidated = consolidate_chunks(chunks)
        top_frame = build_top_n(consolidated, top_n)
        manifest_df = pd.DataFrame(manifest_rows, columns=MANIFEST_COLUMNS)

        final_path = _resolve_output_path(output_dir, output_path, start, end)
        logger(f"Gravando Excel em {final_path}.")
        write_excel_output(final_path, chunks, consolidated, top_frame, manifest_df)
        logger(
            "Exportacao Freeform SQL concluida: "
            f"{len(chunks)} linha(s) de chunks, {len(consolidated)} linha(s) consolidada(s)."
        )

        return ExportResult(
            output_path=final_path,
            chunks=chunks,
            consolidated=consolidated,
            top_n=top_frame,
            manifest=manifest_df,
        )
    finally:
        if own_client:
            logger("Encerrando sessao REST.")
            client.logout()


def run_freeform_sql_export(
    *,
    sql_template: str,
    output_columns: list[str],
    attribute_columns: list[str],
    metric_columns: list[str],
    start_date: str | date,
    end_date: str | date,
    output_dir: str | Path = "outputs/freeform_sql_chunks",
    output_path: str | Path | None = None,
    top_n: int | None = 20,
    chunk_days: int | None = None,
    page_size: int = 5000,
    max_attempts: int = 1,
    sleep_between_attempts: int = 5,
    sleep_between_chunks: int = 0,
    continue_on_error: bool = True,
    verbose: bool = False,
    log: Callable[[str], None] | None = None,
    client: MicroStrategyRestClient | None = None,
    fetch_all_pages: bool = True,
    max_rows: int | None = None,
    report_name_prefix: str = "TMP Freeform SQL",
    description: str = "Relatorio temporario Freeform SQL.",
    write_workbook: bool = True,
) -> ExportResult:
    own_client = client is None
    client = client or MicroStrategyRestClient()
    logger = _make_logger(verbose, log)

    start = parse_date(start_date)
    end = parse_date(end_date)
    if start is None or end is None:
        raise ValueError("Informe start_date e end_date para executar Freeform SQL.")
    if not output_columns:
        raise ValueError("output_columns nao pode ser vazio.")

    if own_client:
        logger("Autenticando no MicroStrategy REST.")
        client.login()

    try:
        windows = date_windows(start, end, chunk_days=chunk_days)
        logger(
            "Periodo de execucao Freeform SQL generico: "
            f"{start.isoformat()} a {end.isoformat()} ({len(windows)} chunk(s))."
        )
        logger(
            "Politica baixo volume: "
            f"fetch_all_pages={fetch_all_pages}, page_size={page_size}, "
            f"max_rows={max_rows}, max_attempts={max_attempts}."
        )
        chunk_frames: list[pd.DataFrame] = []
        manifest_rows: list[dict[str, Any]] = []

        for index, window in enumerate(windows, start=1):
            logger(
                f"[{index}/{len(windows)}] Iniciando chunk Freeform {window.label}: "
                f"{window.start.isoformat()} a {window.end.isoformat()}."
            )
            df, manifest = _run_generic_freeform_window_with_retries(
                client=client,
                window=window,
                sql_template=sql_template,
                output_columns=output_columns,
                attribute_columns=attribute_columns,
                metric_columns=metric_columns,
                page_size=page_size,
                max_attempts=max_attempts,
                sleep_between_attempts=sleep_between_attempts,
                logger=logger,
                fetch_all_pages=fetch_all_pages,
                max_rows=max_rows,
                report_name_prefix=report_name_prefix,
                description=description,
            )
            manifest_rows.append(manifest)
            if not df.empty:
                chunk_frames.append(df)
            logger(
                f"[{index}/{len(windows)}] Chunk Freeform {window.label} finalizado com "
                f"status={manifest['STATUS']}, linhas={manifest['LINHAS']}, "
                f"total_api={manifest['TOTAL_API']}."
            )
            if manifest["STATUS"] != "ok" and not continue_on_error:
                logger("Interrompendo execucao porque continue_on_error=False.")
                break
            if sleep_between_chunks > 0 and index < len(windows):
                logger(f"Aguardando {sleep_between_chunks}s antes do proximo chunk.")
                time.sleep(sleep_between_chunks)

        chunks = _concat_or_empty(chunk_frames, output_columns)
        consolidated = _consolidate_freeform_chunks(chunks)
        top_frame = _build_freeform_top_n(consolidated, top_n)
        manifest_df = pd.DataFrame(manifest_rows, columns=MANIFEST_COLUMNS)

        final_path = _resolve_output_path(output_dir, output_path, start, end)
        if write_workbook:
            logger(f"Gravando Excel em {final_path}.")
            write_excel_output(final_path, chunks, consolidated, top_frame, manifest_df)
        return ExportResult(
            output_path=final_path,
            chunks=chunks,
            consolidated=consolidated,
            top_n=top_frame,
            manifest=manifest_df,
        )
    finally:
        if own_client:
            logger("Encerrando sessao REST.")
            client.logout()


def consolidate_chunks(chunks: pd.DataFrame) -> pd.DataFrame:
    if chunks.empty:
        return pd.DataFrame(columns=CONSOLIDATED_COLUMNS)

    data = chunks.copy()
    for column in ["QTD_DOC", "TOTAL_ITEM", "DIFAL_DEST"]:
        data[column] = pd.to_numeric(data[column], errors="coerce").fillna(0)

    consolidated = (
        data.groupby(
            ["NOME_EMITENTE", "CNPJ_CPF_EMITENTE", "UF_EMITENTE"],
            dropna=False,
            as_index=False,
        )[["QTD_DOC", "TOTAL_ITEM", "DIFAL_DEST"]]
        .sum()
        .sort_values(["DIFAL_DEST", "TOTAL_ITEM"], ascending=[False, False])
        .reset_index(drop=True)
    )
    consolidated["QTD_DOC"] = consolidated["QTD_DOC"].astype("int64")
    return consolidated[CONSOLIDATED_COLUMNS]


def build_top_n(consolidated: pd.DataFrame, top_n: int | None) -> pd.DataFrame:
    if top_n is None or top_n <= 0:
        return pd.DataFrame(columns=consolidated.columns)
    return consolidated.head(top_n).copy()


def _normalize_freeform_frame(
    frame: pd.DataFrame,
    output_columns: list[str],
    window: MonthWindow,
) -> pd.DataFrame:
    data = frame.copy()
    if "MES_REF" in output_columns:
        data["MES_REF"] = window.label
    if "CHUNK_INICIO" in output_columns:
        data["CHUNK_INICIO"] = window.start.isoformat()
    if "CHUNK_FIM" in output_columns:
        data["CHUNK_FIM"] = window.end.isoformat()
    for column in output_columns:
        if column not in data.columns:
            data[column] = pd.NA
    return data[output_columns]


def _consolidate_freeform_chunks(chunks: pd.DataFrame) -> pd.DataFrame:
    if set(CONSOLIDATED_COLUMNS).issubset(chunks.columns):
        return consolidate_chunks(chunks)
    return chunks.copy()


def _build_freeform_top_n(consolidated: pd.DataFrame, top_n: int | None) -> pd.DataFrame:
    if top_n is None or top_n <= 0:
        return pd.DataFrame(columns=consolidated.columns)
    if consolidated.empty:
        return consolidated.head(0).copy()
    if "DIFAL_DEST" in consolidated.columns:
        data = consolidated.copy()
        data["DIFAL_DEST"] = pd.to_numeric(data["DIFAL_DEST"], errors="coerce").fillna(0)
        sort_columns = ["DIFAL_DEST"]
        ascending = [False]
        if "TOTAL_ITEM" in data.columns:
            data["TOTAL_ITEM"] = pd.to_numeric(data["TOTAL_ITEM"], errors="coerce").fillna(0)
            sort_columns.append("TOTAL_ITEM")
            ascending.append(False)
        return data.sort_values(sort_columns, ascending=ascending).head(top_n).reset_index(drop=True)
    return consolidated.head(top_n).copy()


def write_excel_output(
    output_path: str | Path,
    chunks: pd.DataFrame,
    consolidated: pd.DataFrame,
    top_n: pd.DataFrame,
    manifest: pd.DataFrame,
) -> Path:
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)

    with pd.ExcelWriter(path, engine="openpyxl") as writer:
        _write_sheet(writer, chunks, "chunks")
        _write_sheet(writer, consolidated, "consolidado")
        _write_sheet(writer, top_n, "top_n")
        _write_sheet(writer, manifest, "manifest")

    return path


def _split_semantic_report_objects(
    report_objects: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    attributes: list[dict[str, Any]] = []
    metrics: list[dict[str, Any]] = []
    seen: set[str] = set()
    for obj in report_objects:
        object_id = str(obj.get("id") or "").strip()
        object_type = str(obj.get("type") or "").strip().lower()
        name = str(obj.get("name") or "").strip()
        if not object_id or not name or object_id in seen:
            continue
        seen.add(object_id)
        if object_type == "attribute":
            if object_id == DATE_ATTRIBUTE_ID:
                continue
            attributes.append({"id": object_id, "name": name, "type": "attribute"})
        elif object_type == "metric":
            metrics.append({"id": object_id, "name": name, "type": "metric"})
    if not attributes:
        raise ValueError("Relatorio MicroStrategy temporario precisa de pelo menos um atributo de linha.")
    if not metrics:
        raise ValueError("Relatorio MicroStrategy temporario precisa de pelo menos uma metrica.")
    return attributes, metrics


def _semantic_output_columns(attributes: list[dict[str, Any]], metrics: list[dict[str, Any]]) -> list[str]:
    return [
        "MES_REF",
        "CHUNK_INICIO",
        "CHUNK_FIM",
        *[str(attribute["name"]) for attribute in attributes],
        *[str(metric["name"]) for metric in metrics],
    ]


def _semantic_temp_report_definition(
    *,
    base_definition: dict[str, Any],
    name: str,
    attributes: list[dict[str, Any]],
    metrics: list[dict[str, Any]],
) -> dict[str, Any]:
    definition = deepcopy(base_definition)
    definition["information"] = {
        "name": name,
        "destinationFolderId": FOLDER_ID,
        "description": (
            "Relatorio MicroStrategy temporario criado pela IA local; "
            "preserva os filtros fiscais do relatorio base e altera somente o template."
        ),
    }

    data_template_units: list[dict[str, Any]] = [
        {
            "id": attribute["id"],
            "name": attribute["name"],
            "type": "attribute",
            "nonAggregatable": False,
        }
        for attribute in attributes
    ]
    data_template_units.append(
        {
            "type": "metrics",
            "elements": [
                {
                    "id": metric["id"],
                    "name": metric["name"],
                    "subType": "metric",
                }
                for metric in metrics
            ],
        }
    )

    row_units = [
        {
            "id": attribute["id"],
            "name": attribute["name"],
            "type": "attribute",
        }
        for attribute in attributes
    ]
    metric_elements = [
        {
            "id": metric["id"],
            "name": metric["name"],
            "subType": "metric",
            "alias": metric["name"],
        }
        for metric in metrics
    ]

    definition.setdefault("dataSource", {}).setdefault("dataTemplate", {})["units"] = data_template_units
    view_template = definition.setdefault("grid", {}).setdefault("viewTemplate", {})
    view_template["rows"] = {
        "units": row_units,
        "sorts": _semantic_metric_sorts(metrics),
    }
    view_template["columns"] = {
        "units": [
            {
                "type": "metrics",
                "elements": metric_elements,
            }
        ],
        "sorts": [],
    }
    view_template.setdefault("pageBy", {"units": [], "sorts": []})
    return definition


def _semantic_metric_sorts(metrics: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if not metrics:
        return []
    target = _preferred_sort_metric(metrics)
    return [
        {
            "target": {
                "objectId": target["id"],
                "subType": "metric",
                "name": target["name"],
            },
            "order": "descending",
            "type": "metric",
            "subtotalsPosition": "inherit",
        }
    ]


def _preferred_sort_metric(metrics: list[dict[str, Any]]) -> dict[str, Any]:
    for metric in metrics:
        name = str(metric.get("name") or "").lower()
        if "icms interestadual" in name or "difal" in name or metric.get("id") == DIFAL_METRIC_ID:
            return metric
    return metrics[-1]


def _create_semantic_temp_report(
    *,
    client: MicroStrategyRestClient,
    name: str,
    report_definition: dict[str, Any],
) -> str:
    response = client.request(
        "POST",
        "/model/reports",
        params={"showExpressionAs": "tree"},
        headers={"Content-Type": "application/json"},
        json=report_definition,
        timeout=120,
    )
    _raise_for_status(response, "Criacao do relatorio MicroStrategy temporario")

    report_id = response.json().get("information", {}).get("objectId")
    instance_id = response.headers.get("X-MSTR-MS-Instance")
    if not report_id or not instance_id:
        raise RuntimeError("Criacao do relatorio MicroStrategy temporario nao retornou report_id ou instancia.")

    save_response = client.request(
        "POST",
        f"/model/reports/{report_id}/instances/saveAs",
        headers={"Content-Type": "application/json", "X-MSTR-MS-Instance": instance_id},
        json={"name": name, "destinationFolderId": FOLDER_ID, "overwrite": False},
        timeout=120,
    )
    _raise_for_status(save_response, "SaveAs do relatorio MicroStrategy temporario")
    return report_id


def _consolidate_semantic_chunks(
    chunks: pd.DataFrame,
    attributes: list[dict[str, Any]],
    metrics: list[dict[str, Any]],
) -> pd.DataFrame:
    if chunks.empty:
        return pd.DataFrame(columns=_semantic_output_columns(attributes, metrics)[3:])
    attribute_columns = [str(attribute["name"]) for attribute in attributes]
    metric_columns = [str(metric["name"]) for metric in metrics]
    data = chunks.copy()
    for metric in metric_columns:
        if metric in data.columns:
            data[metric] = pd.to_numeric(data[metric], errors="coerce").fillna(0)
    consolidated = (
        data.groupby(attribute_columns, dropna=False, as_index=False)[metric_columns]
        .sum()
        .reset_index(drop=True)
    )
    return _build_semantic_top_n(consolidated, metrics, None)


def _build_semantic_top_n(
    consolidated: pd.DataFrame,
    metrics: list[dict[str, Any]],
    top_n: int | None,
) -> pd.DataFrame:
    if consolidated.empty:
        return consolidated.copy()
    metric_names = [str(metric["name"]) for metric in metrics]
    sort_metric = str(_preferred_sort_metric(metrics)["name"]) if metrics else ""
    data = consolidated.copy()
    for metric in metric_names:
        if metric in data.columns:
            data[metric] = pd.to_numeric(data[metric], errors="coerce").fillna(0)
    if sort_metric in data.columns:
        data = data.sort_values(sort_metric, ascending=False).reset_index(drop=True)
    if top_n is None or top_n <= 0:
        return data
    return data.head(top_n).copy()


def run_top20_debt_analysis(
    *,
    potential_excel_path: str | Path | None = None,
    start_date: str | date,
    end_date: str | date,
    output_dir: str | Path = "outputs/difal_debt_analysis",
    output_path: str | Path | None = None,
    top_n: int = 20,
    chunk_days: int | None = 31,
    page_size: int = 5000,
    max_attempts: int = 2,
    sleep_between_attempts: int = 5,
    verbose: bool = False,
    log: Callable[[str], None] | None = None,
    progress_callback: Callable[[dict[str, Any]], None] | None = None,
    client: MicroStrategyRestClient | None = None,
) -> dict[str, pd.DataFrame | Path]:
    """Build the audit workbook for the top DIFAL candidates.

    The payment/recolhimento source is intentionally not inferred from NF-e data.
    Until a GIA/Recolhimento report or table is validated, the workbook marks that
    step as blocked and does not classify taxpayers as confirmed debtors.
    """
    start = parse_date(start_date)
    end = parse_date(end_date)
    if start is None or end is None:
        raise ValueError("Informe start_date e end_date.")
    if top_n < 1:
        raise ValueError("top_n deve ser maior ou igual a 1.")

    logger = _make_logger(verbose, log)
    if progress_callback:
        progress_callback({"stage": "ranking", "progress": 0.0, "message": "Preparando ranking dos contribuintes top."})
    potential_path = _resolve_potential_excel_path(potential_excel_path)
    logger(f"Lendo consolidado de potencial DIFAL em {potential_path}.")
    consolidated = pd.read_excel(potential_path, sheet_name="consolidado")
    ranking = build_top_n(_normalize_consolidated_for_ranking(consolidated), top_n)
    cnpjs = _clean_cnpj_list(ranking["CNPJ_CPF_EMITENTE"].tolist())
    logger(f"Top {len(cnpjs)} CNPJ(s) selecionados para detalhamento.")
    if progress_callback:
        progress_callback({"stage": "ranking", "progress": 0.02, "message": f"Top {len(cnpjs)} CNPJ(s) selecionados."})

    own_client = client is None
    client = client or MicroStrategyRestClient()
    if own_client:
        logger("Autenticando no MicroStrategy REST.")
        client.login()

    try:
        item_frames: list[pd.DataFrame] = []
        manifest_rows: list[dict[str, Any]] = [
            _analysis_manifest_row(
                etapa="ranking_top20",
                status="ok",
                rows=len(ranking),
                error="",
                started_at=_now(),
                finished_at=_now(),
                details=f"Origem: {potential_path}",
            )
        ]

        windows = date_windows(start, end, chunk_days=chunk_days)
        total_chunks = max(len(windows), 1)
        for index, window in enumerate(windows, start=1):
            chunk_start_progress = 0.02 + ((index - 1) / total_chunks) * 0.93
            if progress_callback:
                progress_callback(
                    {
                        "stage": "chunk_start",
                        "progress": chunk_start_progress,
                        "chunk_index": index,
                        "total_chunks": total_chunks,
                        "message": f"Chunk {index}/{total_chunks}: {window.start.isoformat()} a {window.end.isoformat()}.",
                    }
                )
            logger(
                f"[{index}] Extraindo itens Top {top_n}: "
                f"{window.start.isoformat()} a {window.end.isoformat()}."
            )
            df, manifest = _run_item_detail_window_with_retries(
                client=client,
                window=window,
                cnpjs=cnpjs,
                page_size=page_size,
                max_attempts=max_attempts,
                sleep_between_attempts=sleep_between_attempts,
                logger=logger,
            )
            manifest_rows.append(manifest)
            if not df.empty:
                item_frames.append(df)
            if progress_callback:
                progress_callback(
                    {
                        "stage": "chunk_done",
                        "progress": 0.02 + (index / total_chunks) * 0.93,
                        "chunk_index": index,
                        "total_chunks": total_chunks,
                        "rows": len(df),
                        "message": f"Chunk {index}/{total_chunks} concluído com {len(df)} linha(s).",
                    }
                )

        itens = _concat_or_empty(item_frames, ITEM_DETAIL_COLUMNS)
        recolhimento, recolhimento_manifest = _build_blocked_recolhimento_frame()
        manifest_rows.append(recolhimento_manifest)
        confronto = _build_blocked_confronto(ranking, recolhimento)
        possiveis_devedores = _build_blocked_possiveis_devedores()
        sinais = build_false_positive_signals(itens)

        manifest = pd.DataFrame(manifest_rows)
        final_path = _resolve_analysis_output_path(output_dir, output_path, start, end)
        logger(f"Gravando Excel de analise em {final_path}.")
        if progress_callback:
            progress_callback({"stage": "write_output", "progress": 0.97, "message": "Gravando workbook de itens."})
        write_debt_analysis_output(
            final_path,
            ranking_top20=ranking,
            itens_top20=itens,
            recolhimento=recolhimento,
            confronto=confronto,
            possiveis_devedores=possiveis_devedores,
            falsos_positivos_sinais=sinais,
            manifest=manifest,
        )
        logger("Analise Top 20 concluida com recolhimento marcado como bloqueado.")
        if progress_callback:
            progress_callback({"stage": "extract_done", "progress": 0.98, "message": "Extração de itens concluída."})
        return {
            "output_path": final_path,
            "ranking_top20": ranking,
            "itens_top20": itens,
            "recolhimento": recolhimento,
            "confronto": confronto,
            "possiveis_devedores": possiveis_devedores,
            "falsos_positivos_sinais": sinais,
            "manifest": manifest,
        }
    finally:
        if own_client:
            logger("Encerrando sessao REST.")
            client.logout()


def build_false_positive_signals(itens: pd.DataFrame) -> pd.DataFrame:
    if itens.empty:
        return pd.DataFrame(
            columns=[
                "CNPJEmit",
                "NmEmit",
                "UFEmit",
                "CdFinalidadeNFe",
                "TpOperacao",
                "CFOP",
                "CST",
                "NCM",
                "QTD_ITENS",
                "QTD_NFE",
                "VL_TOTAL_ITEM",
                "VL_ICMS_UF_DEST",
                "VL_ICMS_FCP_UF_DEST",
            ]
        )

    data = itens.copy()
    for column in ["VlTotalItem", "VL_ICMS_UF_DEST", "VL_ICMS_FCP_UF_DEST"]:
        data[column] = pd.to_numeric(data[column], errors="coerce").fillna(0)
    group_columns = [
        "CNPJEmit",
        "NmEmit",
        "UFEmit",
        "CdFinalidadeNFe",
        "TpOperacao",
        "CFOP",
        "CST",
        "NCM",
    ]
    signals = (
        data.groupby(group_columns, dropna=False, as_index=False)
        .agg(
            QTD_ITENS=("IdNFe", "size"),
            QTD_NFE=("IdNFe", "nunique"),
            VL_TOTAL_ITEM=("VlTotalItem", "sum"),
            VL_ICMS_UF_DEST=("VL_ICMS_UF_DEST", "sum"),
            VL_ICMS_FCP_UF_DEST=("VL_ICMS_FCP_UF_DEST", "sum"),
        )
        .sort_values(["VL_ICMS_UF_DEST", "VL_TOTAL_ITEM"], ascending=[False, False])
        .reset_index(drop=True)
    )
    return signals


def write_debt_analysis_output(
    output_path: str | Path,
    *,
    ranking_top20: pd.DataFrame,
    itens_top20: pd.DataFrame,
    recolhimento: pd.DataFrame,
    confronto: pd.DataFrame,
    possiveis_devedores: pd.DataFrame,
    falsos_positivos_sinais: pd.DataFrame,
    manifest: pd.DataFrame,
) -> Path:
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with pd.ExcelWriter(path, engine="openpyxl") as writer:
        _write_sheet(writer, ranking_top20, "ranking_top20")
        _write_sheet(writer, itens_top20, "itens_top20")
        _write_sheet(writer, recolhimento, "recolhimento")
        _write_sheet(writer, confronto, "confronto")
        _write_sheet(writer, possiveis_devedores, "possiveis_devedores")
        _write_sheet(writer, falsos_positivos_sinais, "falsos_positivos_sinais")
        _write_sheet(writer, manifest, "manifest")
    return path


def _run_window_with_retries(
    *,
    client: MicroStrategyRestClient,
    report_id: str,
    report_definition: dict[str, Any],
    window: MonthWindow,
    page_size: int,
    max_attempts: int,
    sleep_between_attempts: int,
    logger: Callable[[str], None],
) -> tuple[pd.DataFrame, dict[str, Any]]:
    last_error = ""
    attempts = max(1, max_attempts)

    for attempt in range(1, attempts + 1):
        started_at = _now()
        try:
            logger(f"{window.label}: tentativa {attempt}/{attempts}.")
            df, instance_id, total_api = _execute_window_once(
                client=client,
                report_id=report_id,
                report_definition=report_definition,
                window=window,
                page_size=page_size,
                logger=logger,
            )
            manifest = _manifest_row(
                window=window,
                status="ok",
                attempt=attempt,
                rows=len(df),
                total_api=total_api,
                instance_id=instance_id,
                error="",
                started_at=started_at,
                finished_at=_now(),
            )
            return df, manifest
        except Exception as exc:
            last_error = str(exc)
            logger(f"{window.label}: erro na tentativa {attempt}/{attempts}: {last_error}")
            if attempt < attempts:
                logger(f"{window.label}: aguardando {sleep_between_attempts}s antes de tentar novamente.")
                time.sleep(sleep_between_attempts)

    manifest = _manifest_row(
        window=window,
        status="erro",
        attempt=attempts,
        rows=0,
        total_api=0,
        instance_id="",
        error=last_error[:2000],
        started_at=started_at,
        finished_at=_now(),
    )
    return pd.DataFrame(columns=OUTPUT_COLUMNS), manifest


def _run_semantic_window_with_retries(
    *,
    client: MicroStrategyRestClient,
    report_id: str,
    report_definition: dict[str, Any],
    window: MonthWindow,
    output_columns: list[str],
    page_size: int,
    max_attempts: int,
    sleep_between_attempts: int,
    logger: Callable[[str], None],
    fetch_all_pages: bool,
    max_rows: int | None,
) -> tuple[pd.DataFrame, dict[str, Any]]:
    last_error = ""
    attempts = max(1, max_attempts)
    started_at = _now()

    for attempt in range(1, attempts + 1):
        started_at = _now()
        try:
            logger(f"{window.label}: tentativa MicroStrategy IA {attempt}/{attempts}.")
            df, instance_id, total_api = _execute_semantic_window_once(
                client=client,
                report_id=report_id,
                report_definition=report_definition,
                window=window,
                output_columns=output_columns,
                page_size=page_size,
                logger=logger,
                fetch_all_pages=fetch_all_pages,
                max_rows=max_rows,
            )
            manifest = _manifest_row(
                window=window,
                status="ok",
                attempt=attempt,
                rows=len(df),
                total_api=total_api,
                instance_id=instance_id,
                error="",
                started_at=started_at,
                finished_at=_now(),
            )
            return df, manifest
        except Exception as exc:
            last_error = str(exc)
            logger(f"{window.label}: erro na tentativa MicroStrategy IA {attempt}/{attempts}: {last_error}")
            if attempt < attempts:
                logger(f"{window.label}: aguardando {sleep_between_attempts}s antes de tentar novamente.")
                time.sleep(sleep_between_attempts)

    manifest = _manifest_row(
        window=window,
        status="erro",
        attempt=attempts,
        rows=0,
        total_api=0,
        instance_id="",
        error=last_error[:2000],
        started_at=started_at,
        finished_at=_now(),
    )
    return pd.DataFrame(columns=output_columns), manifest


def _execute_semantic_window_once(
    *,
    client: MicroStrategyRestClient,
    report_id: str,
    report_definition: dict[str, Any],
    window: MonthWindow,
    output_columns: list[str],
    page_size: int,
    logger: Callable[[str], None],
    fetch_all_pages: bool,
    max_rows: int | None,
) -> tuple[pd.DataFrame, str, int]:
    instance_id = ""
    try:
        logger(f"{window.label}: criando instancia transitoria MicroStrategy IA.")
        instance_id = _create_model_instance(client, report_id)
        logger(f"{window.label}: instancia MicroStrategy IA {instance_id} criada.")
        patched_definition, rank_removed = patch_report_definition_for_window(
            report_definition,
            window,
            remove_rank=True,
        )
        logger(f"{window.label}: filtro do chunk aplicado; rank removido={rank_removed}.")
        _put_report_definition(client, report_id, instance_id, patched_definition)
        logger(f"{window.label}: executando instancia MicroStrategy IA.")
        _execute_model_instance(client, report_id, instance_id)
        if fetch_all_pages:
            logger(f"{window.label}: buscando todas as paginas em blocos de {page_size} linha(s).")
            rows, total_api = _fetch_all_generic_rows(client, report_id, instance_id, page_size, logger)
        else:
            limit = min(page_size, max_rows or page_size)
            logger(f"{window.label}: buscando amostra limitada a {limit} linha(s), sem paginacao completa.")
            rows, total_api = _fetch_limited_generic_rows(
                client,
                report_id,
                instance_id,
                limit,
                logger=logger,
                max_rows=max_rows,
            )
        frame = pd.DataFrame(rows)
        frame = _normalize_freeform_frame(frame, output_columns, window)
        return frame, instance_id, total_api
    finally:
        if instance_id:
            logger(f"{window.label}: removendo instancia MicroStrategy IA {instance_id}.")
            _delete_model_instance(client, report_id, instance_id)


def _execute_window_once(
    *,
    client: MicroStrategyRestClient,
    report_id: str,
    report_definition: dict[str, Any],
    window: MonthWindow,
    page_size: int,
    logger: Callable[[str], None],
) -> tuple[pd.DataFrame, str, int]:
    instance_id = ""
    try:
        logger(f"{window.label}: criando instancia transitoria.")
        instance_id = _create_model_instance(client, report_id)
        logger(f"{window.label}: instancia {instance_id} criada.")
        patched_definition, _rank_removed = patch_report_definition_for_window(
            report_definition,
            window,
            remove_rank=True,
        )
        logger(f"{window.label}: filtro do chunk aplicado; rank removido={_rank_removed}.")
        _put_report_definition(client, report_id, instance_id, patched_definition)
        logger(f"{window.label}: executando instancia no Intelligence Server.")
        _execute_model_instance(client, report_id, instance_id)
        logger(f"{window.label}: buscando resultados em paginas de {page_size} linha(s).")
        rows, total_api = _fetch_all_rows(client, report_id, instance_id, page_size, logger)
        frame = pd.DataFrame(rows, columns=OUTPUT_COLUMNS)
        if not frame.empty:
            frame["MES_REF"] = window.label
            frame["CHUNK_INICIO"] = window.start.isoformat()
            frame["CHUNK_FIM"] = window.end.isoformat()
        return frame, instance_id, total_api
    finally:
        if instance_id:
            logger(f"{window.label}: removendo instancia transitoria {instance_id}.")
            _delete_model_instance(client, report_id, instance_id)


def _run_freeform_window_with_retries(
    *,
    client: MicroStrategyRestClient,
    window: MonthWindow,
    page_size: int,
    max_attempts: int,
    sleep_between_attempts: int,
    logger: Callable[[str], None],
) -> tuple[pd.DataFrame, dict[str, Any]]:
    last_error = ""
    attempts = max(1, max_attempts)
    started_at = _now()

    for attempt in range(1, attempts + 1):
        started_at = _now()
        try:
            logger(f"{window.label}: tentativa SQL {attempt}/{attempts}.")
            df, report_id, instance_id, total_api = _execute_freeform_window_once(
                client=client,
                window=window,
                page_size=page_size,
                logger=logger,
            )
            manifest = _manifest_row(
                window=window,
                status="ok",
                attempt=attempt,
                rows=len(df),
                total_api=total_api,
                instance_id=f"{report_id}/{instance_id}",
                error="",
                started_at=started_at,
                finished_at=_now(),
            )
            return df, manifest
        except Exception as exc:
            last_error = str(exc)
            logger(f"{window.label}: erro na tentativa SQL {attempt}/{attempts}: {last_error}")
            if attempt < attempts:
                logger(f"{window.label}: aguardando {sleep_between_attempts}s antes de tentar novamente.")
                time.sleep(sleep_between_attempts)

    manifest = _manifest_row(
        window=window,
        status="erro",
        attempt=attempts,
        rows=0,
        total_api=0,
        instance_id="",
        error=last_error[:2000],
        started_at=started_at,
        finished_at=_now(),
    )
    return pd.DataFrame(columns=OUTPUT_COLUMNS), manifest


def _execute_freeform_window_once(
    *,
    client: MicroStrategyRestClient,
    window: MonthWindow,
    page_size: int,
    logger: Callable[[str], None],
) -> tuple[pd.DataFrame, str, str, int]:
    report_id = ""
    instance_id = ""
    try:
        logger(f"{window.label}: criando relatorio Freeform SQL temporario.")
        report_id = _create_freeform_efd_saida_report(client, window)
        logger(f"{window.label}: relatorio temporario {report_id} criado.")

        logger(f"{window.label}: criando instancia de execucao SQL.")
        instance_id = _create_persisted_report_instance(client, report_id)
        logger(f"{window.label}: instancia SQL {instance_id} criada.")

        logger(f"{window.label}: executando SQL no Intelligence Server.")
        _execute_model_instance(client, report_id, instance_id)

        logger(f"{window.label}: buscando resultados SQL em paginas de {page_size} linha(s).")
        rows, total_api = _fetch_all_rows(client, report_id, instance_id, page_size, logger)
        frame = pd.DataFrame(rows, columns=OUTPUT_COLUMNS)
        if not frame.empty:
            frame["MES_REF"] = window.label
            frame["CHUNK_INICIO"] = window.start.isoformat()
            frame["CHUNK_FIM"] = window.end.isoformat()
        return frame, report_id, instance_id, total_api
    finally:
        if instance_id and report_id:
            logger(f"{window.label}: removendo instancia SQL {instance_id}.")
            _delete_model_instance(client, report_id, instance_id)
        if report_id:
            logger(f"{window.label}: apagando relatorio temporario {report_id}.")
            _delete_report_object(client, report_id)


def _run_generic_freeform_window_with_retries(
    *,
    client: MicroStrategyRestClient,
    window: MonthWindow,
    sql_template: str,
    output_columns: list[str],
    attribute_columns: list[str],
    metric_columns: list[str],
    page_size: int,
    max_attempts: int,
    sleep_between_attempts: int,
    logger: Callable[[str], None],
    fetch_all_pages: bool,
    max_rows: int | None,
    report_name_prefix: str,
    description: str,
) -> tuple[pd.DataFrame, dict[str, Any]]:
    attempts = max(1, max_attempts)
    last_error = ""
    started_at = _now()

    for attempt in range(1, attempts + 1):
        started_at = _now()
        try:
            logger(f"{window.label}: tentativa Freeform generica {attempt}/{attempts}.")
            df, report_id, instance_id, total_api = _execute_generic_freeform_window_once(
                client=client,
                window=window,
                sql_template=sql_template,
                output_columns=output_columns,
                attribute_columns=attribute_columns,
                metric_columns=metric_columns,
                page_size=page_size,
                logger=logger,
                fetch_all_pages=fetch_all_pages,
                max_rows=max_rows,
                report_name_prefix=report_name_prefix,
                description=description,
            )
            manifest = _manifest_row(
                window=window,
                status="ok",
                attempt=attempt,
                rows=len(df),
                total_api=total_api,
                instance_id=f"{report_id}/{instance_id}",
                error="",
                started_at=started_at,
                finished_at=_now(),
            )
            return df, manifest
        except Exception as exc:
            last_error = str(exc)
            logger(f"{window.label}: erro na tentativa Freeform generica {attempt}/{attempts}: {last_error}")
            if attempt < attempts:
                logger(f"{window.label}: aguardando {sleep_between_attempts}s antes de tentar novamente.")
                time.sleep(sleep_between_attempts)

    manifest = _manifest_row(
        window=window,
        status="erro",
        attempt=attempts,
        rows=0,
        total_api=0,
        instance_id="",
        error=last_error[:2000],
        started_at=started_at,
        finished_at=_now(),
    )
    return pd.DataFrame(columns=output_columns), manifest


def _execute_generic_freeform_window_once(
    *,
    client: MicroStrategyRestClient,
    window: MonthWindow,
    sql_template: str,
    output_columns: list[str],
    attribute_columns: list[str],
    metric_columns: list[str],
    page_size: int,
    logger: Callable[[str], None],
    fetch_all_pages: bool,
    max_rows: int | None,
    report_name_prefix: str,
    description: str,
) -> tuple[pd.DataFrame, str, str, int]:
    report_id = ""
    instance_id = ""
    sql = _render_sql_template(sql_template, window)
    try:
        logger(f"{window.label}: SQL Freeform renderizado:\n{sql}")
        logger(f"{window.label}: criando relatorio Freeform SQL temporario generico.")
        report_id = _create_freeform_sql_report(
            client=client,
            name=f"{report_name_prefix} {window.label} {int(time.time())}",
            sql=sql,
            output_columns=output_columns,
            attribute_columns=attribute_columns,
            metric_columns=metric_columns,
            description=description,
        )
        logger(f"{window.label}: relatorio temporario {report_id} criado.")

        logger(f"{window.label}: criando instancia de execucao SQL.")
        instance_id = _create_persisted_report_instance(client, report_id)
        logger(f"{window.label}: instancia SQL {instance_id} criada.")

        logger(f"{window.label}: executando SQL no Intelligence Server.")
        _execute_model_instance(client, report_id, instance_id)

        if fetch_all_pages:
            logger(f"{window.label}: buscando todas as paginas em blocos de {page_size} linha(s).")
            rows, total_api = _fetch_all_generic_rows(client, report_id, instance_id, page_size, logger)
        else:
            limit = min(page_size, max_rows or page_size)
            logger(f"{window.label}: buscando amostra limitada a {limit} linha(s), sem paginacao completa.")
            rows, total_api = _fetch_limited_generic_rows(
                client,
                report_id,
                instance_id,
                limit,
                logger=logger,
                max_rows=max_rows,
            )
        frame = pd.DataFrame(rows)
        frame = _normalize_freeform_frame(frame, output_columns, window)
        return frame, report_id, instance_id, total_api
    finally:
        if instance_id and report_id:
            logger(f"{window.label}: removendo instancia SQL {instance_id}.")
            _delete_model_instance(client, report_id, instance_id)
        if report_id:
            logger(f"{window.label}: apagando relatorio temporario {report_id}.")
            _delete_report_object(client, report_id)


def _run_item_detail_window_with_retries(
    *,
    client: MicroStrategyRestClient,
    window: MonthWindow,
    cnpjs: list[str],
    page_size: int,
    max_attempts: int,
    sleep_between_attempts: int,
    logger: Callable[[str], None],
) -> tuple[pd.DataFrame, dict[str, Any]]:
    attempts = max(1, max_attempts)
    last_error = ""
    started_at = _now()
    for attempt in range(1, attempts + 1):
        started_at = _now()
        try:
            logger(f"{window.label}: tentativa itens {attempt}/{attempts}.")
            df, report_id, instance_id, total_api = _execute_item_detail_window_once(
                client=client,
                window=window,
                cnpjs=cnpjs,
                page_size=page_size,
                logger=logger,
            )
            manifest = _analysis_manifest_row(
                etapa="itens_top20",
                status="ok",
                rows=len(df),
                error="",
                started_at=started_at,
                finished_at=_now(),
                details=f"{window.label}; total_api={total_api}; {report_id}/{instance_id}",
            )
            return df, manifest
        except Exception as exc:
            last_error = str(exc)
            logger(f"{window.label}: erro na tentativa de itens {attempt}/{attempts}: {last_error}")
            if attempt < attempts:
                logger(f"{window.label}: aguardando {sleep_between_attempts}s antes de tentar novamente.")
                time.sleep(sleep_between_attempts)

    manifest = _analysis_manifest_row(
        etapa="itens_top20",
        status="erro",
        rows=0,
        error=last_error[:2000],
        started_at=started_at,
        finished_at=_now(),
        details=window.label,
    )
    return pd.DataFrame(columns=ITEM_DETAIL_COLUMNS), manifest


def _execute_item_detail_window_once(
    *,
    client: MicroStrategyRestClient,
    window: MonthWindow,
    cnpjs: list[str],
    page_size: int,
    logger: Callable[[str], None],
) -> tuple[pd.DataFrame, str, str, int]:
    report_id = ""
    instance_id = ""
    try:
        logger(f"{window.label}: criando relatorio temporario de itens.")
        report_id = _create_item_detail_report(client, window, cnpjs)
        logger(f"{window.label}: relatorio de itens {report_id} criado.")
        instance_id = _create_persisted_report_instance(client, report_id)
        logger(f"{window.label}: instancia de itens {instance_id} criada.")
        _execute_model_instance(client, report_id, instance_id)
        rows, total_api = _fetch_all_generic_rows(client, report_id, instance_id, page_size, logger)
        return pd.DataFrame(rows, columns=ITEM_DETAIL_COLUMNS), report_id, instance_id, total_api
    finally:
        if instance_id and report_id:
            logger(f"{window.label}: removendo instancia de itens {instance_id}.")
            _delete_model_instance(client, report_id, instance_id)
        if report_id:
            logger(f"{window.label}: apagando relatorio temporario de itens {report_id}.")
            _delete_report_object(client, report_id)


def _create_model_instance(client: MicroStrategyRestClient, report_id: str) -> str:
    response = client.request(
        "POST",
        f"/model/reports/{report_id}/instances",
        params={"executionStage": "no_action"},
    )
    _raise_for_status(response, "Criacao da instancia transitoria")
    instance_id = response.headers.get("X-MSTR-MS-Instance")
    if not instance_id:
        instance_id = response.json().get("id")
    if not instance_id:
        raise RuntimeError("A API nao retornou X-MSTR-MS-Instance.")
    return instance_id


def _create_freeform_efd_saida_report(
    client: MicroStrategyRestClient,
    window: MonthWindow,
) -> str:
    report_name = f"TMP DIFAL EFD Saida SQL {window.label} {int(time.time())}"
    body = _freeform_efd_saida_report_body(report_name, _freeform_efd_saida_sql(window))
    response = client.request(
        "POST",
        "/model/reports",
        params={"showExpressionAs": "tree"},
        headers={"Content-Type": "application/json"},
        json=body,
        timeout=120,
    )
    _raise_for_status(response, "Criacao do relatorio Freeform SQL")

    report_id = response.json().get("information", {}).get("objectId")
    instance_id = response.headers.get("X-MSTR-MS-Instance")
    if not report_id or not instance_id:
        raise RuntimeError("Criacao Freeform SQL nao retornou report_id ou X-MSTR-MS-Instance.")

    save_response = client.request(
        "POST",
        f"/model/reports/{report_id}/instances/saveAs",
        headers={"Content-Type": "application/json", "X-MSTR-MS-Instance": instance_id},
        json={"name": report_name, "destinationFolderId": FOLDER_ID},
        timeout=120,
    )
    _raise_for_status(save_response, "SaveAs do relatorio Freeform SQL")
    return report_id


def _create_item_detail_report(
    client: MicroStrategyRestClient,
    window: MonthWindow,
    cnpjs: list[str],
) -> str:
    report_name = f"TMP DIFAL Itens Top20 {window.label} {int(time.time())}"
    body = _item_detail_report_body(report_name, _item_detail_sql(window, cnpjs))
    response = client.request(
        "POST",
        "/model/reports",
        params={"showExpressionAs": "tree"},
        headers={"Content-Type": "application/json"},
        json=body,
        timeout=120,
    )
    _raise_for_status(response, "Criacao do relatorio Freeform SQL de itens")

    report_id = response.json().get("information", {}).get("objectId")
    instance_id = response.headers.get("X-MSTR-MS-Instance")
    if not report_id or not instance_id:
        raise RuntimeError("Criacao do relatorio de itens nao retornou report_id ou X-MSTR-MS-Instance.")

    save_response = client.request(
        "POST",
        f"/model/reports/{report_id}/instances/saveAs",
        headers={"Content-Type": "application/json", "X-MSTR-MS-Instance": instance_id},
        json={"name": report_name, "destinationFolderId": FOLDER_ID},
        timeout=120,
    )
    _raise_for_status(save_response, "SaveAs do relatorio Freeform SQL de itens")
    return report_id


def _render_sql_template(sql_template: str, window: MonthWindow) -> str:
    return sql_template.format(
        start_date=window.start.isoformat(),
        end_date=window.end.isoformat(),
        start=window.start.isoformat(),
        end=window.end.isoformat(),
    )


def _create_freeform_sql_report(
    *,
    client: MicroStrategyRestClient,
    name: str,
    sql: str,
    output_columns: list[str],
    attribute_columns: list[str],
    metric_columns: list[str],
    description: str,
) -> str:
    body = _freeform_sql_report_body(
        name=name,
        sql=sql,
        output_columns=output_columns,
        attribute_columns=attribute_columns,
        metric_columns=metric_columns,
        description=description,
    )
    response = client.request(
        "POST",
        "/model/reports",
        params={"showExpressionAs": "tree"},
        headers={"Content-Type": "application/json"},
        json=body,
        timeout=120,
    )
    _raise_for_status(response, "Criacao do relatorio Freeform SQL generico")

    report_id = response.json().get("information", {}).get("objectId")
    instance_id = response.headers.get("X-MSTR-MS-Instance")
    if not report_id or not instance_id:
        raise RuntimeError("Criacao Freeform SQL generica nao retornou report_id ou X-MSTR-MS-Instance.")

    save_response = client.request(
        "POST",
        f"/model/reports/{report_id}/instances/saveAs",
        headers={"Content-Type": "application/json", "X-MSTR-MS-Instance": instance_id},
        json={"name": name, "destinationFolderId": FOLDER_ID},
        timeout=120,
    )
    _raise_for_status(save_response, "SaveAs do relatorio Freeform SQL generico")
    return report_id


def _freeform_sql_report_body(
    *,
    name: str,
    sql: str,
    output_columns: list[str],
    attribute_columns: list[str],
    metric_columns: list[str],
    description: str,
) -> dict[str, Any]:
    text_type = {"type": "variable_length_string", "precision": 1024}
    short_text_type = {"type": "variable_length_string", "precision": 64}
    number_type = {"type": "numeric", "precision": 18, "scale": 4}
    metadata_columns = {"MES_REF", "CHUNK_INICIO", "CHUNK_FIM"}
    attribute_set = set(attribute_columns)
    metric_set = set(metric_columns)

    physical_columns: list[tuple[str, dict[str, Any]]] = []
    for column in output_columns:
        if column in metadata_columns:
            continue
        if column in metric_set:
            physical_columns.append((column, number_type))
        elif column in attribute_set:
            physical_columns.append((column, short_text_type if column.startswith("UF_") else text_type))

    return {
        "information": {
            "name": name,
            "destinationFolderId": FOLDER_ID,
            "description": description,
        },
        "sourceType": "custom_sql_free_form",
        "dataSource": {
            "table": {
                "physicalTable": {
                    "columns": [
                        {"name": column, "dataType": data_type}
                        for column, data_type in physical_columns
                    ],
                    "sqlExpression": {
                        "tree": {
                            "type": "operator",
                            "function": "concat_no_blank",
                            "children": [
                                {"type": "constant", "variant": {"type": "string", "value": sql}}
                            ],
                        }
                    },
                },
                "attributes": [
                    {
                        "name": column,
                        "forms": [
                            {
                                "id": COMMON_ID_FORM_ID,
                                "name": "ID",
                                "displayFormat": "text",
                                "expression": {"tree": {"type": "column_reference", "name": column}},
                            }
                        ],
                    }
                    for column in attribute_columns
                ],
                "metrics": [
                    {
                        "name": column,
                        "dataType": number_type,
                        "expression": {"tree": {"type": "column_reference", "name": column}},
                    }
                    for column in metric_columns
                ],
                "dataSource": {
                    "objectId": TERADATA_DATASOURCE_ID,
                    "subType": "db_role",
                    "name": ":: projeto :: Plataform Analytics - TERADATA",
                },
            }
        },
    }


def _freeform_efd_saida_report_body(name: str, sql: str) -> dict[str, Any]:
    text_type = {"type": "variable_length_string", "precision": 512}
    uf_type = {"type": "variable_length_string", "precision": 2}
    number_type = {"type": "numeric", "precision": 18, "scale": 2}

    attribute_columns = [
        ("NOME_EMITENTE", text_type),
        ("CNPJ_CPF_EMITENTE", text_type),
        ("UF_EMITENTE", uf_type),
    ]
    metric_columns = [
        ("QTD_DOC", number_type),
        ("TOTAL_ITEM", number_type),
        ("DIFAL_DEST", number_type),
    ]

    return {
        "information": {
            "name": name,
            "destinationFolderId": FOLDER_ID,
            "description": "Relatorio temporario gerado pelo notebook DIFAL em chunks.",
        },
        "sourceType": "custom_sql_free_form",
        "dataSource": {
            "table": {
                "physicalTable": {
                    "columns": [
                        {"name": column, "dataType": data_type}
                        for column, data_type in [*attribute_columns, *metric_columns]
                    ],
                    "sqlExpression": {
                        "tree": {
                            "type": "operator",
                            "function": "concat_no_blank",
                            "children": [
                                {
                                    "type": "constant",
                                    "variant": {"type": "string", "value": sql},
                                }
                            ],
                        }
                    },
                },
                "attributes": [
                    {
                        "name": column,
                        "forms": [
                            {
                                "id": COMMON_ID_FORM_ID,
                                "name": "ID",
                                "displayFormat": "text",
                                "expression": {
                                    "tree": {"type": "column_reference", "name": column}
                                },
                            }
                        ],
                    }
                    for column, _data_type in attribute_columns
                ],
                "metrics": [
                    {
                        "name": column,
                        "dataType": data_type,
                        "expression": {"tree": {"type": "column_reference", "name": column}},
                    }
                    for column, data_type in metric_columns
                ],
                "dataSource": {
                    "objectId": TERADATA_DATASOURCE_ID,
                    "subType": "db_role",
                    "name": ":: projeto :: Plataform Analytics - TERADATA",
                },
            }
        },
    }


def _item_detail_report_body(name: str, sql: str) -> dict[str, Any]:
    text = {"type": "variable_length_string", "precision": 1024}
    short_text = {"type": "variable_length_string", "precision": 64}
    number = {"type": "numeric", "precision": 18, "scale": 4}
    date_type = {"type": "date"}

    text_columns = {
        "IdNFe",
        "ModeloDoc",
        "SerieDoc",
        "NrDoc",
        "CdFinalidadeNFe",
        "TpOperacao",
        "NmEmit",
        "CNPJEmit",
        "CadICMSEmit",
        "MunicipioEmit",
        "UFEmit",
        "NM_PARTICIPANTE",
        "CD_CNPJ_CPF_PARTICIPANTE",
        "CD_IE_PARTICIPANTE",
        "MUNIC_PARTICIPANTE",
        "UF_PARTICIPANTE",
        "CD_TIPO_IE_DEST",
        "NrItem",
        "GTINItem",
        "CdItem",
        "DescItem",
        "NCM",
        "CEST",
        "CST",
        "CFOP",
        "UnidadeTributavel",
        "CdOrigemMercadoria",
    }
    number_columns = [column for column in ITEM_DETAIL_COLUMNS if column not in text_columns | {"DtEmissao"}]

    column_types: dict[str, dict[str, Any]] = {}
    for column in text_columns:
        column_types[column] = short_text if column not in {"DescItem", "NmEmit", "NM_PARTICIPANTE"} else text
    for column in number_columns:
        column_types[column] = number
    column_types["DtEmissao"] = date_type

    attributes = [
        {
            "name": column,
            "forms": [
                {
                    "id": COMMON_ID_FORM_ID,
                    "name": "ID",
                    "displayFormat": "date" if column == "DtEmissao" else "text",
                    "expression": {"tree": {"type": "column_reference", "name": column}},
                }
            ],
        }
        for column in ITEM_DETAIL_COLUMNS
        if column not in number_columns
    ]
    metrics = [
        {
            "name": column,
            "dataType": number,
            "expression": {"tree": {"type": "column_reference", "name": column}},
        }
        for column in number_columns
    ]

    return {
        "information": {
            "name": name,
            "destinationFolderId": FOLDER_ID,
            "description": "Relatorio temporario analitico de itens DIFAL Top 20.",
        },
        "sourceType": "custom_sql_free_form",
        "dataSource": {
            "table": {
                "physicalTable": {
                    "columns": [
                        {"name": column, "dataType": column_types[column]}
                        for column in ITEM_DETAIL_COLUMNS
                    ],
                    "sqlExpression": {
                        "tree": {
                            "type": "operator",
                            "function": "concat_no_blank",
                            "children": [
                                {"type": "constant", "variant": {"type": "string", "value": sql}}
                            ],
                        }
                    },
                },
                "attributes": attributes,
                "metrics": metrics,
                "dataSource": {
                    "objectId": TERADATA_DATASOURCE_ID,
                    "subType": "db_role",
                    "name": ":: projeto :: Plataform Analytics - TERADATA",
                },
            }
        },
    }


def _freeform_efd_saida_sql(window: MonthWindow) -> str:
    start = window.start.isoformat()
    end = window.end.isoformat()
    return f"""
SELECT
    DF.NM_EMIT AS NOME_EMITENTE,
    CAST(DF.CD_CNPJ_CPF_EMIT AS VARCHAR(32)) AS CNPJ_CPF_EMITENTE,
    ENDE.CD_SIGLA_UF AS UF_EMITENTE,
    COUNT(DISTINCT DF.CD_CHAVE_DFE) AS QTD_DOC,
    SUM(ITEM.VL_TOTAL) AS TOTAL_ITEM,
    SUM(ITEM.VL_ICMS_UF_DEST) AS DIFAL_DEST
FROM P_ACCDB.FAT_DOC_FISC DF
INNER JOIN P_ACCDB.FAT_ITEM ITEM
    ON DF.CD_DOC_FISC = ITEM.CD_DOC_FISC
   AND DF.DT_EMIS_DOC_FISC = ITEM.DT_EMIS_DOC_FISC
   AND DF.CD_SIST_ORIG = ITEM.CD_SIST_ORIG
LEFT JOIN P_ACCDB.DIM_PARTICP_DOC_FISC ENDE
    ON DF.CD_PARTICP_EMIT = ENDE.CD_PARTICP_DOC_FISC
WHERE
    DF.CD_SIT_DOC_FISC = 1
    AND DF.CD_SIST_ORIG = 1
    AND DF.CD_UF_EMIT <> 41
    AND DF.CD_UF_DEST = 41
    AND ITEM.CD_CFOP > 6000
    AND DF.CD_TIPO_IE_DEST = 9
    AND DF.DT_EMIS_DOC_FISC BETWEEN DATE '{start}' AND DATE '{end}'
    AND EXISTS (
        SELECT 1
        FROM P_ACCDB.FAT_DOC_FISC DF2
        WHERE DF2.CD_CHAVE_DFE = DF.CD_CHAVE_DFE
          AND DF2.CD_SIT_DOC_FISC = 1
          AND DF2.CD_SIST_ORIG = 2
          AND DF2.DT_EMIS_DOC_FISC BETWEEN DATE '{start}' AND DATE '{end}'
    )
GROUP BY
    1, 2, 3
HAVING
    SUM(ITEM.VL_ICMS_UF_DEST) > 0
ORDER BY
    6 DESC
""".strip()


def _item_detail_sql(window: MonthWindow, cnpjs: list[str]) -> str:
    start = window.start.isoformat()
    end = window.end.isoformat()
    cnpj_list = ",\n        ".join(cnpjs)
    return f"""
SELECT
    DF.CD_CHAVE_DFE AS IdNFe,
    DF.DT_EMIS_DOC_FISC AS DtEmissao,
    CAST(DF.CD_MODEL_DOC_FISC AS VARCHAR(16)) AS ModeloDoc,
    CAST(DF.NU_SERIE_DOC AS VARCHAR(32)) AS SerieDoc,
    CAST(DF.NU_DOC_FISC AS VARCHAR(32)) AS NrDoc,
    CAST(DF.CD_FINAL_DOC_FISC AS VARCHAR(16)) AS CdFinalidadeNFe,
    CAST(DF.CD_TIPO_OPER AS VARCHAR(16)) AS TpOperacao,
    DF.NM_EMIT AS NmEmit,
    CAST(DF.CD_CNPJ_CPF_EMIT AS VARCHAR(32)) AS CNPJEmit,
    CAST(DF.CD_IE_EMIT AS VARCHAR(32)) AS CadICMSEmit,
    ENDE.NM_MUN_ANALIT AS MunicipioEmit,
    ENDE.CD_SIGLA_UF AS UFEmit,
    CASE WHEN DF.CD_TIPO_OPER = 1 THEN DF.NM_DEST ELSE DF.NM_REMET END AS NM_PARTICIPANTE,
    CAST(CASE WHEN DF.CD_TIPO_OPER = 1 THEN DF.CD_CNPJ_CPF_DEST ELSE DF.CD_CNPJ_CPF_REMET END AS VARCHAR(32)) AS CD_CNPJ_CPF_PARTICIPANTE,
    CAST(CASE WHEN DF.CD_TIPO_OPER = 1 THEN DF.CD_IE_DEST ELSE DF.CD_IE_REMET END AS VARCHAR(32)) AS CD_IE_PARTICIPANTE,
    CASE WHEN DF.CD_TIPO_OPER = 1 THEN ENDD.NM_MUN_ANALIT ELSE ENDR.NM_MUN_ANALIT END AS MUNIC_PARTICIPANTE,
    CASE WHEN DF.CD_TIPO_OPER = 1 THEN ENDD.CD_SIGLA_UF ELSE ENDR.CD_SIGLA_UF END AS UF_PARTICIPANTE,
    CAST(DF.CD_TIPO_IE_DEST AS VARCHAR(16)) AS CD_TIPO_IE_DEST,
    CAST(ITEM.CD_ITEM AS VARCHAR(32)) AS NrItem,
    CAST(ITEM.CD_GTIN AS VARCHAR(64)) AS GTINItem,
    CAST(ITEM.CD_ORIG_ITEM AS VARCHAR(64)) AS CdItem,
    ITEM.DS_ITEM AS DescItem,
    CAST(ITEM.CD_NCM_ORIG AS VARCHAR(32)) AS NCM,
    CAST(ITEM.CD_CEST AS VARCHAR(32)) AS CEST,
    CAST(CST.CD_SIT_TRIB_ORIG AS VARCHAR(16)) AS CST,
    CAST(ITEM.CD_CFOP AS VARCHAR(16)) AS CFOP,
    ITEM.QT_ITEM AS QtdComercial,
    ITEM.DS_UNID_TRIB AS UnidadeTributavel,
    ITEM.VL_UNIT_ITEM_COMERC AS VlUnitComercial,
    ITEM.VL_TOTAL AS VlTotalItem,
    ITEM.QT_TRIB AS QtdTributavel,
    ITEM.VL_UNIT_TRIB AS VlUnitarioTributacao,
    ITEM.VL_FRETE AS VlFrete,
    ITEM.VL_SEGURO AS VlSeguro,
    ITEM.VL_DESC AS VlDesconto,
    ITEM.VL_OUTROS AS VlOutro,
    ITEM.VL_ALIQ_IPI AS AliquotaIPI,
    ITEM.VL_IPI AS VlIPI,
    CAST(ITEM.CD_ORIG_SERV_MERC AS VARCHAR(16)) AS CdOrigemMercadoria,
    ITEM.VL_BC_ICMS AS VlBaseCalculoICMS,
    ITEM.VL_ALIQ_ICMS AS AliquotaICMS,
    ITEM.VL_ICMS AS VlICMS,
    ITEM.VL_MVA_ICMS_ST AS PercMVAICMSST,
    ITEM.VL_RED_BC_ICMS_ST AS PercReducaoBaseCalculoICMSST,
    ITEM.VL_BC_ICMS_ST AS VlBaseCalculoICMSST,
    ITEM.VL_ALIQ_ICMS_ST AS AliquotaICMSST,
    ITEM.VL_ICMS_ST AS VlICMSST,
    ITEM.VL_ALIQ_UF_DEST AS VL_ALIQ_UF_DEST,
    ITEM.VL_ICMS_UF_DEST AS VL_ICMS_UF_DEST,
    ITEM.VL_ICMS_FCP_UF_DEST AS VL_ICMS_FCP_UF_DEST,
    DF.VL_BC_ICMS AS TotVlBaseCalculoICMS,
    DF.VL_ICMS AS TotVlICMS,
    DF.VL_BC_ICMS_ST AS TotVlBaseCalculoICMSST,
    DF.VL_ICMS_ST AS TotVlICMSST,
    DF.VL_TOTAL_ITEM_DOC_FISC AS TotVlTotalItem,
    DF.VL_FRETE_DOC_FISC AS TotVlFrete,
    DF.VL_SEGURO_DOC_FISC AS TotVlSeguro,
    DF.VL_DESC_DOC_FISC AS TotVlDesconto,
    DF.VL_IPI AS TotVlIPI,
    DF.VL_TOTAL_DOC_FISC AS TotVlTotalDoc
FROM P_ACCDB.FAT_DOC_FISC DF
INNER JOIN P_ACCDB.FAT_ITEM ITEM
    ON DF.CD_DOC_FISC = ITEM.CD_DOC_FISC
   AND DF.DT_EMIS_DOC_FISC = ITEM.DT_EMIS_DOC_FISC
   AND DF.CD_SIST_ORIG = ITEM.CD_SIST_ORIG
LEFT JOIN P_ACCDB.DIM_PARTICP_DOC_FISC ENDE
    ON DF.CD_PARTICP_EMIT = ENDE.CD_PARTICP_DOC_FISC
LEFT JOIN P_ACCDB.DIM_PARTICP_DOC_FISC ENDD
    ON DF.CD_PARTICP_DEST = ENDD.CD_PARTICP_DOC_FISC
LEFT JOIN P_ACCDB.DIM_PARTICP_DOC_FISC ENDR
    ON DF.CD_PARTICP_REMET = ENDR.CD_PARTICP_DOC_FISC
LEFT JOIN P_ACCDB.DIM_TIPO_SIT_TRIB CST
    ON ITEM.CD_SIT_TRIB_ICMS = CST.CD_SIT_TRIB
WHERE
    DF.CD_SIT_DOC_FISC = 1
    AND DF.CD_SIST_ORIG = 1
    AND DF.CD_UF_EMIT <> 41
    AND DF.CD_UF_DEST = 41
    AND DF.CD_TIPO_IE_DEST = 9
    AND ITEM.CD_CFOP > 6000
    AND ITEM.VL_ICMS_UF_DEST > 0
    AND DF.CD_CNPJ_CPF_EMIT IN (
        {cnpj_list}
    )
    AND DF.DT_EMIS_DOC_FISC BETWEEN DATE '{start}' AND DATE '{end}'
    AND EXISTS (
        SELECT 1
        FROM P_ACCDB.FAT_DOC_FISC DF2
        WHERE DF2.CD_CHAVE_DFE = DF.CD_CHAVE_DFE
          AND DF2.CD_SIT_DOC_FISC = 1
          AND DF2.CD_SIST_ORIG = 2
          AND DF2.DT_EMIS_DOC_FISC BETWEEN DATE '{start}' AND DATE '{end}'
    )
ORDER BY
    DF.DT_EMIS_DOC_FISC,
    DF.NU_DOC_FISC,
    ITEM.CD_ITEM
""".strip()


def _create_persisted_report_instance(client: MicroStrategyRestClient, report_id: str) -> str:
    response = client.request(
        "POST",
        f"/model/reports/{report_id}/instances",
        headers={"Content-Type": "application/json"},
        json={},
        timeout=120,
    )
    _raise_for_status(response, "Criacao da instancia do relatorio Freeform SQL")
    instance_id = response.json().get("id") or response.headers.get("X-MSTR-MS-Instance")
    if not instance_id:
        raise RuntimeError("A API nao retornou id de instancia para o Freeform SQL.")
    return instance_id


def _put_report_definition(
    client: MicroStrategyRestClient,
    report_id: str,
    instance_id: str,
    report_definition: dict[str, Any],
) -> None:
    response = client.request(
        "PUT",
        f"/model/reports/{report_id}",
        params={"showExpressionAs": "tree", "executionStage": "no_action"},
        headers={"X-MSTR-MS-Instance": instance_id, "Content-Type": "application/json"},
        json=report_definition,
    )
    _raise_for_status(response, "Aplicacao do filtro mensal na instancia")


def _execute_model_instance(
    client: MicroStrategyRestClient,
    report_id: str,
    instance_id: str,
    timeout: int | None = None,
) -> None:
    request_kwargs: dict[str, Any] = {}
    if timeout is not None:
        request_kwargs["timeout"] = timeout
    response = client.request(
        "POST",
        f"/model/reports/{report_id}/instances",
        params={"executionStage": "execute_data"},
        headers={"X-MSTR-MS-Instance": instance_id},
        **request_kwargs,
    )
    if response.status_code not in {200, 201, 202, 204}:
        _raise_for_status(response, "Execucao da instancia mensal")


def _delete_model_instance(
    client: MicroStrategyRestClient,
    report_id: str,
    instance_id: str,
    timeout: int | None = None,
) -> None:
    request_kwargs: dict[str, Any] = {}
    if timeout is not None:
        request_kwargs["timeout"] = timeout
    response = client.request(
        "DELETE",
        f"/model/reports/{report_id}/instances",
        headers={"X-MSTR-MS-Instance": instance_id},
        **request_kwargs,
    )
    if response.status_code not in {200, 202, 204, 404}:
        _raise_for_status(response, "Exclusao da instancia transitoria")


def _delete_report_object(client: MicroStrategyRestClient, report_id: str) -> None:
    response = client.request(
        "DELETE",
        f"/objects/{report_id}",
        params={"type": 3},
        timeout=60,
    )
    if response.status_code not in {200, 202, 204, 404}:
        _raise_for_status(response, "Exclusao do relatorio temporario")


def _fetch_all_rows(
    client: MicroStrategyRestClient,
    report_id: str,
    instance_id: str,
    page_size: int,
    logger: Callable[[str], None],
) -> tuple[list[dict[str, Any]], int]:
    rows: list[dict[str, Any]] = []
    offset = 0
    total = 0

    while True:
        logger(f"Pagina offset={offset}, limit={page_size}: solicitando dados.")
        page = _fetch_ready_page(client, report_id, instance_id, offset, page_size, logger=logger)
        page_rows = parse_v2_report_rows(page)
        rows.extend(page_rows)

        paging = page.get("data", {}).get("paging", {})
        current = int(paging.get("current") or len(page_rows))
        total = int(paging.get("total") or len(rows))
        logger(f"Pagina recebida: {current} linha(s); acumulado={len(rows)}; total_api={total}.")

        if current == 0 or offset + current >= total:
            break
        offset += current

    return rows, total


def _fetch_all_generic_rows(
    client: MicroStrategyRestClient,
    report_id: str,
    instance_id: str,
    page_size: int,
    logger: Callable[[str], None],
) -> tuple[list[dict[str, Any]], int]:
    rows: list[dict[str, Any]] = []
    offset = 0
    total = 0
    while True:
        logger(f"Pagina offset={offset}, limit={page_size}: solicitando dados.")
        page = _fetch_ready_page(client, report_id, instance_id, offset, page_size, logger=logger)
        page_rows = parse_v2_generic_report_rows(page)
        rows.extend(page_rows)
        paging = page.get("data", {}).get("paging", {})
        current = int(paging.get("current") or len(page_rows))
        total = int(paging.get("total") or len(rows))
        logger(f"Pagina recebida: {current} linha(s); acumulado={len(rows)}; total_api={total}.")
        if current == 0 or offset + current >= total:
            break
        offset += current
    return rows, total


def _fetch_limited_generic_rows(
    client: MicroStrategyRestClient,
    report_id: str,
    instance_id: str,
    limit: int,
    *,
    logger: Callable[[str], None],
    max_rows: int | None = None,
) -> tuple[list[dict[str, Any]], int]:
    page = _fetch_ready_page(
        client,
        report_id,
        instance_id,
        0,
        limit,
        max_polls=10,
        poll_seconds=2,
        logger=logger,
    )
    rows = parse_v2_generic_report_rows(page)
    if max_rows is not None:
        rows = rows[:max_rows]
    paging = page.get("data", {}).get("paging", {})
    total = int(paging.get("total") or len(rows))
    logger(f"Amostra recebida: {len(rows)} linha(s); total_api={total}.")
    return rows, total


def _fetch_ready_page(
    client: MicroStrategyRestClient,
    report_id: str,
    instance_id: str,
    offset: int,
    limit: int,
    *,
    max_polls: int = 60,
    poll_seconds: int = 2,
    logger: Callable[[str], None] | None = None,
) -> dict[str, Any]:
    last_payload: dict[str, Any] | None = None
    for poll in range(1, max_polls + 1):
        response = client.request(
            "GET",
            f"/v2/reports/{report_id}/instances/{instance_id}",
            params={"offset": offset, "limit": limit},
        )
        _raise_for_status(response, "Leitura do grid da instancia mensal")
        payload = response.json()
        last_payload = payload
        status = payload.get("status")
        if status in (None, 1, "1", "ready", "Ready"):
            return payload
        if logger:
            logger(f"Instancia ainda nao pronta: status={status}; poll={poll}/{max_polls}.")
        time.sleep(poll_seconds)

    raise TimeoutError(f"Instancia nao ficou pronta. Ultimo payload: {last_payload}")


def parse_v2_generic_report_rows(payload: dict[str, Any]) -> list[dict[str, Any]]:
    grid = payload.get("definition", {}).get("grid", {})
    data = payload.get("data", {})
    row_attributes = grid.get("rows", [])
    metric_defs = _metric_definitions(grid)
    row_headers = data.get("headers", {}).get("rows", [])
    metric_values = data.get("metricValues", {}).get("raw", [])

    rows: list[dict[str, Any]] = []
    for row_index, header in enumerate(row_headers):
        row: dict[str, Any] = {}
        for attr_index, element_index in enumerate(header):
            if attr_index >= len(row_attributes):
                continue
            attr_def = row_attributes[attr_index]
            row[attr_def.get("name")] = _attribute_value(attr_def, element_index)

        values = metric_values[row_index] if row_index < len(metric_values) else []
        for metric_index, value in enumerate(values):
            if metric_index >= len(metric_defs):
                continue
            metric = metric_defs[metric_index]
            row[metric.get("name")] = value
        rows.append(row)
    return rows


def parse_v2_report_rows(payload: dict[str, Any]) -> list[dict[str, Any]]:
    grid = payload.get("definition", {}).get("grid", {})
    data = payload.get("data", {})
    row_attributes = grid.get("rows", [])
    metric_defs = _metric_definitions(grid)
    row_headers = data.get("headers", {}).get("rows", [])
    metric_values = data.get("metricValues", {}).get("raw", [])

    rows: list[dict[str, Any]] = []
    for row_index, header in enumerate(row_headers):
        row = {column: None for column in OUTPUT_COLUMNS}
        for attr_index, element_index in enumerate(header):
            if attr_index >= len(row_attributes):
                continue
            attr_def = row_attributes[attr_index]
            column = ATTRIBUTE_COLUMNS.get(attr_def.get("id"), attr_def.get("name"))
            row[column] = _attribute_value(attr_def, element_index)

        values = metric_values[row_index] if row_index < len(metric_values) else []
        for metric_index, value in enumerate(values):
            if metric_index >= len(metric_defs):
                continue
            metric = metric_defs[metric_index]
            column = METRIC_COLUMNS.get(metric.get("id"), metric.get("name"))
            row[column] = value

        rows.append(row)

    return rows


def _metric_definitions(grid: dict[str, Any]) -> list[dict[str, Any]]:
    for column in grid.get("columns", []):
        if column.get("type") in {"templateMetrics", "metrics"}:
            return column.get("elements", [])
    return []


def _attribute_value(attribute: dict[str, Any], element_index: Any) -> Any:
    if element_index is None:
        return None
    try:
        index = int(element_index)
    except (TypeError, ValueError):
        return None

    elements = attribute.get("elements") or []
    if index < 0 or index >= len(elements):
        return None

    element = elements[index]
    form_values = element.get("formValues") or []
    if not form_values:
        return element.get("name") or element.get("id")

    if attribute.get("id") == ATTR_UF_ID:
        form_names = [str(form.get("name", "")).upper() for form in attribute.get("forms", [])]
        if "SIGLA" in form_names:
            sigla_index = form_names.index("SIGLA")
            if sigla_index < len(form_values):
                return form_values[sigla_index]
        if len(form_values) > 1:
            return form_values[-1]

    return form_values[0]


def _find_date_predicate(report_definition: dict[str, Any]) -> dict[str, Any]:
    children = _get_filter_node(report_definition)["tree"].get("children") or []
    for child in children:
        if _is_date_predicate(child):
            return child
    raise RuntimeError("Filtro de data nao encontrado no relatorio.")


def _get_filter_node(report_definition: dict[str, Any]) -> dict[str, Any]:
    try:
        return report_definition["dataSource"]["filter"]
    except KeyError as exc:
        raise RuntimeError("Definicao do relatorio nao contem dataSource.filter.") from exc


def _is_date_predicate(predicate: dict[str, Any]) -> bool:
    tree = predicate.get("predicateTree") or {}
    attribute = tree.get("attribute") or {}
    return (
        predicate.get("type") == "predicate_form_qualification"
        and tree.get("function") == "between"
        and attribute.get("objectId") == DATE_ATTRIBUTE_ID
    )


def _is_rank_predicate(predicate: dict[str, Any]) -> bool:
    tree = predicate.get("predicateTree") or {}
    metric = tree.get("metric") or {}
    metric_function = str(tree.get("metricFunction") or "").lower()
    return (
        predicate.get("type") == "predicate_metric_qualification"
        and metric.get("objectId") == DIFAL_METRIC_ID
        and metric_function.startswith("rank")
    )


def _patch_date_predicate(predicate: dict[str, Any], window: MonthWindow) -> str:
    tree = predicate["predicateTree"]
    params = tree.get("parameters") or []
    if len(params) < 2:
        raise RuntimeError("Predicado de data nao contem dois parametros.")

    params[0]["constant"] = {"type": "date", "value": window.start.isoformat()}
    params[1]["constant"] = {"type": "date", "value": window.end.isoformat()}

    attribute_name = tree.get("attribute", {}).get("name", "Data de Emissao - Documento Fiscal")
    form_name = tree.get("form", {}).get("name", "ID")
    predicate_text = (
        f"({{{attribute_name}}} ({form_name}) Between "
        f"{_mstr_text_date(window.start)} and {_mstr_text_date(window.end)})"
    )
    predicate["predicateText"] = predicate_text
    return predicate_text


def _patch_filter_text(
    text: str,
    old_date_text: str | None,
    new_date_text: str | None,
    rank_texts: list[str],
) -> str:
    if old_date_text and new_date_text:
        text = text.replace(old_date_text, new_date_text)

    for rank_text in rank_texts:
        text = text.replace(f" And {rank_text}", "")
        text = text.replace(f"{rank_text} And ", "")
        text = text.replace(rank_text, "")

    text = re.sub(r"\s+", " ", text).strip()
    return text


def _mstr_text_date(value: date) -> str:
    return f"{value.month}/{value.day}/{value.year}"


def _manifest_row(
    *,
    window: MonthWindow,
    status: str,
    attempt: int,
    rows: int,
    total_api: int,
    instance_id: str,
    error: str,
    started_at: str,
    finished_at: str,
) -> dict[str, Any]:
    return {
        "MES_REF": window.label,
        "CHUNK_INICIO": window.start.isoformat(),
        "CHUNK_FIM": window.end.isoformat(),
        "STATUS": status,
        "TENTATIVA": attempt,
        "LINHAS": rows,
        "TOTAL_API": total_api,
        "INSTANCE_ID": instance_id,
        "ERRO": error,
        "INICIO_EXECUCAO": started_at,
        "FIM_EXECUCAO": finished_at,
    }


def _concat_or_empty(frames: list[pd.DataFrame], columns: list[str]) -> pd.DataFrame:
    if not frames:
        return pd.DataFrame(columns=columns)
    return pd.concat(frames, ignore_index=True)[columns]


def _resolve_potential_excel_path(path: str | Path | None) -> Path:
    if path is not None:
        resolved = Path(path)
        if not resolved.exists():
            raise FileNotFoundError(f"Arquivo de potencial DIFAL nao encontrado: {resolved}")
        return resolved

    output_dir = Path("outputs") / "difal_emitente_chunks" / "efd_saida_sql"
    candidates = sorted(
        output_dir.glob("difal_emitente_chunks_*.xlsx"),
        key=lambda item: item.stat().st_mtime,
        reverse=True,
    )
    if not candidates:
        raise FileNotFoundError(
            "Nenhum Excel de potencial DIFAL encontrado em outputs/difal_emitente_chunks/efd_saida_sql."
        )
    return candidates[0]


def _normalize_consolidated_for_ranking(consolidated: pd.DataFrame) -> pd.DataFrame:
    data = consolidated.copy()
    for column in ["QTD_DOC", "TOTAL_ITEM", "DIFAL_DEST"]:
        data[column] = pd.to_numeric(data[column], errors="coerce").fillna(0)
    data["CNPJ_CPF_EMITENTE"] = data["CNPJ_CPF_EMITENTE"].map(_clean_cnpj_value)
    return (
        data.groupby(["CNPJ_CPF_EMITENTE"], dropna=False, as_index=False)
        .agg(
            NOME_EMITENTE=("NOME_EMITENTE", "first"),
            UF_EMITENTE=("UF_EMITENTE", _join_unique_values),
            QTD_DOC=("QTD_DOC", "sum"),
            TOTAL_ITEM=("TOTAL_ITEM", "sum"),
            DIFAL_DEST=("DIFAL_DEST", "sum"),
        )
        .sort_values(["DIFAL_DEST", "TOTAL_ITEM"], ascending=[False, False])
        .reset_index(drop=True)[CONSOLIDATED_COLUMNS]
    )


def _clean_cnpj_list(values: Iterable[Any]) -> list[str]:
    cleaned: list[str] = []
    for value in values:
        cnpj = _clean_cnpj_value(value)
        if cnpj and cnpj not in cleaned:
            cleaned.append(cnpj)
    return cleaned


def _clean_cnpj_value(value: Any) -> str:
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return ""
    text = str(value).strip()
    if text.endswith(".0"):
        text = text[:-2]
    digits = re.sub(r"\D", "", text)
    return digits or text


def _join_unique_values(values: pd.Series) -> str:
    unique = sorted({str(value) for value in values.dropna() if str(value).strip()})
    return " | ".join(unique)


def _analysis_manifest_row(
    *,
    etapa: str,
    status: str,
    rows: int,
    error: str,
    started_at: str,
    finished_at: str,
    details: str,
) -> dict[str, Any]:
    return {
        "ETAPA": etapa,
        "STATUS": status,
        "LINHAS": rows,
        "ERRO": error,
        "INICIO_EXECUCAO": started_at,
        "FIM_EXECUCAO": finished_at,
        "DETALHES": details,
    }


def _build_blocked_recolhimento_frame() -> tuple[pd.DataFrame, dict[str, Any]]:
    rows = [
        {
            "STATUS": "bloqueado",
            "MOTIVO": (
                "Fonte GIA/Recolhimento ainda nao validada para valor pago por CNPJ e periodo. "
                "Nao concluir devedor sem esta etapa."
            ),
            "OBJETO_CANDIDATO": "Valor Total Recolhimento - GIA",
            "OBJECT_ID": "5C7B26FF419474239FB002B0270982DD",
            "TIPO": "metrica",
            "CAMINHO": "Objetos publicos / Metricas / Recolhimentos / Recolhimentos GIA",
        },
        {
            "STATUS": "bloqueado",
            "MOTIVO": "Candidato de filtro para periodo de pagamento.",
            "OBJETO_CANDIDATO": "AnoMes Pagamento - Recolhimento",
            "OBJECT_ID": "3B1AA64F4CE04B8E2F19018AB88D003B",
            "TIPO": "filtro",
            "CAMINHO": "Objetos publicos / Relatorios / FONTES / RAF Estado / Dashboard GIA e Recolhimento / Objetos",
        },
        {
            "STATUS": "bloqueado",
            "MOTIVO": "Candidato para chave de contribuinte em GIA/Recolhimento.",
            "OBJETO_CANDIDATO": "CNPJ Raiz (GIA / Recolhimento)",
            "OBJECT_ID": "6949CA7145FF082A3C91B898AEC238B9",
            "TIPO": "filtro",
            "CAMINHO": "Objetos publicos / Relatorios / FONTES / RAF Estado / Dashboard GIA e Recolhimento / Objetos",
        },
        {
            "STATUS": "bloqueado",
            "MOTIVO": "Candidato para limitar receitas/GR aplicaveis antes de confronto.",
            "OBJETO_CANDIDATO": "TODOS - Filtro Codigo da Receita",
            "OBJECT_ID": "DBB5EF4E11E83E6C45B30080EF7500B0",
            "TIPO": "filtro",
            "CAMINHO": "Objetos publicos / Relatorios / FONTES / RAF Estado / Dashboard GIA e Recolhimento / Objetos",
        },
    ]
    manifest = _analysis_manifest_row(
        etapa="recolhimento",
        status="bloqueado",
        rows=0,
        error="Fonte GIA/Recolhimento precisa ser validada antes do confronto financeiro.",
        started_at=_now(),
        finished_at=_now(),
        details="Objetos candidatos registrados na aba recolhimento.",
    )
    return pd.DataFrame(rows), manifest


def _build_blocked_confronto(
    ranking: pd.DataFrame,
    recolhimento: pd.DataFrame,
) -> pd.DataFrame:
    confronto = ranking.copy()
    confronto["DIFAL_ESTIMADO"] = pd.to_numeric(confronto["DIFAL_DEST"], errors="coerce").fillna(0)
    confronto["RECOLHIDO"] = pd.NA
    confronto["POTENCIAL_DEBITO"] = pd.NA
    confronto["STATUS_CONFRONTO"] = "bloqueado_sem_fonte_recolhimento_validada"
    confronto["OBSERVACAO"] = (
        "Nao concluir falta de pagamento: fonte GIA/Recolhimento ainda nao validada."
    )
    return confronto[
        [
            "CNPJ_CPF_EMITENTE",
            "NOME_EMITENTE",
            "UF_EMITENTE",
            "QTD_DOC",
            "TOTAL_ITEM",
            "DIFAL_ESTIMADO",
            "RECOLHIDO",
            "POTENCIAL_DEBITO",
            "STATUS_CONFRONTO",
            "OBSERVACAO",
        ]
    ]


def _build_blocked_possiveis_devedores() -> pd.DataFrame:
    return pd.DataFrame(
        [
            {
                "STATUS": "nao_concluido",
                "MOTIVO": (
                    "A lista de possiveis devedores depende do confronto com GIA/Recolhimento. "
                    "Esta implementacao nao classifica devedor sem valor recolhido validado."
                ),
            }
        ]
    )


def _resolve_output_path(
    output_dir: str | Path,
    output_path: str | Path | None,
    start: date,
    end: date,
) -> Path:
    if output_path is not None:
        return Path(output_path)
    filename = f"difal_emitente_chunks_{start.isoformat()}_{end.isoformat()}.xlsx"
    return Path(output_dir) / filename


def _resolve_analysis_output_path(
    output_dir: str | Path,
    output_path: str | Path | None,
    start: date,
    end: date,
) -> Path:
    if output_path is not None:
        return Path(output_path)
    filename = f"difal_top20_debt_analysis_{start.isoformat()}_{end.isoformat()}.xlsx"
    return Path(output_dir) / filename


def _write_sheet(writer: pd.ExcelWriter, df: pd.DataFrame, sheet_name: str) -> None:
    max_data_rows = EXCEL_MAX_ROWS - 1
    if len(df) <= max_data_rows:
        df.to_excel(writer, sheet_name=sheet_name[:31], index=False)
        return

    for index, start in enumerate(range(0, len(df), max_data_rows), start=1):
        chunk = df.iloc[start : start + max_data_rows]
        suffix = "" if index == 1 else f"_{index}"
        chunk.to_excel(writer, sheet_name=f"{sheet_name}{suffix}"[:31], index=False)


def _raise_for_status(response: Any, context: str) -> None:
    try:
        response.raise_for_status()
    except Exception as exc:
        body = getattr(response, "text", "")[:2000]
        status = getattr(response, "status_code", "?")
        raise RuntimeError(f"{context} falhou com HTTP {status}: {body}") from exc


def _now() -> str:
    return datetime.now().isoformat(timespec="seconds")


def _make_logger(
    verbose: bool,
    log: Callable[[str], None] | None,
) -> Callable[[str], None]:
    if log is not None:
        return log
    if not verbose:
        return lambda _message: None

    def _print(message: str) -> None:
        print(f"[{datetime.now().strftime('%H:%M:%S')}] {message}", flush=True)

    return _print
