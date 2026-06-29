from __future__ import annotations

import json
import sys
import uuid
from dataclasses import replace
from pathlib import Path
from typing import Any

import duckdb
import pandas as pd
import streamlit as st

from app_db import (
    DEFAULT_DB_PATH,
    authenticate,
    can_admin,
    can_write,
    connect,
    create_rule,
    create_or_update_user,
    dataframe_to_excel_bytes,
    init_management_tables,
    mark_admin_action_undone,
    now_iso,
    record_admin_action,
    table_exists,
    update_rule_status,
)


ROOT = Path(__file__).resolve().parents[1]
TB_NFE_PATH = ROOT / "tb_nfe" / "outputs" / "tb_nfe_2022-04-05_a_2025-12-31.xlsx"
st.set_page_config(page_title="Malhas DIFAL", layout="wide")


class StreamlitDuckDBConnection:
    def __init__(self, conn: duckdb.DuckDBPyConnection) -> None:
        self._conn = conn

    def close(self) -> None:
        # Streamlit reruns the script often. Keeping one process-level DuckDB
        # connection avoids reopening the same file and triggering Windows locks.
        return None

    def __getattr__(self, name: str) -> Any:
        return getattr(self._conn, name)


@st.cache_resource(show_spinner=False)
def _cached_conn(db_path: str) -> StreamlitDuckDBConnection:
    conn = connect(Path(db_path))
    init_management_tables(conn)
    return StreamlitDuckDBConnection(conn)


def get_conn() -> StreamlitDuckDBConnection:
    db_path = Path(st.session_state.get("db_path", DEFAULT_DB_PATH))
    return _cached_conn(str(db_path))


def query_df(sql: str, params: list[Any] | None = None) -> pd.DataFrame:
    conn = get_conn()
    try:
        return conn.execute(sql, params or []).df()
    finally:
        conn.close()


def execute(sql: str, params: list[Any] | None = None) -> None:
    conn = get_conn()
    try:
        conn.execute(sql, params or [])
    finally:
        conn.close()


def safe_json_loads(value: str, fallback: Any) -> Any:
    try:
        return json.loads(value) if str(value or "").strip() else fallback
    except json.JSONDecodeError as exc:
        raise ValueError(f"JSON invÃ¡lido: {exc}") from exc


def lenient_json_loads(value: str, fallback: Any) -> Any:
    try:
        return json.loads(value) if str(value or "").strip() else fallback
    except Exception:
        return fallback


def load_deterministic_rules(statuses: list[str] | None = None) -> pd.DataFrame:
    where = "WHERE tipo = 'deterministica' AND coalesce(filtros_json, '') <> ''"
    params: list[Any] = []
    if statuses:
        placeholders = ", ".join(["?"] * len(statuses))
        where += f" AND status IN ({placeholders})"
        params.extend(statuses)
    return query_df(
        f"""
        SELECT regra_id, nome, status, filtros_json
        FROM regras_malha
        {where}
        ORDER BY nome, criado_em DESC
        """,
        params,
    )


def rule_options(frame: pd.DataFrame) -> dict[str, str]:
    if frame.empty:
        return {}
    return {
        f"{row['nome']} [{row['status']}] - {str(row['regra_id'])[:8]}": str(row["regra_id"])
        for _, row in frame.iterrows()
    }


def rule_filter_predicates(selected_rule_ids: list[str], rules: pd.DataFrame) -> tuple[list[str], list[Any]]:
    predicates: list[str] = []
    params: list[Any] = []
    if not selected_rule_ids or rules.empty:
        return predicates, params

    allowed_columns = {
        "cest_norm",
        "ncm_norm",
        "cfop_norm",
        "cst_norm",
        "gtin_norm",
        "desc_item_norm",
        "vl_aliq_uf_dest",
        "vl_base_calculo_icms",
        "vl_icms_uf_dest",
    }
    numeric_columns = {"vl_aliq_uf_dest", "vl_base_calculo_icms", "vl_icms_uf_dest"}
    by_id = {str(row["regra_id"]): row for _, row in rules.iterrows()}
    for regra_id in selected_rule_ids:
        row = by_id.get(str(regra_id))
        if row is None:
            continue
        filtros = lenient_json_loads(str(row.get("filtros_json") or ""), {})
        criteria = filtros.get("criterios") if isinstance(filtros, dict) else None
        if not criteria:
            continue
        rule_parts: list[str] = []
        for criterion in criteria:
            if not isinstance(criterion, dict):
                continue
            campo = str(criterion.get("campo") or "")
            operador = str(criterion.get("operador") or "")
            valor = str(criterion.get("valor") or "")
            if campo not in allowed_columns:
                continue
            numeric_value = None
            if campo in numeric_columns:
                try:
                    numeric_value = float(valor)
                except ValueError:
                    continue
            expr = f"coalesce({campo}, 0)" if campo in numeric_columns else f"lower(coalesce({campo}, ''))"
            if operador == "==":
                rule_parts.append(f"{expr} = ?")
                params.append(numeric_value if campo in numeric_columns else valor.lower())
            elif operador == "!=":
                rule_parts.append(f"{expr} <> ?")
                params.append(numeric_value if campo in numeric_columns else valor.lower())
            elif operador == "contains" and campo not in numeric_columns:
                rule_parts.append(f"{expr} LIKE ?")
                params.append(f"%{valor.lower()}%")
            elif operador == "not_contains" and campo not in numeric_columns:
                rule_parts.append(f"{expr} NOT LIKE ?")
                params.append(f"%{valor.lower()}%")
            elif operador == "is_empty" and campo not in numeric_columns:
                rule_parts.append(f"coalesce({campo}, '') = ''")
            elif operador == "not_empty" and campo not in numeric_columns:
                rule_parts.append(f"coalesce({campo}, '') <> ''")
            elif operador in {">", ">=", "<", "<="} and campo in numeric_columns:
                rule_parts.append(f"{expr} {operador} ?")
                params.append(numeric_value)
        if rule_parts:
            predicates.append("(" + " AND ".join(rule_parts) + ")")
    return predicates, params


def dataframe_selected_rows(event: Any) -> list[int]:
    if isinstance(event, dict):
        selection = event.get("selection") or {}
        return list(selection.get("rows") or [])
    selection = getattr(event, "selection", None)
    return list(getattr(selection, "rows", []) or [])


def ensure_session_state() -> None:
    st.session_state.setdefault("undo_stack", [])
    st.session_state.setdefault("session_id", str(uuid.uuid4()))


def push_undo(
    *,
    user: dict[str, Any],
    action_type: str,
    entity_type: str,
    entity_id: str,
    before_payload: dict[str, Any] | None = None,
    after_payload: dict[str, Any] | None = None,
) -> None:
    ensure_session_state()
    action_id = str(uuid.uuid4())
    conn = get_conn()
    try:
        record_admin_action(
            conn,
            action_id=action_id,
            session_id=st.session_state["session_id"],
            usuario=user["username"],
            action_type=action_type,
            entity_type=entity_type,
            entity_id=entity_id,
            before_payload=before_payload,
            after_payload=after_payload,
        )
    finally:
        conn.close()
    st.session_state["undo_stack"].append(
        {
            "action_id": action_id,
            "action_type": action_type,
            "entity_type": entity_type,
            "entity_id": entity_id,
            "before_payload": before_payload or {},
            "after_payload": after_payload or {},
        }
    )


