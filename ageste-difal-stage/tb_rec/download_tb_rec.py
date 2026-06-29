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

from difal_report_chunks import ExportResult  # noqa: E402
from freeform_snapshot_export import run_freeform_sql_snapshot_export, snapshot_attribute, snapshot_metric  # noqa: E402
from microstrategy_client import MicroStrategyRestClient  # noqa: E402


WORKSPACE_ROOT = Path(__file__).resolve().parent
SQL_PATH = WORKSPACE_ROOT / "sql" / "tb_rec.sql"
DEFAULT_OUTPUT_DIR = WORKSPACE_ROOT / "outputs"
DEFAULT_OUTPUT_FILENAME = "tb_rec.parquet"
DEFAULT_REPORT_NAME = "tbRec"
DEFAULT_REPORT_NAME_PREFIX = "TMP tbRec"
DEFAULT_DESCRIPTION = "Snapshot Freeform SQL de recolhimentos para cruzamento."
DEFAULT_TOP_N = 20
DEFAULT_SAMPLE_ROWS = 1000
DEFAULT_PAGE_SIZE = 5000
DEFAULT_MAX_ATTEMPTS = 2
DEFAULT_SLEEP_BETWEEN_ATTEMPTS = 5

OUTPUT_COLUMNS = ["CD_INSCRICAO_CNPJ_CPF", "TotalRec"]
SNAPSHOT_COLUMNS = [snapshot_attribute("CD_INSCRICAO_CNPJ_CPF"), snapshot_metric("TotalRec")]
SORT_COLUMNS = ["TotalRec", "CD_INSCRICAO_CNPJ_CPF"]
SORT_ASCENDING = [False, True]
VALID_OK_STATUSES = {"ok", "sucesso", "success"}


@dataclass(frozen=True)
class RecRunSummary:
    status: str
    report_name: str
    output_path: Path
    summary_workbook_path: Path
    sql_path: Path
    sort_columns: list[str]
    rows_chunks: int
    rows_consolidated: int
    rows_top_n: int
    manifest_errors: int


@dataclass(frozen=True)
class RecRun:
    result: ExportResult
    summary: RecRunSummary


def _load_sql_exact(path: Path = SQL_PATH) -> str:
    if not path.exists():
        raise FileNotFoundError(f"SQL base nao encontrada: {path}")
    return path.read_text(encoding="utf-8").strip()


def _output_path_from_args(output_dir: str | Path, output_path: str | Path | None) -> Path:
    if output_path is not None:
        return Path(output_path)
    return Path(output_dir) / DEFAULT_OUTPUT_FILENAME


def _summary_workbook_path(output_path: Path) -> Path:
    return output_path.with_name(f"{output_path.stem}_resumo.xlsx")


def _manifest_error_count(manifest: pd.DataFrame) -> int:
    if manifest.empty or "STATUS" not in manifest.columns:
        return 0
    status = manifest["STATUS"].astype(str).str.lower()
    return int((~status.isin(VALID_OK_STATUSES)).sum())


def _sort_rec(frame: pd.DataFrame) -> pd.DataFrame:
    if frame.empty:
        return frame.copy()
    data = frame.copy()
    data["TotalRec"] = pd.to_numeric(data["TotalRec"], errors="coerce").fillna(0)
    return data.sort_values(SORT_COLUMNS, ascending=SORT_ASCENDING, na_position="last").reset_index(drop=True)


def _build_top_n(consolidated: pd.DataFrame, top_n: int | None) -> pd.DataFrame:
    if top_n is None or top_n <= 0:
        return consolidated.head(0).copy()
    return consolidated.head(top_n).copy()


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
    summary_path = _summary_workbook_path(output_path)
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


def dry_run_plan(
    *,
    top_n: int | None = DEFAULT_TOP_N,
    sample_rows: int = DEFAULT_SAMPLE_ROWS,
    page_size: int = DEFAULT_PAGE_SIZE,
    output_dir: str | Path = DEFAULT_OUTPUT_DIR,
    output_path: str | Path | None = None,
) -> dict[str, Any]:
    sql = _load_sql_exact()
    resolved_output_path = _output_path_from_args(output_dir, output_path)
    return {
        "workspace_root": str(WORKSPACE_ROOT),
        "sql_path": str(SQL_PATH),
        "report_name": DEFAULT_REPORT_NAME,
        "output_path": str(resolved_output_path),
        "summary_workbook_path": str(_summary_workbook_path(resolved_output_path)),
        "output_columns": OUTPUT_COLUMNS,
        "sort_columns": SORT_COLUMNS,
        "page_size": page_size,
        "top_n": top_n,
        "sample_rows": sample_rows,
        "sql_preview": "\n".join(sql.splitlines()[:12]),
        "notes": [
            "Snapshot unico, sem chunk temporal.",
            "O arquivo principal e Parquet; o Excel gerado e apenas resumo de inspecao.",
            "A chave CD_INSCRICAO_CNPJ_CPF fica bruta e sera normalizada no staging como inscricao_norm.",
        ],
    }


