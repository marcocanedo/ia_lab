from __future__ import annotations

import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

import pandas as pd

from difal_report_chunks import (  # noqa: E402
    FOLDER_ID,
    ExportResult,
    _create_persisted_report_instance,
    _delete_model_instance,
    _delete_report_object,
    _execute_model_instance,
    _fetch_all_generic_rows,
    _fetch_limited_generic_rows,
    _freeform_sql_report_body,
    _make_logger,
    _now,
    _raise_for_status,
    write_excel_output,
)
from microstrategy_client import MicroStrategyRestClient  # noqa: E402


DEFAULT_OUTPUT_FILENAME = "freeform_snapshot.xlsx"
DEFAULT_REPORT_NAME_PREFIX = "TMP Freeform Snapshot"
DEFAULT_DESCRIPTION = "Relatorio Freeform SQL de snapshot."
VALID_OK_STATUSES = {"ok", "sucesso", "success"}

SNAPSHOT_MANIFEST_COLUMNS = [
    "REPORT_NAME",
    "OUTPUT_PATH",
    "STATUS",
    "TENTATIVA",
    "LINHAS",
    "TOTAL_API",
    "REPORT_ID",
    "INSTANCE_ID",
    "ERRO",
    "INICIO_EXECUCAO",
    "FIM_EXECUCAO",
]


@dataclass(frozen=True)
class SnapshotColumnSpec:
    name: str
    kind: str = "attribute"


def snapshot_attribute(name: str) -> SnapshotColumnSpec:
    return SnapshotColumnSpec(name=name, kind="attribute")


def snapshot_metric(name: str) -> SnapshotColumnSpec:
    return SnapshotColumnSpec(name=name, kind="metric")


def _split_snapshot_columns(
    columns: list[SnapshotColumnSpec],
) -> tuple[list[str], list[str], list[str]]:
    output_columns: list[str] = []
    attribute_columns: list[str] = []
    metric_columns: list[str] = []
    seen: set[str] = set()

    for column in columns:
        name = str(column.name or "").strip()
        kind = str(column.kind or "attribute").strip().lower()
        if not name:
            raise ValueError("SnapshotColumnSpec.name nao pode ser vazio.")
        if name in seen:
            raise ValueError(f"Coluna duplicada no snapshot: {name}")

        seen.add(name)
        output_columns.append(name)

        if kind == "attribute":
            attribute_columns.append(name)
        elif kind == "metric":
            metric_columns.append(name)
        else:
            raise ValueError(f"SnapshotColumnSpec.kind invalido para {name}: {kind}")

    if not output_columns:
        raise ValueError("Snapshot sem colunas nao e valido.")
    if not attribute_columns and not metric_columns:
        raise ValueError("Snapshot precisa de ao menos uma coluna de atributo ou metrica.")

    return output_columns, attribute_columns, metric_columns


def _normalize_sort_ascending(
    sort_columns: list[str] | None,
    sort_ascending: bool | list[bool],
) -> bool | list[bool]:
    if sort_columns is None:
        return sort_ascending
    if isinstance(sort_ascending, list):
        if len(sort_ascending) != len(sort_columns):
            raise ValueError("sort_ascending precisa ter o mesmo tamanho de sort_columns.")
        return sort_ascending
    return [sort_ascending] * len(sort_columns)


def consolidate_snapshot_rows(
    chunks: pd.DataFrame,
    *,
    dedupe_columns: list[str] | None = None,
    sort_columns: list[str] | None = None,
    sort_ascending: bool | list[bool] = True,
) -> pd.DataFrame:
    if chunks.empty:
        return chunks.copy()

    data = chunks.copy()
    effective_sort_columns = list(sort_columns or [])
    if not effective_sort_columns and dedupe_columns:
        effective_sort_columns = list(dedupe_columns)

    if effective_sort_columns:
        ascending = _normalize_sort_ascending(effective_sort_columns, sort_ascending)
        data = data.sort_values(effective_sort_columns, ascending=ascending, na_position="last")

    if dedupe_columns:
        data = data.drop_duplicates(subset=dedupe_columns, keep="first")

    return data.reset_index(drop=True)


