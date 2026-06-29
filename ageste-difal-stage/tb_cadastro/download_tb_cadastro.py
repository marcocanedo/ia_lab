from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from difal_report_chunks import ExportResult  # noqa: E402
from freeform_snapshot_export import run_freeform_sql_snapshot_export, snapshot_attribute  # noqa: E402
from microstrategy_client import MicroStrategyRestClient  # noqa: E402


WORKSPACE_ROOT = Path(__file__).resolve().parent
SQL_PATH = WORKSPACE_ROOT / "sql" / "tb_cadastro.sql"
DEFAULT_OUTPUT_DIR = WORKSPACE_ROOT / "outputs"
DEFAULT_OUTPUT_FILENAME = "tb_cadastro.xlsx"
DEFAULT_REPORT_NAME = "tbCadastro"
DEFAULT_REPORT_NAME_PREFIX = "TMP tbCadastro"
DEFAULT_DESCRIPTION = "Snapshot Freeform SQL de DIM_PESSOA x DIM_DRR para cruzamento."
DEFAULT_TOP_N = 20
DEFAULT_PAGE_SIZE = 5000
DEFAULT_MAX_ATTEMPTS = 2
DEFAULT_SLEEP_BETWEEN_ATTEMPTS = 5

CANONICAL_COLUMNS = [
    "NU_CNPJ_CPF",
    "NU_IE_ST",
    "CD_PESSOA",
    "CD_DRR",
    "NU_CNPJ8",
    "NU_CNPJ",
    "NU_IE",
]

OUTPUT_COLUMNS = [
    *CANONICAL_COLUMNS,
    "CD_TIPO_PESSOA",
    "CD_SIST_ORIG",
    "CD_PARTICP",
    "CD_PESSOA_EMPR",
    "CD_PESSOA_ST",
    "NU_CPF",
    "IN_CNPJ_INSC_IE",
    "NM_PESSOA",
    "CD_CNAE_PRINCP",
    "CD_SRP",
    "CD_SRP_SIT_CAD",
    "CD_SRP_REGM_TRIB",
    "CD_SRP_CAT_REGM_TRIB",
    "CD_SRP_PRAZO_PAGTO",
    "CD_TSS",
    "CD_PESSOA_CONTAB",
    "CD_SIST_ORIG_CONTAB",
    "NU_FONE",
    "CD_TIPO_END",
    "DS_LOGR",
    "NU_LOGR",
    "DS_COMPL",
    "DS_BAIRRO",
    "NU_CEP",
    "NU_LAT",
    "NU_LONG",
    "CD_MUN_ANALIT",
    "CD_PESSOA_ARE",
    "CD_PESSOA_ARE_CENTR",
    "CD_PESSOA_DRR",
    "CD_UF",
    "CD_PESSOA_ORIG",
    "DS_TIPO_CLASSIF_PESSOA",
    "DT_REF_CAD",
    "DT_INI_ATIV",
    "DT_FIM_ATIV",
    "NM_FANTASIA",
    "DT_INI_EFD",
    "CD_SUB_SETOR_SIGEF",
]

SNAPSHOT_COLUMNS = [snapshot_attribute(column) for column in OUTPUT_COLUMNS]
DEDUPE_COLUMNS = ["NU_CNPJ_CPF", "NU_IE_ST"]
SORT_COLUMNS = ["NU_CNPJ_CPF", "NU_IE_ST", "CD_PESSOA"]
VALID_OK_STATUSES = {"ok", "sucesso", "success"}


@dataclass(frozen=True)
class SnapshotRunSummary:
    status: str
    report_name: str
    output_path: Path
    sql_path: Path
    canonical_columns: list[str]
    dedupe_columns: list[str]
    sort_columns: list[str]
    rows_chunks: int
    rows_consolidated: int
    rows_top_n: int
    manifest_errors: int


@dataclass(frozen=True)
class SnapshotRun:
    result: ExportResult
    summary: SnapshotRunSummary


def _load_sql_exact(path: Path = SQL_PATH) -> str:
    if not path.exists():
        raise FileNotFoundError(f"SQL base nao encontrada: {path}")
    return path.read_text(encoding="utf-8").strip()


