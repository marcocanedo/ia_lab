from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict, dataclass, replace
from pathlib import Path
from typing import Any

import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from difal_report_chunks import ExportResult, run_freeform_sql_export  # noqa: E402
from microstrategy_client import MicroStrategyRestClient  # noqa: E402


WORKSPACE_ROOT = Path(__file__).resolve().parent
SQL_PATH = WORKSPACE_ROOT / "sql" / "tb_gia.sql"
DEFAULT_OUTPUT_DIR = WORKSPACE_ROOT / "outputs"
DEFAULT_START_DATE = "2022-04-01"
DEFAULT_END_DATE = "2025-12-31"
DEFAULT_TOP_N = 20
DEFAULT_SAMPLE_ROWS = 1000
DEFAULT_PAGE_SIZE = 5000
DEFAULT_MAX_ATTEMPTS = 2
DEFAULT_SLEEP_BETWEEN_ATTEMPTS = 5
DEFAULT_REPORT_NAME = "tbGia - GIA-ST declarada"
DEFAULT_REPORT_NAME_PREFIX = "TMP tbGia"
DEFAULT_DESCRIPTION = "Relatorio Freeform SQL de GIA-ST declarada para extracao em chunks."

REPORT_COLUMNS = [
    "NU_CNPJ",
    "NU_IE",
    "NU_IE_ST",
    "CD_MUN_ANALIT",
    "NM_MUN_IBGE",
    "CD_UF",
    "CD_SIGLA_UF",
    "CD_PESSOA_ARE",
    "CD_PESSOA_ARE_CENTR",
    "CD_PESSOA_DRR",
    "CD_DRR",
    "DS_DRR",
    "Difal",
]

OUTPUT_COLUMNS = [
    "MES_REF",
    "CHUNK_INICIO",
    "CHUNK_FIM",
    *REPORT_COLUMNS,
]

ATTRIBUTE_COLUMNS = REPORT_COLUMNS[:-1]
METRIC_COLUMNS = ["Difal"]
CONSOLIDATE_SORT_COLUMNS = [
    "MES_REF",
    "CHUNK_INICIO",
    "CHUNK_FIM",
    "NU_CNPJ",
    "NU_IE",
    "NU_IE_ST",
    "CD_DRR",
    "CD_MUN_ANALIT",
    "CD_SIGLA_UF",
    "Difal",
]
CONSOLIDATE_SORT_ASCENDING = [True, True, True, True, True, True, True, True, True, False]
TOP_N_SORT_COLUMNS = [
    "Difal",
    "MES_REF",
    "CHUNK_INICIO",
    "CHUNK_FIM",
    "NU_CNPJ",
    "NU_IE",
    "NU_IE_ST",
    "CD_DRR",
    "CD_MUN_ANALIT",
    "CD_SIGLA_UF",
]
TOP_N_SORT_ASCENDING = [False, True, True, True, True, True, True, True, True, True]
VALID_OK_STATUSES = {"ok", "sucesso", "success"}


@dataclass(frozen=True)
class ExportRunSummary:
    status: str
    selected_chunk_days: int | None
    selected_label: str
    fallback_chain: list[str]
    attempts: list[dict[str, Any]]
    final_output_path: Path
    sql_path: Path
    rows_chunks: int
    rows_consolidated: int
    rows_top_n: int
    manifest_errors: int


@dataclass(frozen=True)
class ExportRun:
    result: ExportResult
    summary: ExportRunSummary


def _load_sql_exact(path: Path = SQL_PATH) -> str:
    if not path.exists():
        raise FileNotFoundError(f"SQL base nao encontrada: {path}")
    return path.read_text(encoding="utf-8").strip()


def _chunk_label(chunk_days: int | None) -> str:
    return "monthly" if chunk_days is None else f"{chunk_days}d"


def _candidate_chunk_days(requested_chunk_days: int | None) -> list[int | None]:
    if requested_chunk_days is None:
        return [None, 15, 7]

    candidates: list[int | None] = [requested_chunk_days]
    for fallback in (15, 7):
        if fallback < requested_chunk_days and fallback not in candidates:
            candidates.append(fallback)
    return candidates


def _build_output_path(output_dir: str | Path, start_date: str, end_date: str) -> Path:
    return Path(output_dir) / f"tb_gia_{start_date}_a_{end_date}.parquet"


def _make_temp_output_path(final_output_path: Path, chunk_days: int | None) -> Path:
    return final_output_path.with_name(f"{final_output_path.stem}__{_chunk_label(chunk_days)}{final_output_path.suffix}")