def undo_last_action() -> str:
    ensure_session_state()
    if not st.session_state["undo_stack"]:
        raise ValueError("Nao ha ato nesta sessao para desfazer.")
    action = st.session_state["undo_stack"].pop()
    conn = get_conn()
    try:
        action_type = action["action_type"]
        entity_id = action["entity_id"]
        before_payload = action["before_payload"]
        if action_type == "create_param":
            conn.execute("DELETE FROM param_lotes WHERE param_id = ?", [entity_id])
        elif action_type == "delete_param":
            conn.execute(
                """
                INSERT INTO param_lotes (
                    param_id, nome, ativo, top_n, potencial_minimo, status_triagem_json,
                    incluir_com_recolhimento, incluir_baixados, criado_por, criado_em, atualizado_em,
                    descricao, filtros_json
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    before_payload.get("param_id"),
                    before_payload.get("nome"),
                    before_payload.get("ativo"),
                    before_payload.get("top_n"),
                    before_payload.get("potencial_minimo"),
                    before_payload.get("status_triagem_json"),
                    before_payload.get("incluir_com_recolhimento"),
                    before_payload.get("incluir_baixados"),
                    before_payload.get("criado_por"),
                    before_payload.get("criado_em"),
                    now_iso(),
                    before_payload.get("descricao"),
                    before_payload.get("filtros_json"),
                ],
            )
        elif action_type == "deactivate_param":
            conn.execute("UPDATE param_lotes SET ativo = TRUE, atualizado_em = ? WHERE param_id = ?", [now_iso(), entity_id])
        elif action_type == "set_param_active":
            conn.execute("UPDATE param_lotes SET ativo = ?, atualizado_em = ? WHERE param_id = ?", [before_payload.get("ativo"), now_iso(), entity_id])
        elif action_type == "create_rule":
            update_rule_status(conn, regra_id=entity_id, status="excluida_logica", usuario="undo", comentario="Desfeito na sessao.")
        elif action_type == "update_rule_status":
            update_rule_status(
                conn,
                regra_id=entity_id,
                status=before_payload["status"],
                usuario="undo",
                comentario="Status restaurado por desfazer ato.",
            )
        elif action_type == "mark_false_positive":
            conn.execute(
                "UPDATE marcacoes_falso_positivo SET active = FALSE, atualizado_em = ? WHERE marcacao_id = ?",
                [now_iso(), entity_id],
            )
        elif action_type == "mark_no_false_positive":
            conn.execute(
                "UPDATE revisoes_sem_falso_positivo SET active = FALSE, atualizado_em = ? WHERE revisao_id = ?",
                [now_iso(), entity_id],
            )
        elif action_type == "approve_lote":
            conn.execute("UPDATE lotes_autorregularizacao SET status = 'desfeito', atualizado_em = ? WHERE lote_id = ?", [now_iso(), entity_id])
        else:
            raise ValueError(f"Tipo de ato sem undo implementado: {action_type}")
        mark_admin_action_undone(conn, action["action_id"])
    finally:
        conn.close()
    return action["action_type"]


def require_login() -> dict[str, Any] | None:
    st.sidebar.text_input("Banco DuckDB", value=str(DEFAULT_DB_PATH), key="db_path")
    user = st.session_state.get("user")
    if user:
        st.sidebar.caption(f"UsuÃ¡rio: {user['username']} ({user['role']})")
        if st.sidebar.button("Sair"):
            st.session_state.pop("user", None)
            st.session_state.pop("undo_stack", None)
            st.session_state.pop("session_id", None)
            st.rerun()
        return user

    st.title("Malhas DIFAL")
    st.subheader("Login")
    username = st.text_input("UsuÃ¡rio")
    password = st.text_input("Senha", type="password")
    if st.button("Entrar", type="primary"):
        conn = get_conn()
        try:
            authenticated = authenticate(conn, username=username, password=password)
        finally:
            conn.close()
        if authenticated:
            st.session_state["user"] = authenticated
            st.session_state["undo_stack"] = []
            st.session_state["session_id"] = str(uuid.uuid4())
            st.rerun()
        st.error("UsuÃ¡rio ou senha invÃ¡lidos.")
    st.info("Use `uv run python malhas_agent/manage_app.py create-user --username seu_usuario --role admin` para criar o primeiro usuÃ¡rio.")
    return None


def ensure_item_tables() -> bool:
    conn = get_conn()
    try:
        return table_exists(conn, "mart_itens_detalhe")
    finally:
        conn.close()


def filter_options(column: str, limit: int = 500) -> list[str]:
    if not ensure_item_tables():
        return []
    frame = query_df(
        f"""
        SELECT DISTINCT CAST({column} AS VARCHAR) AS value
        FROM mart_itens_detalhe
        WHERE {column} IS NOT NULL AND CAST({column} AS VARCHAR) <> ''
        ORDER BY value
        LIMIT {limit}
        """
    )
    return frame["value"].dropna().astype(str).tolist()


def build_where(filters: dict[str, Any]) -> tuple[str, list[Any]]:
    predicates: list[str] = []
    params: list[Any] = []
    for key, column in [
        ("contribuintes", "cnpj_emit_norm"),
        ("notas", '"IdNFe"'),
        ("ncm", "ncm_norm"),
        ("cest", "cest_norm"),
        ("cfop", "cfop_norm"),
        ("cst", "cst_norm"),
        ("gtin", "gtin_norm"),
    ]:
        values = filters.get(key) or []
        if values:
            placeholders = ", ".join(["?"] * len(values))
            predicates.append(f"{column} IN ({placeholders})")
            params.extend(values)

    if filters.get("descricao"):
        predicates.append("lower(coalesce(desc_item_norm, '')) LIKE ?")
        params.append(f"%{str(filters['descricao']).lower()}%")
    if filters.get("valor_minimo", 0) > 0:
        predicates.append("coalesce(vl_icms_uf_dest, 0) >= ?")
        params.append(float(filters["valor_minimo"]))
    if filters.get("somente_com_sinais"):
        predicates.append("coalesce(sinais_falso_positivo_item, '') <> ''")
    if filters.get("somente_sem_sinais"):
        predicates.append("coalesce(sinais_falso_positivo_item, '') = ''")
    if filters.get("somente_revisados_sem_fp"):
        predicates.append(
            """
            EXISTS (
                SELECT 1
                FROM revisoes_sem_falso_positivo r
                WHERE r.active = TRUE
                  AND r.id_nfe = mart_itens_detalhe."IdNFe"
                  AND coalesce(r.item_id, '') = coalesce(mart_itens_detalhe."NrItem", '')
            )
            """
        )
    if filters.get("ocultar_revisados_sem_fp"):
        predicates.append(
            """
            NOT EXISTS (
                SELECT 1
                FROM revisoes_sem_falso_positivo r
                WHERE r.active = TRUE
                  AND r.id_nfe = mart_itens_detalhe."IdNFe"
                  AND coalesce(r.item_id, '') = coalesce(mart_itens_detalhe."NrItem", '')
            )
            """
        )
    if filters.get("data_inicio"):
        predicates.append("CAST(DtEmissao AS DATE) >= ?")
        params.append(filters["data_inicio"].isoformat())
    if filters.get("data_fim"):
        predicates.append("CAST(DtEmissao AS DATE) <= ?")
        params.append(filters["data_fim"].isoformat())
    rule_predicates, rule_params = rule_filter_predicates(
        filters.get("regras_deterministicas") or [],
        filters.get("regras_frame") if isinstance(filters.get("regras_frame"), pd.DataFrame) else pd.DataFrame(),
    )
    if rule_predicates:
        predicates.append("(" + " OR ".join(rule_predicates) + ")")
        params.extend(rule_params)

    return ("WHERE " + " AND ".join(predicates)) if predicates else "", params


def render_item_analysis(user: dict[str, Any]) -> None:
    st.title("AnÃ¡lise de Itens")
    if not ensure_item_tables():
        st.warning("As tabelas de itens ainda nÃ£o existem. Rode `uv run python malhas_agent/load_malhas_db.py --quality-checks` apÃ³s carregar `raw_tbNFeItens`.")
        return

    total_rows = query_df("SELECT count(*) AS qtd FROM mart_itens_detalhe")["qtd"].iloc[0]
    if total_rows == 0:
        st.info("A estrutura da tela estÃ¡ pronta, mas ainda nÃ£o hÃ¡ itens carregados em `raw_tbNFeItens`.")
        return

    st.sidebar.header("Filtros de Itens")
    approved_rules = load_deterministic_rules(["aprovada"])
    pending_rules = load_deterministic_rules(["candidata", "em_teste"])
    approved_rule_options = rule_options(approved_rules)
    pending_rule_options = rule_options(pending_rules)
    selected_approved_rule_labels = st.sidebar.multiselect("Regras determinÃƒÂ­sticas aprovadas", list(approved_rule_options.keys()))
    selected_pending_rule_labels = st.sidebar.multiselect("Regras nÃƒÂ£o implantadas", list(pending_rule_options.keys()))
    selected_rule_ids = [approved_rule_options[label] for label in selected_approved_rule_labels]
    selected_rule_ids.extend(pending_rule_options[label] for label in selected_pending_rule_labels)
    rules_frame = pd.concat([approved_rules, pending_rules], ignore_index=True) if selected_rule_ids else pd.DataFrame()
    filters = {
        "contribuintes": st.sidebar.multiselect("Contribuinte", filter_options("cnpj_emit_norm")),
        "notas": st.sidebar.multiselect("NF-e", filter_options('"IdNFe"', limit=1000)),
        "ncm": st.sidebar.multiselect("NCM", filter_options("ncm_norm")),
        "cest": st.sidebar.multiselect("CEST", filter_options("cest_norm")),
        "cfop": st.sidebar.multiselect("CFOP", filter_options("cfop_norm")),
        "cst": st.sidebar.multiselect("CST", filter_options("cst_norm")),
        "gtin": st.sidebar.multiselect("GTIN", filter_options("gtin_norm")),
        "descricao": st.sidebar.text_input("DescriÃ§Ã£o contÃ©m"),
        "valor_minimo": st.sidebar.number_input("DIFAL mÃ­nimo por item", min_value=0.0, value=0.0, step=100.0),
        "somente_com_sinais": st.sidebar.checkbox("Somente com sinais de falso positivo"),
        "somente_sem_sinais": st.sidebar.checkbox("Somente sem sinais de falso positivo"),
        "somente_revisados_sem_fp": st.sidebar.checkbox("Somente marcados como sem falso positivo"),
        "ocultar_revisados_sem_fp": st.sidebar.checkbox("Ocultar marcados como sem falso positivo"),
        "data_inicio": st.sidebar.date_input("Data inicial", value=None),
        "data_fim": st.sidebar.date_input("Data final", value=None),
        "regras_deterministicas": selected_rule_ids,
        "regras_frame": rules_frame,
    }
    where_sql, params = build_where(filters)

    metrics = query_df(
        f"""
        SELECT
            count(*) AS itens,
            count(DISTINCT "IdNFe") AS documentos,
            count(DISTINCT cnpj_emit_norm) AS contribuintes,
            sum(coalesce(vl_total_item, 0)) AS valor_itens,
            sum(coalesce(vl_icms_uf_dest, 0)) AS difal_destino,
            sum(coalesce(vl_icms_fcp_uf_dest, 0)) AS fcp_destino
        FROM mart_itens_detalhe
        {where_sql}
        """,
        params,
    ).iloc[0]
    cols = st.columns(6)
    cols[0].metric("Itens", f"{int(metrics['itens']):,}".replace(",", "."))
    cols[1].metric("Documentos", f"{int(metrics['documentos']):,}".replace(",", "."))
    cols[2].metric("Contribuintes", f"{int(metrics['contribuintes']):,}".replace(",", "."))
    cols[3].metric("Valor itens", f"R$ {metrics['valor_itens']:,.2f}")
    cols[4].metric("DIFAL destino", f"R$ {metrics['difal_destino']:,.2f}")
    cols[5].metric("FCP destino", f"R$ {metrics['fcp_destino']:,.2f}")

    st.subheader("Notas")
    st.caption("Selecione uma NF-e na tabela para abrir a lista resumida dos itens. No Streamlit, a seleÃ§Ã£o de linha substitui o duplo clique.")
    notas = query_df(
        f"""
        SELECT
            "IdNFe",
            any_value("DtEmissao") AS dt_emissao,
            any_value("NrDoc") AS nr_doc,
            any_value("NmEmit") AS nome_emitente,
            any_value(cnpj_emit_norm) AS cnpj_emit_norm,
            any_value("UFEmit") AS uf_emitente,
            count(*) AS qtd_itens,
            sum(coalesce(vl_total_item, 0)) AS vl_total_item,
            sum(coalesce(vl_icms_uf_dest, 0)) AS vl_icms_uf_dest,
            sum(coalesce(vl_icms_fcp_uf_dest, 0)) AS vl_icms_fcp_uf_dest,
            count(*) FILTER (WHERE coalesce(sinais_falso_positivo_item, '') <> '') AS qtd_itens_com_sinal
        FROM mart_itens_detalhe
        {where_sql}
        GROUP BY "IdNFe"
        ORDER BY vl_icms_uf_dest DESC
        LIMIT 500
        """,
        params,
    )
    note_event = st.dataframe(
        notas,
        use_container_width=True,
        hide_index=True,
        on_select="rerun",
        selection_mode="single-row",
        key="notas_grid",
    )
    note_rows = dataframe_selected_rows(note_event)
    selected_note = notas.iloc[note_rows[0]].to_dict() if note_rows else None

    selected_item: dict[str, Any] | None = None
    itens_nota = pd.DataFrame()
    if selected_note:
        selected_note_id = str(selected_note["IdNFe"])
        if st.session_state.get("selected_note_id") != selected_note_id:
            st.session_state["selected_note_id"] = selected_note_id
            st.session_state.pop("selected_item_id", None)
        st.subheader("Dados do Documento")
        doc_cols = st.columns(6)
        doc_cols[0].metric("NF-e", str(selected_note.get("IdNFe") or "")[:18])
        doc_cols[1].metric("Documento", str(selected_note.get("nr_doc") or ""))
        doc_cols[2].metric("Data", str(selected_note.get("dt_emissao") or "")[:10])
        doc_cols[3].metric("Emitente", str(selected_note.get("cnpj_emit_norm") or ""))
        doc_cols[4].metric("Itens", int(selected_note.get("qtd_itens") or 0))
        doc_cols[5].metric("DIFAL NF-e", f"R$ {float(selected_note.get('vl_icms_uf_dest') or 0):,.2f}")
        st.dataframe(
            pd.DataFrame(
                [
                    {
                        "IdNFe": selected_note.get("IdNFe"),
                        "DtEmissao": selected_note.get("dt_emissao"),
                        "NrDoc": selected_note.get("nr_doc"),
                        "NmEmit": selected_note.get("nome_emitente"),
                        "CNPJEmit": selected_note.get("cnpj_emit_norm"),
                        "UFEmit": selected_note.get("uf_emitente"),
                        "qtd_itens": selected_note.get("qtd_itens"),
                        "vl_total_item": selected_note.get("vl_total_item"),
                        "vl_icms_uf_dest": selected_note.get("vl_icms_uf_dest"),
                        "vl_icms_fcp_uf_dest": selected_note.get("vl_icms_fcp_uf_dest"),
                    }
                ]
            ),
            use_container_width=True,
            hide_index=True,
        )
        st.subheader("Itens da Nota Selecionada")
        st.caption("Dados resumidos dos itens da NF-e selecionada. Selecione um item para abrir os detalhes fiscais abaixo.")
        itens_nota = query_df(
            """
            SELECT
                "NrItem", ncm_norm, cest_norm, cfop_norm, cst_norm, gtin_norm,
                "DescItem", qtd_comercial, "UnidadeTributavel",
                vl_total_item, vl_base_calculo_icms, aliquota_icms,
                vl_aliq_uf_dest, vl_icms_uf_dest, vl_icms_fcp_uf_dest,
                vl_base_calculo_icms_st, vl_icms_st, sinais_falso_positivo_item
            FROM mart_itens_detalhe
            WHERE "IdNFe" = ?
            ORDER BY try_cast("NrItem" AS BIGINT), "NrItem"
            """,
            [selected_note["IdNFe"]],
        )
        st.caption(f"{len(itens_nota)} item(ns) encontrados para esta NF-e.")
        item_event = st.dataframe(
            itens_nota,
            use_container_width=True,
            hide_index=True,
            height=420,
            on_select="rerun",
            selection_mode="single-row",
            key=f"itens_nota_grid_{selected_note_id}",
        )
        item_rows = dataframe_selected_rows(item_event)
        if item_rows:
            selected_item = itens_nota.iloc[item_rows[0]].to_dict()
            st.session_state["selected_item_id"] = str(selected_item.get("NrItem") or "")

    if selected_item:
        st.subheader("Detalhe do Item Selecionado")
        d1, d2, d3, d4 = st.columns(4)
        d1.metric("Item", str(selected_item.get("NrItem") or ""))
        d2.metric("NCM", str(selected_item.get("ncm_norm") or ""))
        d3.metric("CFOP", str(selected_item.get("cfop_norm") or ""))
        d4.metric("DIFAL", f"R$ {float(selected_item.get('vl_icms_uf_dest') or 0):,.2f}")
        item_identity = {
            "NrItem": selected_item.get("NrItem"),
            "DescItem": selected_item.get("DescItem"),
            "NCM": selected_item.get("ncm_norm"),
            "CEST": selected_item.get("cest_norm"),
            "CFOP": selected_item.get("cfop_norm"),
            "CST": selected_item.get("cst_norm"),
            "GTIN": selected_item.get("gtin_norm"),
        }
        item_values = {
            "QtdComercial": selected_item.get("qtd_comercial"),
            "UnidadeTributavel": selected_item.get("UnidadeTributavel"),
            "ValorItem": selected_item.get("vl_total_item"),
            "BaseICMS": selected_item.get("vl_base_calculo_icms"),
            "AliquotaICMS": selected_item.get("aliquota_icms"),
            "AliquotaUFDest": selected_item.get("vl_aliq_uf_dest"),
            "DIFAL": selected_item.get("vl_icms_uf_dest"),
            "FCP": selected_item.get("vl_icms_fcp_uf_dest"),
            "BaseST": selected_item.get("vl_base_calculo_icms_st"),
            "ICMSST": selected_item.get("vl_icms_st"),
        }
        st.markdown("**IdentificaÃ§Ã£o do item**")
        st.dataframe(pd.DataFrame([item_identity]), use_container_width=True, hide_index=True)
        st.markdown("**Valores e tributaÃ§Ã£o do item**")
        st.dataframe(pd.DataFrame([item_values]), use_container_width=True, hide_index=True)
        st.markdown("**Sinais automÃ¡ticos do item**")
        st.info(str(selected_item.get("sinais_falso_positivo_item") or "Sem sinais automÃ¡ticos."))
        if can_write(user["role"]):
            revisao_comentario = st.text_input("ComentÃ¡rio da revisÃ£o sem falso positivo", key="comentario_sem_fp")
            if st.button("Marcar item como sem falso positivo", key="mark_item_sem_fp"):
                conn = get_conn()
                try:
                    timestamp = now_iso()
                    revisao_id = str(uuid.uuid4())
                    conn.execute(
                        """
                        INSERT INTO revisoes_sem_falso_positivo (
                            revisao_id, id_nfe, item_id, comentario, active, criado_por, criado_em, atualizado_em
                        )
                        VALUES (?, ?, ?, ?, TRUE, ?, ?, ?)
                        """,
                        [
                            revisao_id,
                            str(selected_note["IdNFe"] if selected_note else ""),
                            str(selected_item.get("NrItem") or ""),
                            revisao_comentario.strip(),
                            user["username"],
                            timestamp,
                            timestamp,
                        ],
                    )
                finally:
                    conn.close()
                push_undo(
                    user=user,
                    action_type="mark_no_false_positive",
                    entity_type="revisoes_sem_falso_positivo",
                    entity_id=revisao_id,
                    after_payload={
                        "id_nfe": str(selected_note["IdNFe"] if selected_note else ""),
                        "item_id": str(selected_item.get("NrItem") or ""),
                    },
                )
                st.success("Item marcado como sem falso positivo.")
                st.rerun()

    st.subheader("Regra de Falso Positivo")
    if not can_write(user["role"]):
        st.info("Seu perfil permite consulta, mas nÃ£o marcaÃ§Ã£o.")
    else:
        with st.form("marcar_falso_positivo"):
            tipo_regra = st.radio(
                "Tipo de regra",
                ["deterministica", "nao_deterministica"],
                format_func=lambda value: "deterministica" if value == "deterministica" else "nao deterministica",
                horizontal=True,
            )
            origem = st.radio("Regra associada a", ["nota", "item"], horizontal=True)
            nome_regra = st.text_input(
                "Nome da regra",
                value="Regra de falso positivo" if tipo_regra == "deterministica" else "",
            )
            descricao_regra = st.text_area("Descricao da regra")
            filtro_deterministico: dict[str, Any] | None = None
            field_options = {
                "CEST": "cest_norm",
                "NCM": "ncm_norm",
                "CFOP": "cfop_norm",
                "CST": "cst_norm",
                "GTIN": "gtin_norm",
                "Descricao": "desc_item_norm",
                "Aliquota UF destino": "vl_aliq_uf_dest",
                "Base ICMS": "vl_base_calculo_icms",
                "Valor DIFAL": "vl_icms_uf_dest",
            }
            operator_options = {
                "igual": "==",
                "diferente": "!=",
                "contem": "contains",
                "nao contem": "not_contains",
                "vazio": "is_empty",
                "nao vazio": "not_empty",
                "maior que": ">",
                "maior ou igual": ">=",
                "menor que": "<",
                "menor ou igual": "<=",
            }
            if tipo_regra == "deterministica":
                c1, c2, c3 = st.columns(3)
                campo_label = c1.selectbox("Campo", list(field_options.keys()), index=0)
                operador_label = c2.selectbox("Operador", list(operator_options.keys()), index=1)
                campo = field_options[campo_label]
                default_value = ""
                if selected_item and campo in selected_item:
                    default_value = str(selected_item.get(campo) or "")
                valor = c3.text_input("Valor", value=default_value if default_value else "0")
                filtro_deterministico = {
                    "escopo": origem,
                    "criterios": [
                        {
                            "campo": campo,
                            "campo_label": campo_label,
                            "operador": operator_options[operador_label],
                            "operador_label": operador_label,
                            "valor": valor,
                        }
                    ],
                    "id_nfe_evidencia": selected_note["IdNFe"] if selected_note else "",
                    "nr_item_evidencia": str(selected_item.get("NrItem") or "") if selected_item else "",
                }
                st.caption("Exemplo: Campo `CEST`, operador `diferente`, valor `0`.")
            motivo = st.text_area("Motivo/evidencia para a exclusao", help="Obrigatorio para auditoria e para orientar o agente futuro.")
            submitted_fp = st.form_submit_button("Incluir regra de falso positivo")
        if submitted_fp:
            if not nome_regra.strip():
                st.error("Informe o nome da regra.")
            elif not descricao_regra.strip():
                st.error("Informe a descricao da regra.")
            elif not motivo.strip():
                st.error("Informe o motivo/evidencia.")
            else:
                regra_id = ""
                conn = get_conn()
                try:
                    evidencia = (
                        f"NF-e: {selected_note['IdNFe']}; "
                        f"Item: {selected_item.get('NrItem') if selected_item else ''}; "
                        f"DIFAL nota: {float(selected_note.get('vl_icms_uf_dest') or 0):.2f}"
                    ) if selected_note else "Regra criada sem NF-e vinculada."
                    regra_id = create_rule(
                        conn,
                        tipo=tipo_regra,
                        nome=nome_regra,
                        descricao=descricao_regra.strip(),
                        usuario=user["username"],
                        filtros=filtro_deterministico if tipo_regra == "deterministica" else None,
                        hipotese_texto=descricao_regra.strip() if tipo_regra == "nao_deterministica" else None,
                        evidencia_resumo=evidencia,
                        impacto_estimado=float(selected_note.get("vl_icms_uf_dest") or 0) if selected_note else 0.0,
                        vinculo={
                            "origem": "analise_itens",
                            "tipo": "regra_falso_positivo",
                            "id_nfe": selected_note["IdNFe"] if selected_note else "",
                        },
                    )
                    push_undo(user=user, action_type="create_rule", entity_type="regras_malha", entity_id=regra_id)
                finally:
                    conn.close()

                if not selected_note:
                    st.success(f"Regra criada sem NF-e vinculada: {regra_id}")
                    st.rerun()

                marcacao_id = str(uuid.uuid4())
                item_id = str(selected_item.get("NrItem") or "") if selected_item and origem == "item" else ""
                motivo_marcacao = motivo.strip()
                agrupamento = {
                    "id_nfe": selected_note["IdNFe"],
                    "nr_doc": selected_note.get("nr_doc"),
                    "nr_item_evidencia": item_id,
                    "origem_marcacao": origem,
                    "regra_id": regra_id,
                    "tipo_regra": tipo_regra,
                    "filtro_deterministico": filtro_deterministico,
                    "ncm": str(selected_item.get("ncm_norm") or "") if selected_item else "",
                    "cfop": str(selected_item.get("cfop_norm") or "") if selected_item else "",
                    "cst": str(selected_item.get("cst_norm") or "") if selected_item else "",
                }
                conn = get_conn()
                try:
                    timestamp = now_iso()
                    conn.execute(
                        """
                        INSERT INTO marcacoes_falso_positivo (
                            marcacao_id, lote_id, escopo, cnpj_norm, item_id, agrupamento_json,
                            motivo, active, criado_por, criado_em, atualizado_em
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, TRUE, ?, ?, ?)
                        """,
                        [
                            marcacao_id,
                            str((get_active_param() or {}).get("param_id") or ""),
                            origem,
                            str(selected_note["cnpj_emit_norm"] or ""),
                            item_id,
                            json.dumps(agrupamento, ensure_ascii=False),
                            motivo_marcacao,
                            user["username"],
                            timestamp,
                            timestamp,
                        ],
                    )
                finally:
                    conn.close()
                push_undo(
                    user=user,
                    action_type="mark_false_positive",
                    entity_type="marcacoes_falso_positivo",
                    entity_id=marcacao_id,
                    after_payload={"id_nfe": selected_note["IdNFe"], "origem": origem, "regra_id": regra_id, "motivo": motivo_marcacao},
                )
                st.success(f"Regra de falso positivo criada ({regra_id}) e NF-e marcada para exclusÃ£o.")
                st.rerun()

    if st.button("Desfazer Ãºltimo ato desta sessÃ£o", key="undo_item_action"):
        try:
            undone = undo_last_action()
            st.success(f"Ato desfeito: {undone}")
            st.rerun()
        except Exception as exc:
            st.warning(str(exc))



def render_rules_panel(user: dict[str, Any], filters: dict[str, Any], metrics: pd.Series) -> None:
    role = user["role"]
    if not can_write(role):
        st.info("Seu perfil permite consulta, mas nÃ£o criaÃ§Ã£o de regras.")
    else:
        with st.form("nova_regra"):
            tipo = st.radio("Tipo de achado", ["deterministica", "nao_deterministica"], horizontal=True)
            nome = st.text_input("Nome")
            descricao = st.text_area("DescriÃ§Ã£o")
            evidencia = st.text_area("EvidÃªncia/resumo", value=f"Itens: {int(metrics['itens'])}; DIFAL destino: {float(metrics['difal_destino'] or 0):.2f}")
            impacto = st.number_input("Impacto estimado", min_value=0.0, value=float(metrics["difal_destino"] or 0), step=1000.0)
            if tipo == "deterministica":
                st.caption("Os filtros estruturados serÃ£o montados a partir dos filtros ativos da tela.")
                hipotese = None
                fonte = None
                referencia = None
            else:
                hipotese = st.text_area("HipÃ³tese nÃ£o determinÃ­stica", help="Ex.: regime especial, convÃªnio, legislaÃ§Ã£o ou exceÃ§Ã£o nÃ£o modelÃ¡vel pelos dados da NF-e.")
                fonte = st.text_input("Tipo de fonte externa")
                referencia = st.text_input("ReferÃªncia externa")
            submitted = st.form_submit_button("Criar achado")

        if submitted:
            filtros_json = {
                "ncm": filters.get("ncm") or [],
                "cest": filters.get("cest") or [],
                "cfop": filters.get("cfop") or [],
                "cst": filters.get("cst") or [],
                "gtin": filters.get("gtin") or [],
                "descricao_contains": filters.get("descricao") or "",
                "cnpj_emit": filters.get("contribuintes") or [],
                "valor_minimo": filters.get("valor_minimo") or 0,
                "periodo": {
                    "inicio": str(filters.get("data_inicio") or ""),
                    "fim": str(filters.get("data_fim") or ""),
                },
            }
            conn = get_conn()
            try:
                regra_id = create_rule(
                    conn,
                    tipo=tipo,
                    nome=nome,
                    descricao=descricao,
                    usuario=user["username"],
                    filtros=filtros_json if tipo == "deterministica" else None,
                    hipotese_texto=hipotese,
                    fonte_externa_tipo=fonte,
                    referencia_externa=referencia,
                    evidencia_resumo=evidencia,
                    impacto_estimado=impacto,
                    vinculo={"origem": "analise_itens"},
                )
                push_undo(user=user, action_type="create_rule", entity_type="regras_malha", entity_id=regra_id)
                st.success(f"Achado criado: {regra_id}")
            except Exception as exc:
                st.error(str(exc))
            finally:
                conn.close()

    rules = query_df(
        """
        SELECT regra_id, tipo, nome, status, impacto_estimado, criado_por, criado_em, descricao,
               fonte_externa_tipo, referencia_externa
        FROM regras_malha
        ORDER BY criado_em DESC
        LIMIT 200
        """
    )
    st.dataframe(rules, use_container_width=True)

    if can_admin(role) and not rules.empty:
        st.subheader("Alterar status")
        regra_id = st.selectbox("Regra", rules["regra_id"].tolist())
        status = st.selectbox("Novo status", ["candidata", "em_teste", "aprovada", "rejeitada", "arquivada", "suspensa", "excluida_logica"])
        comentario = st.text_input("ComentÃ¡rio")
        if st.button("Salvar status"):
            conn = get_conn()
            try:
                previous = rules[rules["regra_id"] == regra_id].iloc[0].to_dict()
                update_rule_status(conn, regra_id=regra_id, status=status, usuario=user["username"], comentario=comentario)
                push_undo(
                    user=user,
                    action_type="update_rule_status",
                    entity_type="regras_malha",
                    entity_id=regra_id,
                    before_payload={"status": previous["status"]},
                    after_payload={"status": status},
                )
                st.success("Status atualizado.")
                st.rerun()
            finally:
                conn.close()


def render_dashboard() -> None:
    st.title("Painel da Malha")
    active_param = get_active_param()
    top_limit = int((active_param or {}).get("top_n") or 50)
    st.caption(f"Exibindo top {top_limit} conforme parÃ¢metro de lote ativo." if active_param else "Exibindo top 50 porque nÃ£o hÃ¡ parÃ¢metro de lote ativo.")
    tables = ["mart_casos_malha", "mart_itens_detalhe", "regras_malha"]
    cols = st.columns(len(tables))
    for col, table in zip(cols, tables):
        try:
            qtd = query_df(f"SELECT count(*) AS qtd FROM {table}")["qtd"].iloc[0]
            col.metric(table, f"{int(qtd):,}".replace(",", "."))
        except Exception:
            col.metric(table, "indisponÃ­vel")

    conn = get_conn()
    try:
        has_cases = table_exists(conn, "mart_casos_malha")
    finally:
        conn.close()
    if has_cases:
        st.subheader("Maiores potenciais")
        top = query_df(
            """
            SELECT cnpj_norm, nome_pessoa, difal_nfe, difal_gia, valor_recolhido,
                   potencial_arrecadacao, status_triagem, sinais_falso_positivo
            FROM mart_casos_malha
            ORDER BY potencial_arrecadacao DESC
            LIMIT ?
            """,
            [top_limit],
        )
        st.dataframe(top, use_container_width=True)


def get_active_param() -> dict[str, Any] | None:
    frame = query_df(
        """
        SELECT param_id, nome, descricao, top_n, potencial_minimo, status_triagem_json,
               incluir_com_recolhimento, incluir_baixados, filtros_json
        FROM param_lotes
        WHERE ativo = TRUE
        ORDER BY atualizado_em DESC
        LIMIT 1
        """
    )
    if frame.empty:
        return None
    return frame.iloc[0].to_dict()


def set_param_active(user: dict[str, Any], param_id: str, active: bool) -> None:
    current = query_df("SELECT param_id, ativo FROM param_lotes WHERE param_id = ?", [param_id])
    before_active = bool(current["ativo"].iloc[0]) if not current.empty else None
    timestamp = now_iso()
    conn = get_conn()
    try:
        if active:
            conn.execute("UPDATE param_lotes SET ativo = FALSE, atualizado_em = ?", [timestamp])
        conn.execute("UPDATE param_lotes SET ativo = ?, atualizado_em = ? WHERE param_id = ?", [bool(active), timestamp, param_id])
    finally:
        conn.close()
    push_undo(
        user=user,
        action_type="set_param_active",
        entity_type="param_lotes",
        entity_id=param_id,
        before_payload={"ativo": before_active},
        after_payload={"ativo": bool(active)},
    )


def get_excluded_cnpjs() -> list[str]:
    conn = get_conn()
    try:
        fp = conn.execute(
            """
            SELECT DISTINCT cnpj_norm
            FROM marcacoes_falso_positivo
            WHERE active = TRUE AND escopo = 'empresa' AND coalesce(cnpj_norm, '') <> ''
            """
        ).df()
        approved = conn.execute(
            """
            SELECT DISTINCT c.cnpj_norm
            FROM lote_autorregularizacao_casos c
            INNER JOIN lotes_autorregularizacao l ON c.lote_id = l.lote_id
            WHERE l.status = 'aprovado' AND coalesce(c.cnpj_norm, '') <> ''
            """
        ).df()
    finally:
        conn.close()
    values = pd.concat([fp, approved], ignore_index=True) if not fp.empty or not approved.empty else pd.DataFrame(columns=["cnpj_norm"])
    return sorted(values["cnpj_norm"].dropna().astype(str).unique().tolist())


def current_item_lote_stats() -> dict[str, Any]:
    if not ensure_item_tables():
        return {"empresas": 0, "empresas_validas": 0, "itens": 0, "potencial": 0.0}
    stats = query_df(
        """
        WITH fp AS (
            SELECT DISTINCT json_extract_string(agrupamento_json, '$.id_nfe') AS id_nfe
            FROM marcacoes_falso_positivo
            WHERE active = TRUE AND escopo = 'nota'
        )
        SELECT
            count(*) FILTER (WHERE fp.id_nfe IS NULL) AS itens,
            count(DISTINCT cnpj_emit_norm) FILTER (WHERE fp.id_nfe IS NULL) AS empresas,
            count(DISTINCT cnpj_emit_norm) FILTER (WHERE fp.id_nfe IS NULL) AS empresas_validas,
            sum(coalesce(vl_icms_uf_dest, 0)) FILTER (WHERE fp.id_nfe IS NULL) AS potencial
        FROM mart_itens_detalhe i
        LEFT JOIN fp ON i."IdNFe" = fp.id_nfe
        """
    )
    return stats.iloc[0].to_dict() if not stats.empty else {"empresas": 0, "empresas_validas": 0, "itens": 0, "potencial": 0.0}


def load_items_for_active_lote(
    user: dict[str, Any],
    active_param: dict[str, Any],
    progress_callback: Any | None = None,
) -> dict[str, Any]:
    param_id = str(active_param["param_id"])
    top_n = int(active_param.get("top_n") or 20)
    output_path = ROOT / "tb_nfe" / "outputs" / f"tb_nfe_itens_lote_{param_id}.xlsx"
    tb_nfe_dir = ROOT / "tb_nfe"
    if str(tb_nfe_dir) not in sys.path:
        sys.path.insert(0, str(tb_nfe_dir))
    from download_tb_nfe_itens_top import run_items_top_export

    import load_malhas_db as loader

    extract_summary = run_items_top_export(
        potential_path=TB_NFE_PATH,
        top_n=top_n,
        output_path=output_path,
        exclude_cnpjs=get_excluded_cnpjs(),
        quiet=True,
        progress_callback=progress_callback,
    )

    conn = get_conn()
    load_result: dict[str, Any]
    quality_rows: list[dict[str, Any]]
    loader_spec = replace(loader.SOURCES["tbNFeItens"], default_file=output_path)
    loader.create_control_tables(conn)
    load_result = loader.load_source(conn, loader_spec, output_path)
    loader.rebuild_staging_tables(conn)
    loader.rebuild_marts(conn)
    quality_rows = loader.run_quality_checks(conn)
    if progress_callback:
        progress_callback({"stage": "load_duckdb", "progress": 0.99, "message": "DuckDB carregado; marts e checks reconstruÃ­dos."})
    if load_result.get("status") != "ok":
        raise RuntimeError(json.dumps(load_result, ensure_ascii=False, default=str))

    stats = current_item_lote_stats()
    run_id = str(uuid.uuid4())
    conn = get_conn()
    try:
        conn.execute(
            """
            INSERT INTO item_analysis_runs (run_id, lote_id, status, source_file, rows_loaded, criado_por, criado_em, detalhes)
            VALUES (?, ?, 'ok', ?, ?, ?, ?, ?)
            """,
            [
                run_id,
                param_id,
                str(output_path),
                int(stats.get("itens") or 0),
                user["username"],
                now_iso(),
                json.dumps(
                    {
                        "extract_summary": extract_summary,
                        "load_result": load_result,
                        "quality_checks": quality_rows,
                    },
                    ensure_ascii=False,
                    default=str,
                ),
            ],
        )
    finally:
        conn.close()
    if progress_callback:
        progress_callback({"stage": "done", "progress": 1.0, "message": "Carga de itens finalizada."})
    return {"run_id": run_id, "output_path": str(output_path), **stats}


def approve_current_lote(user: dict[str, Any], active_param: dict[str, Any]) -> str:
    if not ensure_item_tables():
        raise ValueError("Nao ha itens carregados para aprovar.")
    lote_id = str(uuid.uuid4())
    timestamp = now_iso()
    valid_cases = query_df(
        """
        WITH fp AS (
            SELECT DISTINCT json_extract_string(agrupamento_json, '$.id_nfe') AS id_nfe
            FROM marcacoes_falso_positivo
            WHERE active = TRUE AND escopo = 'nota'
        )
        SELECT
            cnpj_emit_norm AS cnpj_norm,
            any_value("NmEmit") AS nome_pessoa,
            sum(coalesce(vl_icms_uf_dest, 0)) AS potencial_arrecadacao
        FROM mart_itens_detalhe i
        LEFT JOIN fp ON i."IdNFe" = fp.id_nfe
        WHERE fp.id_nfe IS NULL
        GROUP BY cnpj_emit_norm
        ORDER BY potencial_arrecadacao DESC
        """
    )
    if valid_cases.empty:
        raise ValueError("Nao ha empresas validas para aprovar.")
    conn = get_conn()
    try:
        conn.execute(
            """
            INSERT INTO lotes_autorregularizacao (
                lote_id, param_id, nome, descricao, status, qtd_casos, potencial_total,
                criado_por, criado_em, atualizado_em
            )
            VALUES (?, ?, ?, ?, 'aprovado', ?, ?, ?, ?, ?)
            """,
            [
                lote_id,
                str(active_param["param_id"]),
                f"Lote autorregularizacao {timestamp}",
                active_param.get("descricao"),
                len(valid_cases),
                float(valid_cases["potencial_arrecadacao"].fillna(0).sum()),
                user["username"],
                timestamp,
                timestamp,
            ],
        )
        for row in valid_cases.to_dict("records"):
            conn.execute(
                """
                INSERT INTO lote_autorregularizacao_casos (
                    lote_id, cnpj_norm, nome_pessoa, potencial_arrecadacao, difal_nfe,
                    difal_gia, valor_recolhido, status_triagem, criado_em
                )
                VALUES (?, ?, ?, ?, NULL, NULL, NULL, NULL, ?)
                """,
                [lote_id, row["cnpj_norm"], row["nome_pessoa"], float(row["potencial_arrecadacao"] or 0), timestamp],
            )
    finally:
        conn.close()
    push_undo(user=user, action_type="approve_lote", entity_type="lote_autorregularizacao", entity_id=lote_id)
    return lote_id


def render_admin(user: dict[str, Any]) -> None:
    st.title("AdministraÃ§Ã£o")
    st.caption("Ãrea do administrador para operar usuÃ¡rios, parÃ¢metros de lote, regras e diagnÃ³stico do banco.")

    tabs = st.tabs(["UsuÃ¡rios", "ParÃ¢metros de Lote", "Regras", "DiagnÃ³stico"])

    with tabs[0]:
        st.subheader("UsuÃ¡rios")
        users = query_df(
            """
            SELECT username, role, active, created_at, updated_at
            FROM app_users
            ORDER BY username
            """
        )
        st.dataframe(users, use_container_width=True)

        with st.form("admin_user_form"):
            st.markdown("**Criar ou atualizar usuÃ¡rio**")
            username = st.text_input("UsuÃ¡rio", key="admin_username")
            role = st.selectbox("Perfil", ["analista", "leitor", "admin"], key="admin_role")
            password = st.text_input("Senha", type="password", key="admin_password")
            active = st.checkbox("Ativo", value=True, key="admin_active")
            submitted = st.form_submit_button("Salvar usuÃ¡rio")

        if submitted:
            if not username.strip() or not password:
                st.error("Informe usuÃ¡rio e senha.")
            else:
                conn = get_conn()
                try:
                    create_or_update_user(
                        conn,
                        username=username.strip(),
                        password=password,
                        role=role,
                        active=active,
                    )
                    st.success("UsuÃ¡rio salvo.")
                    st.rerun()
                except Exception as exc:
                    st.error(str(exc))
                finally:
                    conn.close()

    with tabs[1]:
        st.subheader("ParÃ¢metros de Lote")
        params = query_df(
            """
            SELECT param_id, nome, ativo, top_n, potencial_minimo, status_triagem_json,
                   incluir_com_recolhimento, incluir_baixados, criado_por, criado_em, atualizado_em
            FROM param_lotes
            ORDER BY criado_em DESC
            """
        )
        st.dataframe(params, use_container_width=True)

        active_param = get_active_param()
        stats = current_item_lote_stats()
        st.markdown("**OperaÃ§Ã£o do lote ativo**")
        if active_param:
            c1, c2, c3, c4 = st.columns(4)
            c1.metric("ParÃ¢metro", str(active_param["nome"]))
            c2.metric("Top alvo", int(active_param.get("top_n") or 0))
            c3.metric("Empresas vÃ¡lidas", int(stats.get("empresas_validas") or 0))
            c4.metric("Itens carregados", int(stats.get("itens") or 0))
            st.caption(f"CNPJs excluÃ­dos do prÃ³ximo carregamento: {len(get_excluded_cnpjs())}")
        else:
            st.warning("Nenhum parÃ¢metro ativo. Ative um parÃ¢metro existente ou crie um novo marcado como ativo.")

        op1, op2, op3 = st.columns(3)
        if op1.button("Carregar / recarregar itens", type="primary", disabled=active_param is None):
            progress_bar = st.progress(0)
            status_box = st.empty()
            log_box = st.empty()
            progress_messages: list[str] = []

            def update_progress(event: dict[str, Any]) -> None:
                progress = max(0.0, min(1.0, float(event.get("progress") or 0)))
                message = str(event.get("message") or event.get("stage") or "")
                progress_bar.progress(progress, text=f"{int(progress * 100)}%")
                status_box.info(message)
                if message:
                    progress_messages.append(message)
                    log_box.code("\n".join(progress_messages[-8:]), language="text")

            with st.spinner("Extraindo itens dos tops selecionados e recarregando o DuckDB..."):
                try:
                    update_progress({"stage": "start", "progress": 0.0, "message": "Iniciando carga de itens."})
                    result = load_items_for_active_lote(user, active_param, progress_callback=update_progress)
                    update_progress({"stage": "done", "progress": 1.0, "message": "Carga finalizada."})
                    st.success(f"Itens carregados: {int(result.get('itens') or 0)} | arquivo: {result['output_path']}")
                    st.rerun()
                except Exception as exc:
                    status_box.error("Falha na carga de itens.")
                    st.error(str(exc))
        lote_completo = bool(active_param) and int(stats.get("empresas_validas") or 0) >= int(active_param.get("top_n") or 0) > 0
        if op2.button("Marcar lote como autorregularizaÃ§Ã£o", disabled=not lote_completo):
            try:
                lote_id = approve_current_lote(user, active_param)
                st.success(f"Lote aprovado: {lote_id}")
                st.rerun()
            except Exception as exc:
                st.error(str(exc))
        if op3.button("Desfazer Ãºltimo ato desta sessÃ£o", key="undo_lote_operacao"):
            try:
                undone = undo_last_action()
                st.success(f"Ato desfeito: {undone}")
                st.rerun()
            except Exception as exc:
                st.warning(str(exc))

        if not params.empty:
            st.markdown("**Administrar parÃ¢metro existente**")
            param_labels = {
                f"{row['nome']} | top {row['top_n']} | {'ativo' if bool(row['ativo']) else 'inativo'}": row["param_id"]
                for row in params.to_dict("records")
            }
            selected_param_label = st.selectbox("ParÃ¢metro", list(param_labels.keys()), key="admin_param_select")
            selected_param_id = str(param_labels[selected_param_label])
            selected_param = params[params["param_id"].astype(str) == selected_param_id].iloc[0].to_dict()
            p1, p2, p3 = st.columns(3)
            if p1.button("Ativar parÃ¢metro selecionado", disabled=bool(selected_param["ativo"])):
                set_param_active(user, selected_param_id, True)
                st.success("ParÃ¢metro ativado.")
                st.rerun()
            if p2.button("Desativar parÃ¢metro selecionado", disabled=not bool(selected_param["ativo"])):
                set_param_active(user, selected_param_id, False)
                st.success("ParÃ¢metro desativado.")
                st.rerun()
            if p3.button("Excluir parÃ¢metro selecionado"):
                selected_param_payload = {
                    "param_id": selected_param_id,
                    "nome": str(selected_param.get("nome") or ""),
                    "descricao": str(selected_param.get("descricao") or ""),
                    "ativo": bool(selected_param.get("ativo")),
                    "top_n": int(selected_param.get("top_n") or 0),
                    "potencial_minimo": float(selected_param.get("potencial_minimo") or 0),
                    "status_triagem_json": str(selected_param.get("status_triagem_json") or "[]"),
                    "incluir_com_recolhimento": bool(selected_param.get("incluir_com_recolhimento")),
                    "incluir_baixados": bool(selected_param.get("incluir_baixados")),
                    "filtros_json": str(selected_param.get("filtros_json") or "{}"),
                    "criado_por": str(selected_param.get("criado_por") or user["username"]),
                    "criado_em": str(selected_param.get("criado_em") or now_iso()),
                }
                conn = get_conn()
                try:
                    conn.execute("DELETE FROM param_lotes WHERE param_id = ?", [selected_param_id])
                finally:
                    conn.close()
                push_undo(
                    user=user,
                    action_type="delete_param",
                    entity_type="param_lotes",
                    entity_id=selected_param_id,
                    before_payload=selected_param_payload,
                )
                st.success("ParÃ¢metro excluÃ­do.")
                st.rerun()

        if st.button("Desfazer Ãºltimo ato desta sessÃ£o", key="undo_admin_params"):
            try:
                undone = undo_last_action()
                st.success(f"Ato desfeito: {undone}")
                st.rerun()
            except Exception as exc:
                st.warning(str(exc))

        with st.form("param_lote_form"):
            st.markdown("**Novo conjunto de parÃ¢metros**")
            nome = st.text_input("Nome do parÃ¢metro", value="Maiores potenciais para revisÃ£o")
            descricao = st.text_area("DescriÃ§Ã£o", value="CritÃ©rios usados para formar lote exploratÃ³rio de autorregularizaÃ§Ã£o.")
            top_n = st.number_input("Top N casos", min_value=1, value=500, step=50)
            potencial_minimo = st.number_input("Potencial mÃ­nimo", min_value=0.0, value=0.0, step=1000.0)
            status_triagem = st.multiselect(
                "Status de triagem incluÃ­dos",
                ["priorizar", "revisar_chave", "revisar_cadastro", "revisar_recolhimento", "sem_potencial_aparente"],
                default=["priorizar", "revisar_chave", "revisar_cadastro"],
            )
            incluir_com_recolhimento = st.checkbox("Incluir casos com recolhimento existente", value=True)
            incluir_baixados = st.checkbox("Incluir contribuintes baixados", value=False)
            filtros_json_raw = st.text_area("Filtros adicionais em JSON", value="{}")
            ativo = st.checkbox("Marcar como parÃ¢metro ativo", value=True)
            submitted = st.form_submit_button("Salvar parÃ¢metro")

        if submitted:
            try:
                filtros_json = safe_json_loads(filtros_json_raw, {})
                timestamp = now_iso()
                param_id = str(uuid.uuid4())
                conn = get_conn()
                try:
                    if ativo:
                        conn.execute("UPDATE param_lotes SET ativo = FALSE, atualizado_em = ?", [timestamp])
                    conn.execute(
                        """
                        INSERT INTO param_lotes (
                            param_id, nome, descricao, top_n, potencial_minimo, status_triagem_json,
                            incluir_com_recolhimento, incluir_baixados, filtros_json, ativo,
                            criado_por, criado_em, atualizado_em
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        [
                            param_id,
                            nome,
                            descricao,
                            int(top_n),
                            float(potencial_minimo),
                            json.dumps(status_triagem, ensure_ascii=False),
                            bool(incluir_com_recolhimento),
                            bool(incluir_baixados),
                            json.dumps(filtros_json, ensure_ascii=False),
                            bool(ativo),
                            user["username"],
                            timestamp,
                            timestamp,
                        ],
                    )
                    push_undo(
                        user=user,
                        action_type="create_param",
                        entity_type="param_lotes",
                        entity_id=param_id,
                        after_payload={"nome": nome, "top_n": int(top_n), "ativo": bool(ativo)},
                    )
                    st.success("ParÃ¢metro salvo.")
                    st.rerun()
                finally:
                    conn.close()
            except Exception as exc:
                st.error(str(exc))

    with tabs[2]:
        st.subheader("Regras e HipÃ³teses")
        rules = query_df(
            """
            SELECT regra_id, tipo, nome, status, impacto_estimado, criado_por, criado_em,
                   atualizado_em, descricao, fonte_externa_tipo, referencia_externa
            FROM regras_malha
            ORDER BY criado_em DESC
            """
        )
        if rules.empty:
            st.info("Ainda nÃ£o hÃ¡ regras ou hipÃ³teses cadastradas.")
        else:
            col1, col2 = st.columns(2)
            tipos = ["todos"] + sorted(rules["tipo"].dropna().unique().tolist())
            statuses = ["todos"] + sorted(rules["status"].dropna().unique().tolist())
            tipo_filter = col1.selectbox("Filtrar tipo", tipos)
            status_filter = col2.selectbox("Filtrar status", statuses)
            visible = rules.copy()
            if tipo_filter != "todos":
                visible = visible[visible["tipo"] == tipo_filter]
            if status_filter != "todos":
                visible = visible[visible["status"] == status_filter]
            st.dataframe(visible, use_container_width=True)

            regra_id = st.selectbox("Regra para administrar", rules["regra_id"].tolist())
            selected = rules[rules["regra_id"] == regra_id].iloc[0]
            st.write(selected[["nome", "tipo", "status", "impacto_estimado", "descricao"]])

            r1, r2, r3 = st.columns(3)
            direct_rule_action = None
            if r1.button("Ativar regra", disabled=str(selected["status"]) == "aprovada"):
                direct_rule_action = ("aprovada", "Regra ativada pelo administrador.")
            if r2.button("Suspender regra", disabled=str(selected["status"]) == "suspensa"):
                direct_rule_action = ("suspensa", "Regra suspensa pelo administrador.")
            if r3.button("Excluir regra", disabled=str(selected["status"]) == "excluida_logica"):
                direct_rule_action = ("excluida_logica", "Regra excluÃ­da logicamente pelo administrador.")

            if direct_rule_action:
                new_status, default_comment = direct_rule_action
                conn = get_conn()
                try:
                    previous_status = str(selected["status"])
                    update_rule_status(
                        conn,
                        regra_id=regra_id,
                        status=new_status,
                        usuario=user["username"],
                        comentario=default_comment,
                    )
                    push_undo(
                        user=user,
                        action_type="update_rule_status",
                        entity_type="regras_malha",
                        entity_id=regra_id,
                        before_payload={"status": previous_status},
                        after_payload={"status": new_status},
                    )
                    st.success(default_comment)
                    st.rerun()
                finally:
                    conn.close()

            eventos = query_df(
                """
                SELECT usuario, acao, comentario, criado_em
                FROM regra_eventos
                WHERE regra_id = ?
                ORDER BY criado_em DESC
                """,
                [regra_id],
            )
            st.dataframe(eventos, use_container_width=True)

            with st.form("admin_rule_status_form"):
                status = st.selectbox("Novo status", ["candidata", "em_teste", "aprovada", "rejeitada", "arquivada", "suspensa", "excluida_logica"])
                comentario = st.text_input("ComentÃ¡rio administrativo")
                submitted = st.form_submit_button("Atualizar regra")

            if submitted:
                conn = get_conn()
                try:
                    previous_status = str(selected["status"])
                    update_rule_status(
                        conn,
                        regra_id=regra_id,
                        status=status,
                        usuario=user["username"],
                        comentario=comentario,
                    )
                    push_undo(
                        user=user,
                        action_type="update_rule_status",
                        entity_type="regras_malha",
                        entity_id=regra_id,
                        before_payload={"status": previous_status},
                        after_payload={"status": status},
                    )
                    st.success("Regra atualizada.")
                    st.rerun()
                finally:
                    conn.close()

    with tabs[3]:
        st.subheader("DiagnÃ³stico")
        check_tables = [
            "mart_casos_malha",
            "mart_potencial_arrecadacao",
            "raw_tbNFeItens",
            "stg_tbNFeItens",
            "mart_itens_detalhe",
            "mart_itens_por_ncm_cfop_cst",
            "mart_itens_por_descricao",
            "mart_itens_por_emitente",
            "mart_sinais_falso_positivo_itens",
            "regras_malha",
            "regra_eventos",
            "marcacoes_falso_positivo",
            "admin_action_events",
            "lotes_autorregularizacao",
            "lote_autorregularizacao_casos",
            "app_users",
            "param_lotes",
        ]
        rows: list[dict[str, Any]] = []
        conn = get_conn()
        try:
            for table in check_tables:
                exists = table_exists(conn, table)
                count = None
                if exists:
                    count = conn.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
                rows.append({"tabela": table, "existe": exists, "linhas": count})
        finally:
            conn.close()

        diag = pd.DataFrame(rows)
        st.dataframe(diag, use_container_width=True)
        itens_row = diag[diag["tabela"] == "mart_itens_detalhe"]
        if not itens_row.empty and int(itens_row["linhas"].fillna(0).iloc[0]) == 0:
            st.warning("A tela de itens estÃ¡ disponÃ­vel, mas ainda nÃ£o hÃ¡ itens carregados em `raw_tbNFeItens`.")
        st.code(str(Path(st.session_state.get("db_path", DEFAULT_DB_PATH))), language="text")


def main() -> None:
    user = require_login()
    if not user:
        return
    ensure_session_state()

    pages = ["Painel", "AnÃ¡lise de Itens"]
    if can_admin(user["role"]):
        pages.append("AdministraÃ§Ã£o")

    page = st.sidebar.radio("NavegaÃ§Ã£o", pages)
    if page == "Painel":
        render_dashboard()
    elif page == "AnÃ¡lise de Itens":
        render_item_analysis(user)
    else:
        render_admin(user)


if __name__ == "__main__":
    main()
