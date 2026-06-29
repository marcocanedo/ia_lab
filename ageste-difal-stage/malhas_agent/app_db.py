from __future__ import annotations

import hashlib
import hmac
import json
import os
import secrets
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import duckdb
import pandas as pd


WORKSPACE_ROOT = Path(__file__).resolve().parent
DEFAULT_DB_PATH = WORKSPACE_ROOT / "db" / "malhas.duckdb"
PBKDF2_ITERATIONS = 260_000
RULE_STATUSES = {"candidata", "em_teste", "aprovada", "rejeitada", "arquivada", "suspensa", "excluida_logica"}


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def connect(db_path: str | Path = DEFAULT_DB_PATH, *, read_only: bool = False) -> duckdb.DuckDBPyConnection:
    return duckdb.connect(str(db_path), read_only=read_only)


def qident(identifier: str) -> str:
    return '"' + identifier.replace('"', '""') + '"'


def table_exists(conn: duckdb.DuckDBPyConnection, table_name: str) -> bool:
    row = conn.execute(
        "SELECT count(*) FROM information_schema.tables WHERE table_name = ?",
        [table_name],
    ).fetchone()
    return bool(row and row[0])


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, PBKDF2_ITERATIONS)
    return f"pbkdf2_sha256${PBKDF2_ITERATIONS}${salt.hex()}${digest.hex()}"


def verify_password(password: str, stored_hash: str) -> bool:
    try:
        scheme, iterations_raw, salt_hex, digest_hex = stored_hash.split("$", 3)
        if scheme != "pbkdf2_sha256":
            return False
        iterations = int(iterations_raw)
        salt = bytes.fromhex(salt_hex)
        expected = bytes.fromhex(digest_hex)
    except Exception:
        return False

    actual = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)
    return hmac.compare_digest(actual, expected)