def _build_summary_workbook_path(output_path: Path) -> Path:
    return output_path.with_name(f"{output_path.stem}_resumo.xlsx")


def _manifest_error_count(manifest: pd.DataFrame) -> int:
    if manifest.empty or "STATUS" not in manifest.columns:
        return 0
    status = manifest["STATUS"].astype(str).str.lower()
    return int((~status.isin(VALID_OK_STATUSES)).sum())


def _sort_frame(frame: pd.DataFrame, *, sort_columns: list[str], ascending: list[bool]) -> pd.DataFrame:
    if frame.empty:
        return frame.copy()

    data = frame.copy()
    if "Difal" in data.columns:
        data["Difal"] = pd.to_numeric(data["Difal"], errors="coerce").fillna(0)
    return data.sort_values(sort_columns, ascending=ascending, na_position="last").reset_index(drop=True)


def _consolidate_chunks(chunks: pd.DataFrame) -> pd.DataFrame:
    return _sort_frame(chunks, sort_columns=CONSOLIDATE_SORT_COLUMNS, ascending=CONSOLIDATE_SORT_ASCENDING)


def _build_top_n(consolidated: pd.DataFrame, top_n: int | None) -> pd.DataFrame:
    if top_n is None or top_n <= 0:
        return consolidated.head(0).copy()
    if consolidated.empty:
        return consolidated.head(0).copy()
    return _sort_frame(consolidated, sort_columns=TOP_N_SORT_COLUMNS, ascending=TOP_N_SORT_ASCENDING).head(top_n).copy()


def _dry_run_notes() -> list[str]:
    return [
        "O SQL base fica no arquivo SQL e o script troca apenas o periodo mensal da GIA-ST.",
        "A execucao tenta mensal, depois 15 dias, depois 7 dias.",
        "O arquivo principal e Parquet; o Excel gerado e apenas um resumo de inspecao.",
    ]


def dry_run_plan(
    *,
    start_date: str = DEFAULT_START_DATE,
    end_date: str = DEFAULT_END_DATE,
    chunk_days: int | None = None,
    page_size: int = DEFAULT_PAGE_SIZE,
    top_n: int | None = DEFAULT_TOP_N,
    output_dir: str | Path = DEFAULT_OUTPUT_DIR,
) -> dict[str, Any]:
    sql_exact = _load_sql_exact()
    return {
        "workspace_root": str(WORKSPACE_ROOT),
        "sql_path": str(SQL_PATH),
        "report_name": DEFAULT_REPORT_NAME,
        "start_date": start_date,
        "end_date": end_date,
        "output_path": str(_build_output_path(output_dir, start_date, end_date)),
        "chunk_candidates": [_chunk_label(item) for item in _candidate_chunk_days(chunk_days)],
        "page_size": page_size,
        "top_n": top_n,
        "sql_preview": "\n".join(sql_exact.splitlines()[:14]),
        "notes": _dry_run_notes(),
    }


def _write_parquet_output(output_path: Path, frame: pd.DataFrame) -> Path:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    writing_path = output_path.with_name(f"{output_path.stem}__writing{output_path.suffix}")
    writing_path.unlink(missing_ok=True)
    frame.to_parquet(writing_path, index=False, engine="pyarrow", compression="snappy")
    writing_path.replace(output_path)
    return output_path


def _write_summary_workbook(
    *,
    output_path: Path,
    chunks: pd.DataFrame,
    consolidated: pd.DataFrame,
    top_frame: pd.DataFrame,
    manifest: pd.DataFrame,
    sample_rows: int,
) -> Path:
    summary_path = _build_summary_workbook_path(output_path)
    sample = chunks.head(max(0, sample_rows)).copy()
    summary = pd.DataFrame(
        [
            {"item": "arquivo_dados", "valor": str(output_path)},
            {"item": "linhas_chunks", "valor": len(chunks)},
            {"item": "linhas_consolidado", "valor": len(consolidated)},
            {"item": "linhas_top_n", "valor": len(top_frame)},
            {"item": "linhas_amostra", "valor": len(sample)},
        ]
    )

    writing_path = summary_path.with_name(f"{summary_path.stem}__writing{summary_path.suffix}")
    writing_path.unlink(missing_ok=True)
    with pd.ExcelWriter(writing_path, engine="openpyxl") as writer:
        summary.to_excel(writer, sheet_name="resumo", index=False)
        sample.to_excel(writer, sheet_name="amostra_chunks", index=False)
        top_frame.to_excel(writer, sheet_name="top_n", index=False)
        manifest.to_excel(writer, sheet_name="manifest", index=False)
    writing_path.replace(summary_path)
    return summary_path


