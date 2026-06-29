from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any, Callable

import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from difal_report_chunks import run_top20_debt_analysis  # noqa: E402


WORKSPACE_ROOT = Path(__file__).resolve().parent
DEFAULT_POTENTIAL_PATH = WORKSPACE_ROOT / "outputs" / "tb_nfe_2022-04-05_a_2025-12-31.xlsx"
DEFAULT_OUTPUT_DIR = WORKSPACE_ROOT / "outputs"
DEFAULT_START_DATE = "2022-04-05"
DEFAULT_END_DATE = "2025-12-31"
DEFAULT_TOP_N = 20
DEFAULT_CHUNK_DAYS = 31
DEFAULT_PAGE_SIZE = 5000
DEFAULT_MAX_ATTEMPTS = 2
DEFAULT_SLEEP_BETWEEN_ATTEMPTS = 5


RENAME_TO_LEGACY_COLUMNS = {
    "NmEmit": "NOME_EMITENTE",
    "CNPJEmit": "CNPJ_CPF_EMITENTE",
    "UFEmit": "UF_EMITENTE",
}


def _read_consolidado(path: Path) -> pd.DataFrame:
    if not path.exists():
        raise FileNotFoundError(f"Workbook tbNFe nao encontrado: {path}")
    data = pd.read_excel(path, sheet_name="consolidado", dtype=object)
    data.columns = [str(column).strip() for column in data.columns]
    return data


def _clean_cnpj(value: Any) -> str:
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return ""
    text = str(value).strip()
    if text.endswith(".0"):
        text = text[:-2]
    return re.sub(r"\D", "", text)


def _prepare_potential_workbook(source_path: Path, temp_dir: Path, exclude_cnpjs: set[str] | None = None) -> Path:
    data = _read_consolidado(source_path)
    data = data.rename(columns=RENAME_TO_LEGACY_COLUMNS)
    required_columns = ["NOME_EMITENTE", "CNPJ_CPF_EMITENTE", "UF_EMITENTE", "QTD_DOC", "TOTAL_ITEM", "DIFAL_DEST"]
    missing = [column for column in required_columns if column not in data.columns]
    if missing:
        raise ValueError(f"Workbook tbNFe sem colunas esperadas para ranking de itens: {missing}")

    if exclude_cnpjs:
        data["_cnpj_norm"] = data["CNPJ_CPF_EMITENTE"].map(_clean_cnpj)
        data = data[~data["_cnpj_norm"].isin(exclude_cnpjs)].drop(columns=["_cnpj_norm"])

    prepared_path = temp_dir / "tb_nfe_potencial_normalizado.xlsx"
    with pd.ExcelWriter(prepared_path, engine="openpyxl") as writer:
        data[required_columns].to_excel(writer, sheet_name="consolidado", index=False)
    return prepared_path


def _output_path(output_dir: Path, start_date: str, end_date: str, top_n: int) -> Path:
    return output_dir / f"tb_nfe_itens_top{top_n}_{start_date}_a_{end_date}.xlsx"


