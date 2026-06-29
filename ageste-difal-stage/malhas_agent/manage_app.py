from __future__ import annotations

import argparse
import getpass
import json
from pathlib import Path

from app_db import DEFAULT_DB_PATH, connect, create_or_update_user, init_management_tables


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Administra o modulo gerencial da malha.")
    parser.add_argument("--db-path", default=str(DEFAULT_DB_PATH), help="Caminho do banco DuckDB.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("init-db", help="Cria tabelas de gestao.")

    create_user = subparsers.add_parser("create-user", help="Cria ou atualiza usuario.")
    create_user.add_argument("--username", required=True)
    create_user.add_argument("--role", choices=["admin", "analista", "leitor"], required=True)
    create_user.add_argument("--password", default=None, help="Senha. Se omitida, pergunta no terminal.")
    create_user.add_argument("--inactive", action="store_true", help="Cria usuario inativo.")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    db_path = Path(args.db_path)
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = connect(db_path)
    try:
        init_management_tables(conn)
        if args.command == "init-db":
            print(json.dumps({"status": "ok", "db_path": str(db_path)}, ensure_ascii=False, indent=2))
            return 0

        if args.command == "create-user":
            password = args.password or getpass.getpass("Senha: ")
            create_or_update_user(
                conn,
                username=args.username,
                password=password,
                role=args.role,
                active=not args.inactive,
            )
            print(
                json.dumps(
                    {"status": "ok", "username": args.username, "role": args.role, "active": not args.inactive},
                    ensure_ascii=False,
                    indent=2,
                )
            )
            return 0
    finally:
        conn.close()

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