def _output_path_from_args(output_dir: str | Path, output_path: str | Path | None) -> Path:
    if output_path is not None:
        return Path(output_path)
    return Path(output_dir) / DEFAULT_OUTPUT_FILENAME


def _manifest_error_count(manifest: Any) -> int:
    if getattr(manifest, "empty", True) or "STATUS" not in manifest.columns:
        return 0
    status = manifest["STATUS"].astype(str).str.lower()
    return int((~status.isin(VALID_OK_STATUSES)).sum())


def _build_summary(result: ExportResult) -> SnapshotRunSummary:
    manifest_errors = _manifest_error_count(result.manifest)
    status = "ok" if manifest_errors == 0 else "partial"
    if result.chunks.empty and manifest_errors > 0:
        status = "erro"

    return SnapshotRunSummary(
        status=status,
        report_name=DEFAULT_REPORT_NAME,
        output_path=result.output_path,
        sql_path=SQL_PATH,
        canonical_columns=CANONICAL_COLUMNS,
        dedupe_columns=DEDUPE_COLUMNS,
        sort_columns=SORT_COLUMNS,
        rows_chunks=len(result.chunks),
        rows_consolidated=len(result.consolidated),
        rows_top_n=len(result.top_n),
        manifest_errors=manifest_errors,
    )


def dry_run_plan(
    *,
    top_n: int | None = DEFAULT_TOP_N,
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
        "canonical_columns": CANONICAL_COLUMNS,
        "dedupe_columns": DEDUPE_COLUMNS,
        "sort_columns": SORT_COLUMNS,
        "output_columns": OUTPUT_COLUMNS,
        "page_size": page_size,
        "top_n": top_n,
        "sql_preview": "\n".join(sql.splitlines()[:18]),
        "notes": [
            "Snapshot unico, sem recorte temporal.",
            "A consolidacao deduplica por NU_CNPJ_CPF + NU_IE_ST para o cruzamento.",
            "O workbook final preserva as colunas brutas e destaca a visao canonica no inicio.",
        ],
    }


def run_tb_cadastro_export(
    *,
    top_n: int | None = DEFAULT_TOP_N,
    page_size: int = DEFAULT_PAGE_SIZE,
    output_dir: str | Path = DEFAULT_OUTPUT_DIR,
    output_path: str | Path | None = None,
    max_attempts: int = DEFAULT_MAX_ATTEMPTS,
    sleep_between_attempts: int = DEFAULT_SLEEP_BETWEEN_ATTEMPTS,
    verbose: bool = False,
    client: MicroStrategyRestClient | None = None,
) -> SnapshotRun:
    sql = _load_sql_exact()
    resolved_output_path = _output_path_from_args(output_dir, output_path)
    result = run_freeform_sql_snapshot_export(
        sql=sql,
        columns=SNAPSHOT_COLUMNS,
        output_dir=output_dir,
        output_path=resolved_output_path,
        top_n=top_n,
        page_size=page_size,
        max_attempts=max_attempts,
        sleep_between_attempts=sleep_between_attempts,
        verbose=verbose,
        client=client,
        fetch_all_pages=True,
        max_rows=None,
        report_name_prefix=DEFAULT_REPORT_NAME_PREFIX,
        description=DEFAULT_DESCRIPTION,
        dedupe_columns=DEDUPE_COLUMNS,
        sort_columns=SORT_COLUMNS,
        sort_ascending=True,
    )
    summary = _build_summary(result)
    return SnapshotRun(result=result, summary=summary)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Snapshot de DIM_PESSOA x DIM_DRR para cruzamento.")
    parser.add_argument("--top-n", type=int, default=DEFAULT_TOP_N, help="Quantidade de linhas no top_n.")
    parser.add_argument("--page-size", type=int, default=DEFAULT_PAGE_SIZE, help="Tamanho da pagina da API.")
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_DIR), help="Diretorio de saida do workbook.")
    parser.add_argument("--output-path", default=None, help="Arquivo final xlsx. Sobrescreve output-dir.")
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

    run = run_tb_cadastro_export(
        top_n=args.top_n,
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