def run_items_top_export(
    *,
    potential_path: str | Path = DEFAULT_POTENTIAL_PATH,
    start_date: str = DEFAULT_START_DATE,
    end_date: str = DEFAULT_END_DATE,
    top_n: int = DEFAULT_TOP_N,
    chunk_days: int = DEFAULT_CHUNK_DAYS,
    page_size: int = DEFAULT_PAGE_SIZE,
    output_dir: str | Path = DEFAULT_OUTPUT_DIR,
    output_path: str | Path | None = None,
    max_attempts: int = DEFAULT_MAX_ATTEMPTS,
    sleep_between_attempts: int = DEFAULT_SLEEP_BETWEEN_ATTEMPTS,
    exclude_cnpjs: list[str] | set[str] | None = None,
    quiet: bool = False,
    progress_callback: Callable[[dict[str, Any]], None] | None = None,
) -> dict[str, Any]:
    potential_path = Path(potential_path)
    output_dir = Path(output_dir)
    final_output_path = Path(output_path) if output_path else _output_path(output_dir, start_date, end_date, top_n)
    exclude_set = {_clean_cnpj(value) for value in (exclude_cnpjs or []) if _clean_cnpj(value)}
    if progress_callback:
        progress_callback({"stage": "prepare", "progress": 0.0, "message": "Preparando workbook de potencial."})

    output_dir.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix="tb_nfe_itens_top_") as tmp:
        normalized_path = _prepare_potential_workbook(potential_path, Path(tmp), exclude_set)
        result = run_top20_debt_analysis(
            potential_excel_path=normalized_path,
            start_date=start_date,
            end_date=end_date,
            output_dir=output_dir,
            output_path=final_output_path,
            top_n=top_n,
            chunk_days=chunk_days,
            page_size=page_size,
            max_attempts=max_attempts,
            sleep_between_attempts=sleep_between_attempts,
            verbose=not quiet,
            progress_callback=progress_callback,
        )

    return {
        "source": "tbNFe",
        "mode": "itens_apenas_top_selecionados",
        "potential_path": str(potential_path),
        "output_path": str(final_output_path),
        "start_date": start_date,
        "end_date": end_date,
        "top_n": top_n,
        "chunk_days": chunk_days,
        "page_size": page_size,
        "excluded_cnpjs": len(exclude_set),
        "status": "ok",
        "rows_ranking_top": len(result["ranking_top20"]),
        "rows_itens_top": len(result["itens_top20"]),
        "rows_manifest": len(result["manifest"]),
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Baixa itens NF-e apenas para os contribuintes top selecionados em tbNFe."
    )
    parser.add_argument("--potential-path", default=str(DEFAULT_POTENTIAL_PATH), help="Workbook tbNFe de origem.")
    parser.add_argument("--start-date", default=DEFAULT_START_DATE, help="Data inicial YYYY-MM-DD.")
    parser.add_argument("--end-date", default=DEFAULT_END_DATE, help="Data final YYYY-MM-DD.")
    parser.add_argument("--top-n", type=int, default=DEFAULT_TOP_N, help="Quantidade de contribuintes top.")
    parser.add_argument("--chunk-days", type=int, default=DEFAULT_CHUNK_DAYS, help="Tamanho da janela em dias.")
    parser.add_argument("--page-size", type=int, default=DEFAULT_PAGE_SIZE, help="Tamanho da pagina da API.")
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_DIR), help="Diretorio de saida.")
    parser.add_argument("--output-path", default=None, help="Arquivo final opcional.")
    parser.add_argument("--exclude-cnpj", action="append", default=[], help="CNPJ a excluir do ranking. Pode repetir.")
    parser.add_argument("--max-attempts", type=int, default=DEFAULT_MAX_ATTEMPTS, help="Tentativas por janela.")
    parser.add_argument(
        "--sleep-between-attempts",
        type=int,
        default=DEFAULT_SLEEP_BETWEEN_ATTEMPTS,
        help="Pausa em segundos entre tentativas.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Mostra o plano sem conectar ao MicroStrategy.")
    parser.add_argument("--quiet", action="store_true", help="Reduz logs de progresso.")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    potential_path = Path(args.potential_path)
    output_dir = Path(args.output_dir)
    final_output_path = Path(args.output_path) if args.output_path else _output_path(
        output_dir,
        args.start_date,
        args.end_date,
        args.top_n,
    )

    plan: dict[str, Any] = {
        "source": "tbNFe",
        "mode": "itens_apenas_top_selecionados",
        "potential_path": str(potential_path),
        "output_path": str(final_output_path),
        "start_date": args.start_date,
        "end_date": args.end_date,
        "top_n": args.top_n,
        "chunk_days": args.chunk_days,
        "page_size": args.page_size,
    }
    if args.dry_run:
        print(json.dumps(plan, ensure_ascii=False, indent=2))
        return 0

    summary = run_items_top_export(
        potential_path=potential_path,
        start_date=args.start_date,
        end_date=args.end_date,
        top_n=args.top_n,
        chunk_days=args.chunk_days,
        page_size=args.page_size,
        output_dir=output_dir,
        output_path=final_output_path,
        max_attempts=args.max_attempts,
        sleep_between_attempts=args.sleep_between_attempts,
        exclude_cnpjs=args.exclude_cnpj,
        quiet=args.quiet,
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