def run_tb_rec_export(
    *,
    top_n: int | None = DEFAULT_TOP_N,
    sample_rows: int = DEFAULT_SAMPLE_ROWS,
    page_size: int = DEFAULT_PAGE_SIZE,
    output_dir: str | Path = DEFAULT_OUTPUT_DIR,
    output_path: str | Path | None = None,
    max_attempts: int = DEFAULT_MAX_ATTEMPTS,
    sleep_between_attempts: int = DEFAULT_SLEEP_BETWEEN_ATTEMPTS,
    verbose: bool = False,
    client: MicroStrategyRestClient | None = None,
) -> RecRun:
    sql = _load_sql_exact()
    resolved_output_path = _output_path_from_args(output_dir, output_path)
    result = run_freeform_sql_snapshot_export(
        sql=sql,
        columns=SNAPSHOT_COLUMNS,
        output_dir=output_dir,
        output_path=resolved_output_path,
        top_n=0,
        page_size=page_size,
        max_attempts=max_attempts,
        sleep_between_attempts=sleep_between_attempts,
        verbose=verbose,
        client=client,
        fetch_all_pages=True,
        max_rows=None,
        report_name_prefix=DEFAULT_REPORT_NAME_PREFIX,
        description=DEFAULT_DESCRIPTION,
        sort_columns=SORT_COLUMNS,
        sort_ascending=SORT_ASCENDING,
        write_workbook=False,
    )
    consolidated = _sort_rec(result.chunks)
    top_frame = _build_top_n(consolidated, top_n)
    _write_parquet_output(resolved_output_path, result.chunks)
    summary_path = _write_summary_workbook(
        output_path=resolved_output_path,
        chunks=result.chunks,
        consolidated=consolidated,
        top_frame=top_frame,
        manifest=result.manifest,
        sample_rows=sample_rows,
    )
    final_result = replace(result, output_path=resolved_output_path, consolidated=consolidated, top_n=top_frame)
    manifest_errors = _manifest_error_count(result.manifest)
    summary = RecRunSummary(
        status="ok" if manifest_errors == 0 else "partial",
        report_name=DEFAULT_REPORT_NAME,
        output_path=resolved_output_path,
        summary_workbook_path=summary_path,
        sql_path=SQL_PATH,
        sort_columns=SORT_COLUMNS,
        rows_chunks=len(result.chunks),
        rows_consolidated=len(consolidated),
        rows_top_n=len(top_frame),
        manifest_errors=manifest_errors,
    )
    return RecRun(result=final_result, summary=summary)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Snapshot de recolhimentos para cruzamento da malha.")
    parser.add_argument("--top-n", type=int, default=DEFAULT_TOP_N, help="Quantidade de linhas no top_n.")
    parser.add_argument("--sample-rows", type=int, default=DEFAULT_SAMPLE_ROWS, help="Linhas de amostra no Excel de resumo.")
    parser.add_argument("--page-size", type=int, default=DEFAULT_PAGE_SIZE, help="Tamanho da pagina da API.")
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_DIR), help="Diretorio de saida.")
    parser.add_argument("--output-path", default=None, help="Arquivo final parquet. Sobrescreve output-dir.")
    parser.add_argument("--max-attempts", type=int, default=DEFAULT_MAX_ATTEMPTS, help="Numero maximo de tentativas.")
    parser.add_argument(
        "--sleep-between-attempts",
        type=int,
        default=DEFAULT_SLEEP_BETWEEN_ATTEMPTS,
        help="Pausa em segundos entre tentativas.",
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
                    top_n=args.top_n,
                    sample_rows=args.sample_rows,
                    page_size=args.page_size,
                    output_dir=args.output_dir,
                    output_path=args.output_path,
                ),
                ensure_ascii=False,
                indent=2,
                default=str,
            )
        )
        return 0

    run = run_tb_rec_export(
        top_n=args.top_n,
        sample_rows=args.sample_rows,
        page_size=args.page_size,
        output_dir=args.output_dir,
        output_path=args.output_path,
        max_attempts=args.max_attempts,
        sleep_between_attempts=args.sleep_between_attempts,
        verbose=not args.quiet,
    )
    print(json.dumps(asdict(run.summary), ensure_ascii=False, indent=2, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
