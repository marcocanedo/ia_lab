from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from mstrio.connection import Connection


WORKSPACE_ROOT = Path(__file__).resolve().parents[1]
load_dotenv(WORKSPACE_ROOT / ".env", override=False)

DEFAULT_USER_AGENT = os.getenv(
    "MSTR_USER_AGENT",
    (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/126.0.0.0 Safari/537.36"
    ),
)
_CONNECTION_SESSION_PATCHED = False


def _patch_connection_session_headers() -> None:
    global _CONNECTION_SESSION_PATCHED
    if _CONNECTION_SESSION_PATCHED:
        return

    original_configure_session = Connection._Connection__configure_session

    def patched_configure_session(
        self,
        verify,
        certificate_path,
        proxies,
        existing_session=None,
        retries=2,
        backoff_factor=0.3,
    ):
        session = original_configure_session(
            self,
            verify,
            certificate_path,
            proxies,
            existing_session,
            retries,
            backoff_factor,
        )
        session.headers.update(
            {
                "User-Agent": DEFAULT_USER_AGENT,
                "Accept": "application/json, text/plain, */*",
            }
        )
        return session

    Connection._Connection__configure_session = patched_configure_session
    _CONNECTION_SESSION_PATCHED = True


_patch_connection_session_headers()


def _normalize_base_url(base_url: str) -> str:
    normalized = base_url.strip().rstrip("/")
    lowered = normalized.lower()
    for suffix in ("/api", "/app", "/servlet/mstrweb"):
        if lowered.endswith(suffix):
            normalized = normalized[: -len(suffix)].rstrip("/")
            break
    return normalized


def _normalize_api_url(base_url: str) -> str:
    return f"{_normalize_base_url(base_url)}/api"


@dataclass(frozen=True)
class MicroStrategyConfig:
    base_url: str
    username: str | None = None
    password: str | None = None
    login_mode: int = 1
    project_id: str | None = None
    verify_tls: bool = True
    timeout: int = 30

    @property
    def api_url(self) -> str:
        return _normalize_api_url(self.base_url)


def load_config() -> MicroStrategyConfig:
    raw_base_url = (
        os.getenv("MSTR_BASE_URL")
        or os.getenv("MSTR_LIBRARY_URL")
        or os.getenv("MSTR_WEB_URL")
        or "https://bi.sefa.pr.gov.br/SEFAPRODLIB"
    )
    return MicroStrategyConfig(
        base_url=raw_base_url,
        username=os.getenv("MSTR_USERNAME") or None,
        password=os.getenv("MSTR_PASSWORD") or None,
        login_mode=int(os.getenv("MSTR_LOGIN_MODE", "1")),
        project_id=os.getenv("MSTR_PROJECT_ID") or None,
        verify_tls=os.getenv("MSTR_VERIFY_TLS", "1") != "0",
        timeout=int(os.getenv("MSTR_TIMEOUT", "30")),
    )


def normalize_api_path(path: str) -> str:
    normalized = "/" + str(path or "").strip().lstrip("/")
    normalized = normalized.replace("//", "/")
    if normalized == "/":
        return "/api"
    if not normalized.startswith("/api/"):
        normalized = "/api" + normalized
    return normalized


class MicroStrategyRestClient:
    def __init__(self, config: MicroStrategyConfig | None = None) -> None:
        self.config = config or load_config()
        self.connection: Connection | None = None

    @property
    def session(self) -> Any:
        if self.connection is None:
            raise RuntimeError("Autentique com login() antes de acessar a sessao.")
        return self.connection._session

    @property
    def project_id(self) -> str | None:
        if self.connection is None:
            return self.config.project_id
        return getattr(self.connection, "project_id", None) or self.config.project_id

    def _require_connection(self) -> Connection:
        if self.connection is None:
            raise RuntimeError("Autentique com login() antes de executar requests.")
        return self.connection

    def login(self) -> str:
        if not self.config.username or not self.config.password:
            raise ValueError("Preencha MSTR_USERNAME e MSTR_PASSWORD no .env para autenticar.")

        self.connection = Connection(
            base_url=self.config.api_url,
            username=self.config.username,
            password=self.config.password,
            project_id=self.config.project_id,
            login_mode=self.config.login_mode,
            ssl_verify=self.config.verify_tls,
            verbose=False,
            request_timeout=self.config.timeout,
        )
        return str(getattr(self.connection, "token", "") or "")

    def select_project(
        self,
        project: Any | None = None,
        project_id: str | None = None,
        project_name: str | None = None,
    ) -> None:
        connection = self._require_connection()
        connection.select_project(project=project, project_id=project_id, project_name=project_name)

    def request(self, method: str, path: str, **kwargs: Any):
        connection = self._require_connection()
        normalized = normalize_api_path(path)
        timeout = kwargs.pop("timeout", None)
        verify = kwargs.pop("verify", None)
        if timeout is not None:
            original_timeout = connection.request_timeout
            connection.set_request_timeout(timeout)
        else:
            original_timeout = None
        if verify is not None:
            connection._session.verify = verify

        try:
            method_name = method.upper()
            method_fn = getattr(connection, method_name.lower())
            return method_fn(endpoint=normalized, **kwargs)
        finally:
            if original_timeout is not None:
                connection.set_request_timeout(original_timeout)

    def get(self, path: str, **kwargs: Any):
        return self.request("GET", path, **kwargs)

    def head(self, path: str, **kwargs: Any):
        return self.request("HEAD", path, **kwargs)

    def post(self, path: str, **kwargs: Any):
        return self.request("POST", path, **kwargs)

    def put(self, path: str, **kwargs: Any):
        return self.request("PUT", path, **kwargs)

    def patch(self, path: str, **kwargs: Any):
        return self.request("PATCH", path, **kwargs)

    def delete(self, path: str, **kwargs: Any):
        return self.request("DELETE", path, **kwargs)

    def logout(self) -> None:
        if self.connection is None:
            return
        try:
            self.connection.close()
        finally:
            self.connection = None

    def close(self) -> None:
        self.logout()

    def list_projects(self) -> list[dict[str, Any]]:
        response = self.get("/api/projects")
        response.raise_for_status()
        data = response.json()
        return data if isinstance(data, list) else data.get("projects", [])

    def session_info(self) -> dict[str, Any]:
        response = self.get("/api/sessions")
        response.raise_for_status()
        return response.json()

    def status(self) -> bool:
        if self.connection is None:
            raise RuntimeError("Autentique com login() antes de consultar o status.")
        return bool(self.connection.status())