def _cleanup_temp_outputs(paths: list[Path]) -> None:
    for path in paths:
        path.unlink(missing_ok=True)


def run_tb_gia_export(
    *,
    start_date: str = DEFAULT_START_DATE,
    end_date: str = DEFAULT_END_DATE,
    chunk_days: int | None = None,
    page_size: int = DEFAULT_PAGE_SIZE,
    top_n: int | None = DEFAULT_TOP_N,
    sample_rows: int = DEFAULT_SAMPLE_ROWS,
    output_dir: str | Path = DEFAULT_OUTPUT_DIR,
    max_attempts: int = DEFAULT_MAX_ATTEMPTS,
    sleep_between_attempts: int = DEFAULT_SLEEP_BETWEEN_ATTEMPTS,
    verbose: bool = False,
    client: MicroStrategyRestClient | None = None,
) -> ExportRun:
    sql_exact = _load_sql_exact()
    final_output_path = _build_output_path(output_dir, start_date, end_date)
    logger = print if verbose else None

    own_client = client is None
    client = client or MicroStrategyRestClient()
    if own_client:
        client.login()

    attempts: list[dict[str, Any]] = []
    staged_runs: list[dict[str, Any]] = []
    temp_paths: list[Path] = []

    try:
        for candidate in _candidate_chunk_days(chunk_days):
            candidate_label = _chunk_label(candidate)
            temp_output_path = _make_temp_output_path(final_output_path, candidate)
            temp_paths.append(temp_output_path)
            if logger:
                logger(f"[tbGia] tentando {candidate_label} em {temp_output_path.name}")

            try:
                staged_result = run_freeform_sql_export(
                    sql_template=sql_exact,
                    output_columns=OUTPUT_COLUMNS,
                    attribute_columns=ATTRIBUTE_COLUMNS,
                    metric_columns=METRIC_COLUMNS,
                    start_date=start_date,
                    end_date=end_date,
                    output_dir=output_dir,
                    output_path=temp_output_path,
                    top_n=0,
                    chunk_days=candidate,
                    page_size=page_size,
                    max_attempts=max_attempts,
                    sleep_between_attempts=sleep_between_attempts,
                    sleep_between_chunks=0,
                    continue_on_error=True,
                    verbose=verbose,
                    log=logger,
                    client=client,
                    fetch_all_pages=True,
                    max_rows=None,
                    report_name_prefix=DEFAULT_REPORT_NAME_PREFIX,
                    description=DEFAULT_DESCRIPTION,
                    write_workbook=False,
                )
            except Exception as exc:
                attempts.append(
                    {
                        "chunk_days": candidate,
                        "label": candidate_label,
                        "status": "exception",
                        "error_count": 10**9,
                        "rows_chunks": 0,
                        "rows_consolidated": 0,
                        "output_path": str(temp_output_path),
                        "error": str(exc),
                    }
                )
                temp_output_path.unlink(missing_ok=True)
                continue

            consolidated = _consolidate_chunks(staged_result.chunks)
            top_frame = _build_top_n(consolidated, top_n)
            error_count = _manifest_error_count(staged_result.manifest)
            rows_chunks = len(staged_result.chunks)
            rows_consolidated = len(consolidated)
            staged_runs.append(
                {
                    "chunk_days": candidate,
                    "label": candidate_label,
                    "result": staged_result,
                    "temp_output_path": temp_output_path,
                }
            )
            attempts.append(
                {
                    "chunk_days": candidate,
                    "label": candidate_label,
                    "status": "ok" if error_count == 0 else "partial",
                    "error_count": error_count,
                    "rows_chunks": rows_chunks,
                    "rows_consolidated": rows_consolidated,
                    "output_path": str(temp_output_path),
                    "error": "",
                }
            )

            if error_count == 0:
                _write_parquet_output(temp_output_path, staged_result.chunks)
                temp_output_path.replace(final_output_path)
                _write_summary_workbook(
                    output_path=final_output_path,
                    chunks=staged_result.chunks,
                    consolidated=consolidated,
                    top_frame=top_frame,
                    manifest=staged_result.manifest,
                    sample_rows=sample_rows,
                )
                temp_paths.remove(temp_output_path)
                _cleanup_temp_outputs(temp_paths)
                final_result = replace(
                    staged_result,
                    output_path=final_output_path,
                    consolidated=consolidated,
                    top_n=top_frame,
                )
                summary = ExportRunSummary(
                    status="ok",
                    selected_chunk_days=candidate,
                    selected_label=candidate_label,
                    fallback_chain=[attempt["label"] for attempt in attempts],
                    attempts=attempts,
                    final_output_path=final_output_path,
                    sql_path=SQL_PATH,
                    rows_chunks=rows_chunks,
                    rows_consolidated=rows_consolidated,
                    rows_top_n=len(top_frame),
                    manifest_errors=error_count,
                )
                return ExportRun(result=final_result, summary=summary)

        valid_attempts = [item for item in attempts if item["status"] != "exception"]
        if not valid_attempts:
            raise RuntimeError("Nenhuma tentativa de exportacao conseguiu retornar dados.")

        best_attempt = min(valid_attempts, key=lambda item: (item["error_count"], -item["rows_chunks"], -item["rows_consolidated"]))
        selected_candidate = best_attempt["chunk_days"]
        selected_label = str(best_attempt["label"])
        selected_run = next((item for item in staged_runs if item["chunk_days"] == selected_candidate), None)
        if selected_run is None:
            raise RuntimeError("A melhor tentativa foi selecionada, mas o resultado estagiado nao foi localizado.")

        staged_result = selected_run["result"]
        consolidated = _consolidate_chunks(staged_result.chunks)
        top_frame = _build_top_n(consolidated, top_n)
        _write_parquet_output(final_output_path, staged_result.chunks)
        _write_summary_workbook(
            output_path=final_output_path,
            chunks=staged_result.chunks,
            consolidated=consolidated,
            top_frame=top_frame,
            manifest=staged_result.manifest,
            sample_rows=sample_rows,
        )
        _cleanup_temp_outputs(temp_paths)
        final_result = replace(
            staged_result,
            output_path=final_output_path,
            consolidated=consolidated,
            top_n=top_frame,
        )
        summary = ExportRunSummary(
            status="partial",
            selected_chunk_days=selected_candidate,
            selected_label=selected_label,
            fallback_chain=[attempt["label"] for attempt in attempts],
            attempts=attempts,
            final_output_path=final_output_path,
            sql_path=SQL_PATH,
            rows_chunks=len(staged_result.chunks),
            rows_consolidated=len(consolidated),
            rows_top_n=len(top_frame),
            manifest_errors=_manifest_error_count(staged_result.manifest),
        )
        return ExportRun(result=final_result, summary=summary)
    finally:
        if own_client:
            client.logout()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Download do relatorio tbGia em chunks mensais.")
    parser.add_argument("--start-date", default=DEFAULT_START_DATE, help="Data inicial no formato YYYY-MM-DD.")
    parser.add_argument("--end-date", default=DEFAULT_END_DATE, help="Data final no formato YYYY-MM-DD.")
    parser.add_argument("--chunk-days", type=int, default=None, help="Tamanho do chunk em dias. O padrao tenta mensal.")
    parser.add_argument("--page-size", type=int, default=DEFAULT_PAGE_SIZE, help="Tamanho da pagina da API.")
    parser.add_argument("--top-n", type=int, default=DEFAULT_TOP_N, help="Quantidade de linhas no top_n.")
    parser.add_argument("--sample-rows", type=int, default=DEFAULT_SAMPLE_ROWS, help="Linhas de amostra no Excel de resumo.")
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_DIR), help="Diretorio de saida do workbook.")
    parser.add_argument("--max-attempts", type=int, default=DEFAULT_MAX_ATTEMPTS, help="Numero maximo de tentativas por chunk.")
    parser.add_argument(
        "--sleep-between-attempts",
        type=int,
        default=DEFAULT_SLEEP_BETWEEN_ATTEMPTS,
        help="Pausa em segundos entre tentativas de um mesmo chunk.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Mostra o plano sem conectar ao MicroStrategy.")
    parser.add_argument("--quiet", action="store_true", help="Reduz o output de progresso.")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.dry_run:
        print(
            json.dumps(
                dry_run_plan(
                    start_date=args.start_date,
                    end_date=args.end_date,
                    chunk_days=args.chunk_days,
                    page_size=args.page_size,
                    top_n=args.top_n,
                    output_dir=args.output_dir,
                ),
                ensure_ascii=False,
                indent=2,
                default=str,
            )
        )
        return 0

    run = run_tb_gia_export(
        start_date=args.start_date,
        end_date=args.end_date,
        chunk_days=args.chunk_days,
        page_size=args.page_size,
        top_n=args.top_n,
        sample_rows=args.sample_rows,
        output_dir=args.output_dir,
        max_attempts=args.max_attempts,
        sleep_between_attempts=args.sleep_between_attempts,
        verbose=not args.quiet,
    )
    print(json.dumps(asdict(run.summary), ensure_ascii=False, indent=2, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