def build_snapshot_top_n(consolidated: pd.DataFrame, top_n: int | None) -> pd.DataFrame:
    if top_n is None or top_n <= 0:
        return consolidated.head(0).copy()
    if consolidated.empty:
        return consolidated.head(0).copy()
    return consolidated.head(top_n).copy()


def _resolve_output_path(
    output_dir: str | Path,
    output_path: str | Path | None,
    *,
    default_filename: str = DEFAULT_OUTPUT_FILENAME,
) -> Path:
    if output_path is not None:
        return Path(output_path)
    return Path(output_dir) / default_filename


def _create_snapshot_report(
    *,
    client: MicroStrategyRestClient,
    report_name: str,
    sql: str,
    output_columns: list[str],
    attribute_columns: list[str],
    metric_columns: list[str],
    description: str,
    logger: Callable[[str], None],
) -> str:
    body = _freeform_sql_report_body(
        name=report_name,
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
    _raise_for_status(response, "Criacao do relatorio Freeform SQL de snapshot")

    report_id = response.json().get("information", {}).get("objectId")
    creation_instance_id = response.headers.get("X-MSTR-MS-Instance")
    if not report_id or not creation_instance_id:
        raise RuntimeError("Criacao do snapshot Freeform SQL nao retornou report_id ou instance_id.")

    try:
        save_response = client.request(
            "POST",
            f"/model/reports/{report_id}/instances/saveAs",
            headers={"Content-Type": "application/json", "X-MSTR-MS-Instance": creation_instance_id},
            json={"name": report_name, "destinationFolderId": FOLDER_ID},
            timeout=120,
        )
        _raise_for_status(save_response, "SaveAs do snapshot Freeform SQL")
    except Exception:
        logger(f"Falha ao salvar relatorio temporario {report_id}; apagando objeto.")
        _delete_report_object(client, report_id)
        raise

    return report_id


def _execute_snapshot_once(
    *,
    client: MicroStrategyRestClient,
    sql: str,
    columns: list[SnapshotColumnSpec],
    page_size: int,
    fetch_all_pages: bool,
    max_rows: int | None,
    report_name_prefix: str,
    description: str,
    logger: Callable[[str], None],
) -> tuple[pd.DataFrame, str, str, int, str]:
    output_columns, attribute_columns, metric_columns = _split_snapshot_columns(columns)
    report_id = ""
    instance_id = ""
    report_name = f"{report_name_prefix} {time.time_ns()}"

    try:
        logger(f"Criando relatorio Freeform SQL temporario de snapshot: {report_name}.")
        report_id = _create_snapshot_report(
            client=client,
            report_name=report_name,
            sql=sql,
            output_columns=output_columns,
            attribute_columns=attribute_columns,
            metric_columns=metric_columns,
            description=description,
            logger=logger,
        )
        logger(f"Relatorio temporario criado: {report_id}.")

        logger("Criando instancia de execucao do snapshot.")
        instance_id = _create_persisted_report_instance(client, report_id)
        logger(f"Instancia de execucao criada: {instance_id}.")

        _execute_model_instance(client, report_id, instance_id)
        if fetch_all_pages:
            logger(f"Buscando todas as paginas em blocos de {page_size} linha(s).")
            rows, total_api = _fetch_all_generic_rows(client, report_id, instance_id, page_size, logger)
        else:
            limit = min(page_size, max_rows or page_size)
            logger(f"Buscando amostra limitada a {limit} linha(s), sem pagina completa.")
            rows, total_api = _fetch_limited_generic_rows(
                client,
                report_id,
                instance_id,
                limit,
                logger=logger,
                max_rows=max_rows,
            )

        frame = pd.DataFrame(rows, columns=output_columns)
        if not frame.empty:
            frame = frame[output_columns]
        return frame, report_id, instance_id, total_api, report_name
    finally:
        if instance_id:
            logger(f"Removendo instancia de execucao {instance_id}.")
            _delete_model_instance(client, report_id, instance_id)
        if report_id:
            logger(f"Apagando relatorio temporario {report_id}.")
            _delete_report_object(client, report_id)


def run_freeform_sql_snapshot_export(
    *,
    sql: str,
    columns: list[SnapshotColumnSpec],
    output_dir: str | Path = "outputs/freeform_sql_snapshot",
    output_path: str | Path | None = None,
    top_n: int | None = 20,
    page_size: int = 5000,
    max_attempts: int = 2,
    sleep_between_attempts: int = 5,
    verbose: bool = False,
    log: Callable[[str], None] | None = None,
    client: MicroStrategyRestClient | None = None,
    fetch_all_pages: bool = True,
    max_rows: int | None = None,
    report_name_prefix: str = DEFAULT_REPORT_NAME_PREFIX,
    description: str = DEFAULT_DESCRIPTION,
    dedupe_columns: list[str] | None = None,
    sort_columns: list[str] | None = None,
    sort_ascending: bool | list[bool] = True,
    write_workbook: bool = True,
) -> ExportResult:
    output_columns, _, _ = _split_snapshot_columns(columns)
    own_client = client is None
    client = client or MicroStrategyRestClient()
    logger = _make_logger(verbose, log)
    attempts = max(1, max_attempts)
    last_error = ""

    if own_client:
        logger("Autenticando no MicroStrategy REST.")
        client.login()

    try:
        for attempt in range(1, attempts + 1):
            started_at = _now()
            try:
                logger(f"Execucao do snapshot {attempt}/{attempts}.")
                frame, report_id, instance_id, total_api, report_name = _execute_snapshot_once(
                    client=client,
                    sql=sql,
                    columns=columns,
                    page_size=page_size,
                    fetch_all_pages=fetch_all_pages,
                    max_rows=max_rows,
                    report_name_prefix=report_name_prefix,
                    description=description,
                    logger=logger,
                )
                consolidated = consolidate_snapshot_rows(
                    frame,
                    dedupe_columns=dedupe_columns,
                    sort_columns=sort_columns,
                    sort_ascending=sort_ascending,
                )
                top_frame = build_snapshot_top_n(consolidated, top_n)
                final_output_path = _resolve_output_path(
                    output_dir,
                    output_path,
                )
                final_output_path.parent.mkdir(parents=True, exist_ok=True)
                manifest = pd.DataFrame(
                    [
                        {
                            "REPORT_NAME": report_name,
                            "OUTPUT_PATH": str(final_output_path),
                            "STATUS": "ok",
                            "TENTATIVA": attempt,
                            "LINHAS": len(frame),
                            "TOTAL_API": total_api,
                            "REPORT_ID": report_id,
                            "INSTANCE_ID": instance_id,
                            "ERRO": "",
                            "INICIO_EXECUCAO": started_at,
                            "FIM_EXECUCAO": _now(),
                        }
                    ],
                    columns=SNAPSHOT_MANIFEST_COLUMNS,
                )
                if write_workbook:
                    write_excel_output(final_output_path, frame, consolidated, top_frame, manifest)
                return ExportResult(
                    output_path=final_output_path,
                    chunks=frame,
                    consolidated=consolidated,
                    top_n=top_frame,
                    manifest=manifest,
                )
            except Exception as exc:
                last_error = str(exc)
                logger(f"Erro na execucao do snapshot {attempt}/{attempts}: {last_error}")
                if attempt < attempts:
                    logger(f"Aguardando {sleep_between_attempts}s antes de tentar novamente.")
                    time.sleep(sleep_between_attempts)

        raise RuntimeError(f"Nao foi possivel concluir o snapshot Freeform SQL: {last_error}")
    finally:
        if own_client:
            logger("Encerrando sessao REST.")
            client.logout()