def init_management_tables(conn: duckdb.DuckDBPyConnection) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS app_users (
            username VARCHAR PRIMARY KEY,
            password_hash VARCHAR NOT NULL,
            role VARCHAR NOT NULL,
            active BOOLEAN NOT NULL DEFAULT TRUE,
            created_at VARCHAR NOT NULL,
            updated_at VARCHAR NOT NULL
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS param_lotes (
            param_id VARCHAR PRIMARY KEY,
            nome VARCHAR NOT NULL,
            descricao VARCHAR,
            top_n INTEGER,
            potencial_minimo DOUBLE,
            status_triagem_json VARCHAR,
            incluir_com_recolhimento BOOLEAN,
            incluir_baixados BOOLEAN,
            filtros_json VARCHAR,
            ativo BOOLEAN NOT NULL DEFAULT FALSE,
            criado_por VARCHAR,
            criado_em VARCHAR NOT NULL,
            atualizado_em VARCHAR NOT NULL
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS lotes_analise (
            lote_id VARCHAR PRIMARY KEY,
            param_id VARCHAR,
            nome VARCHAR NOT NULL,
            descricao VARCHAR,
            criado_por VARCHAR,
            criado_em VARCHAR NOT NULL,
            qtd_casos BIGINT,
            potencial_total DOUBLE
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS lote_casos (
            lote_id VARCHAR NOT NULL,
            cnpj_norm VARCHAR,
            nome_pessoa VARCHAR,
            potencial_arrecadacao DOUBLE,
            difal_nfe DOUBLE,
            difal_gia DOUBLE,
            valor_recolhido DOUBLE,
            status_triagem VARCHAR,
            sinais_falso_positivo VARCHAR
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS item_analysis_runs (
            run_id VARCHAR PRIMARY KEY,
            lote_id VARCHAR,
            status VARCHAR,
            source_file VARCHAR,
            rows_loaded BIGINT,
            criado_por VARCHAR,
            criado_em VARCHAR NOT NULL,
            detalhes VARCHAR
        )
        """
    )
    _ensure_rules_table(conn)
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS marcacoes_falso_positivo (
            marcacao_id VARCHAR PRIMARY KEY,
            lote_id VARCHAR,
            escopo VARCHAR NOT NULL,
            cnpj_norm VARCHAR,
            item_id VARCHAR,
            agrupamento_json VARCHAR,
            motivo VARCHAR NOT NULL,
            active BOOLEAN NOT NULL DEFAULT TRUE,
            criado_por VARCHAR,
            criado_em VARCHAR NOT NULL,
            atualizado_em VARCHAR NOT NULL
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS revisoes_sem_falso_positivo (
            revisao_id VARCHAR PRIMARY KEY,
            id_nfe VARCHAR NOT NULL,
            item_id VARCHAR,
            comentario VARCHAR,
            active BOOLEAN NOT NULL DEFAULT TRUE,
            criado_por VARCHAR,
            criado_em VARCHAR NOT NULL,
            atualizado_em VARCHAR NOT NULL
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS admin_action_events (
            action_id VARCHAR PRIMARY KEY,
            session_id VARCHAR,
            usuario VARCHAR,
            action_type VARCHAR NOT NULL,
            entity_type VARCHAR,
            entity_id VARCHAR,
            before_payload VARCHAR,
            after_payload VARCHAR,
            undone BOOLEAN NOT NULL DEFAULT FALSE,
            created_at VARCHAR NOT NULL,
            undone_at VARCHAR
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS lotes_autorregularizacao (
            lote_id VARCHAR PRIMARY KEY,
            param_id VARCHAR,
            nome VARCHAR NOT NULL,
            descricao VARCHAR,
            status VARCHAR NOT NULL,
            qtd_casos BIGINT,
            potencial_total DOUBLE,
            criado_por VARCHAR,
            criado_em VARCHAR NOT NULL,
            atualizado_em VARCHAR NOT NULL
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS lote_autorregularizacao_casos (
            lote_id VARCHAR NOT NULL,
            cnpj_norm VARCHAR NOT NULL,
            nome_pessoa VARCHAR,
            potencial_arrecadacao DOUBLE,
            difal_nfe DOUBLE,
            difal_gia DOUBLE,
            valor_recolhido DOUBLE,
            status_triagem VARCHAR,
            criado_em VARCHAR NOT NULL
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS regra_eventos (
            evento_id VARCHAR PRIMARY KEY,
            regra_id VARCHAR NOT NULL,
            usuario VARCHAR,
            acao VARCHAR NOT NULL,
            comentario VARCHAR,
            criado_em VARCHAR NOT NULL
        )
        """
    )


def _ensure_rules_table(conn: duckdb.DuckDBPyConnection) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS regras_malha (
            regra_id VARCHAR PRIMARY KEY,
            tipo VARCHAR NOT NULL,
            nome VARCHAR NOT NULL,
            descricao VARCHAR,
            status VARCHAR NOT NULL,
            filtros_json VARCHAR,
            hipotese_texto VARCHAR,
            fonte_externa_tipo VARCHAR,
            referencia_externa VARCHAR,
            evidencia_resumo VARCHAR,
            impacto_estimado DOUBLE,
            vinculo_json VARCHAR,
            criado_por VARCHAR,
            criado_em VARCHAR NOT NULL,
            atualizado_em VARCHAR NOT NULL
        )
        """
    )
    # Recria a tabela sem CHECK antigo para aceitar status operacionais novos.
    conn.execute(
        """
        CREATE OR REPLACE TABLE regras_malha_migrated AS
        SELECT
            regra_id, tipo, nome, descricao, status, filtros_json, hipotese_texto,
            fonte_externa_tipo, referencia_externa, evidencia_resumo, impacto_estimado,
            vinculo_json, criado_por, criado_em, atualizado_em
        FROM regras_malha
        """
    )
    conn.execute("DROP TABLE regras_malha")
    conn.execute("ALTER TABLE regras_malha_migrated RENAME TO regras_malha")


def create_or_update_user(
    conn: duckdb.DuckDBPyConnection,
    *,
    username: str,
    password: str,
    role: str,
    active: bool = True,
) -> None:
    if role not in {"admin", "analista", "leitor"}:
        raise ValueError("role deve ser admin, analista ou leitor.")
    timestamp = now_iso()
    password_hash = hash_password(password)
    conn.execute(
        """
        INSERT INTO app_users (username, password_hash, role, active, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT (username) DO UPDATE SET
            password_hash = excluded.password_hash,
            role = excluded.role,
            active = excluded.active,
            updated_at = excluded.updated_at
        """,
        [username, password_hash, role, active, timestamp, timestamp],
    )


def authenticate(
    conn: duckdb.DuckDBPyConnection,
    *,
    username: str,
    password: str,
) -> dict[str, Any] | None:
    row = conn.execute(
        "SELECT username, password_hash, role, active FROM app_users WHERE username = ?",
        [username],
    ).fetchone()
    if not row:
        return None
    user, password_hash, role, active = row
    if not active or not verify_password(password, password_hash):
        return None
    return {"username": user, "role": role}


def can_write(role: str | None) -> bool:
    return role in {"admin", "analista"}


def can_admin(role: str | None) -> bool:
    return role == "admin"


def create_rule(
    conn: duckdb.DuckDBPyConnection,
    *,
    tipo: str,
    nome: str,
    descricao: str,
    usuario: str,
    filtros: dict[str, Any] | None = None,
    hipotese_texto: str | None = None,
    fonte_externa_tipo: str | None = None,
    referencia_externa: str | None = None,
    evidencia_resumo: str | None = None,
    impacto_estimado: float | None = None,
    vinculo: dict[str, Any] | None = None,
) -> str:
    if tipo == "deterministica" and not filtros:
        raise ValueError("Regra deterministica precisa de filtros_json.")
    if tipo == "nao_deterministica" and not str(hipotese_texto or "").strip():
        raise ValueError("Hipotese nao deterministica precisa de descricao textual.")

    regra_id = str(uuid.uuid4())
    timestamp = now_iso()
    conn.execute(
        """
        INSERT INTO regras_malha (
            regra_id, tipo, nome, descricao, status, filtros_json, hipotese_texto,
            fonte_externa_tipo, referencia_externa, evidencia_resumo,
            impacto_estimado, vinculo_json, criado_por, criado_em, atualizado_em
        )
        VALUES (?, ?, ?, ?, 'candidata', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [
            regra_id,
            tipo,
            nome,
            descricao,
            json.dumps(filtros or {}, ensure_ascii=False) if tipo == "deterministica" else None,
            hipotese_texto if tipo == "nao_deterministica" else None,
            fonte_externa_tipo,
            referencia_externa,
            evidencia_resumo,
            impacto_estimado,
            json.dumps(vinculo or {}, ensure_ascii=False),
            usuario,
            timestamp,
            timestamp,
        ],
    )
    add_rule_event(conn, regra_id=regra_id, usuario=usuario, acao="criada", comentario="Regra criada pela tela de analise de itens.")
    return regra_id


def add_rule_event(
    conn: duckdb.DuckDBPyConnection,
    *,
    regra_id: str,
    usuario: str,
    acao: str,
    comentario: str | None = None,
) -> None:
    conn.execute(
        """
        INSERT INTO regra_eventos (evento_id, regra_id, usuario, acao, comentario, criado_em)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        [str(uuid.uuid4()), regra_id, usuario, acao, comentario, now_iso()],
    )


def update_rule_status(
    conn: duckdb.DuckDBPyConnection,
    *,
    regra_id: str,
    status: str,
    usuario: str,
    comentario: str | None = None,
) -> None:
    if status not in RULE_STATUSES:
        raise ValueError("Status invalido.")
    previous = conn.execute("SELECT status FROM regras_malha WHERE regra_id = ?", [regra_id]).fetchone()
    conn.execute(
        "UPDATE regras_malha SET status = ?, atualizado_em = ? WHERE regra_id = ?",
        [status, now_iso(), regra_id],
    )
    old_status = previous[0] if previous else ""
    add_rule_event(conn, regra_id=regra_id, usuario=usuario, acao=f"status:{old_status}->{status}", comentario=comentario)


def record_admin_action(
    conn: duckdb.DuckDBPyConnection,
    *,
    action_id: str,
    session_id: str,
    usuario: str,
    action_type: str,
    entity_type: str,
    entity_id: str,
    before_payload: dict[str, Any] | None = None,
    after_payload: dict[str, Any] | None = None,
) -> None:
    conn.execute(
        """
        INSERT INTO admin_action_events (
            action_id, session_id, usuario, action_type, entity_type, entity_id,
            before_payload, after_payload, undone, created_at, undone_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, FALSE, ?, NULL)
        """,
        [
            action_id,
            session_id,
            usuario,
            action_type,
            entity_type,
            entity_id,
            json.dumps(before_payload or {}, ensure_ascii=False),
            json.dumps(after_payload or {}, ensure_ascii=False),
            now_iso(),
        ],
    )


def mark_admin_action_undone(conn: duckdb.DuckDBPyConnection, action_id: str) -> None:
    conn.execute(
        "UPDATE admin_action_events SET undone = TRUE, undone_at = ? WHERE action_id = ?",
        [now_iso(), action_id],
    )


def dataframe_to_excel_bytes(sheets: dict[str, pd.DataFrame]) -> bytes:
    from io import BytesIO

    buffer = BytesIO()
    with pd.ExcelWriter(buffer, engine="openpyxl") as writer:
        for name, frame in sheets.items():
            frame.to_excel(writer, sheet_name=name[:31], index=False)
    return buffer.getvalue()
