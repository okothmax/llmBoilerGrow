import logging
import os
import sqlite3
import uuid
from contextlib import contextmanager
from datetime import datetime
from typing import Optional

import inngest
import inngest.flask
from flask import Flask, abort, jsonify, request
from pydantic import BaseModel, ValidationError, constr


app = Flask(__name__)


def _is_containerised() -> bool:
    """Detect whether the app is running inside a container."""

    checks = [
        "/var/run/secrets/kubernetes.io/serviceaccount/namespace",
        "/.dockerenv",
    ]
    if any(os.path.exists(check) for check in checks):
        return True

    cgroup_path = "/proc/self/cgroup"
    if os.path.isfile(cgroup_path):
        with open(cgroup_path, "r", encoding="utf-8") as handle:
            lines = handle.readlines()
        return any("kubepods" in line or "docker" in line for line in lines)

    return False


IS_CONTAINER = _is_containerised()


def _resolve_default_ollama_base() -> str:
    if IS_CONTAINER:
        return "http://ollama.ollama.svc.cluster.local:11434/v1"
    return "http://localhost:11434/v1"


OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", _resolve_default_ollama_base())
AGENT_RESULT_TOKEN = os.getenv("AGENT_RESULT_TOKEN", "dev-token")
DATABASE_PATH = os.getenv("AGENT_DB_PATH", os.path.join("/tmp", "agent_requests.db"))


def _ensure_db_path() -> None:
    os.makedirs(os.path.dirname(DATABASE_PATH), exist_ok=True)


_ensure_db_path()


@contextmanager
def get_db_connection():
    conn = sqlite3.connect(DATABASE_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()


def init_db() -> None:
    with get_db_connection() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS agent_requests (
                request_id TEXT PRIMARY KEY,
                prompt TEXT NOT NULL,
                context TEXT,
                status TEXT NOT NULL,
                result TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )
        conn.commit()


init_db()


class AgentRequestPayload(BaseModel):
    prompt: constr(strip_whitespace=True, min_length=1)  # type: ignore[valid-type]
    context: Optional[constr(strip_whitespace=True, min_length=1)] = None  # type: ignore[valid-type]


class AgentResultPayload(BaseModel):
    request_id: constr(strip_whitespace=True, min_length=1)  # type: ignore[valid-type]
    status: constr(strip_whitespace=True, min_length=1)  # type: ignore[valid-type]
    result: Optional[str] = None


def _record_to_dict(row: sqlite3.Row) -> dict:
    return {
        "request_id": row["request_id"],
        "prompt": row["prompt"],
        "context": row["context"],
        "status": row["status"],
        "result": row["result"],
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
    }


def _insert_request(request_id: str, prompt: str, context_value: Optional[str]) -> None:
    timestamp = datetime.utcnow().isoformat()
    with get_db_connection() as conn:
        conn.execute(
            """
            INSERT INTO agent_requests (request_id, prompt, context, status, result, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (request_id, prompt, context_value, "queued", None, timestamp, timestamp),
        )
        conn.commit()


def _update_request_status(request_id: str, status: str, result: Optional[str] = None) -> bool:
    timestamp = datetime.utcnow().isoformat()
    with get_db_connection() as conn:
        cursor = conn.execute(
            """
            UPDATE agent_requests
            SET status = ?, result = ?, updated_at = ?
            WHERE request_id = ?
            """,
            (status, result, timestamp, request_id),
        )
        conn.commit()
        return cursor.rowcount > 0


def _fetch_request(request_id: str) -> Optional[dict]:
    with get_db_connection() as conn:
        cursor = conn.execute(
            "SELECT * FROM agent_requests WHERE request_id = ?", (request_id,)
        )
        row = cursor.fetchone()
        return _record_to_dict(row) if row else None


logger = logging.getLogger("flask.app")

inngest_kwargs = {
    "app_id": os.getenv("INNGEST_APP_ID", "flask_agent_app"),
    "logger": logger,
}

signing_key = os.getenv("INNGEST_SIGNING_KEY")
if signing_key:
    inngest_kwargs["signing_key"] = signing_key


inngest_client = inngest.Inngest(**inngest_kwargs)


@app.route("/healthz", methods=["GET"])
def health_check():
    return jsonify({"status": "ok"})


@app.route("/api/agent", methods=["POST"])
def create_agent_request():
    try:
        payload = AgentRequestPayload.model_validate(request.get_json(force=True))
    except ValidationError as exc:
        return jsonify({"message": "Invalid request payload", "errors": exc.errors()}), 400

    request_id = str(uuid.uuid4())
    _insert_request(request_id, payload.prompt, payload.context)

    event_payload = {
        "request_id": request_id,
        "prompt": payload.prompt,
        "context": payload.context,
        "ollama_base_url": OLLAMA_BASE_URL,
    }

    try:
        inngest_client.send_sync(
            inngest.Event(name="app/agent.request", data=event_payload)
        )
    except Exception as exc:  # pragma: no cover - defensive logging
        logger.exception("Failed to enqueue Inngest event", exc_info=exc)
        _update_request_status(request_id, "error", str(exc))
        return (
            jsonify({"message": "Failed to queue agent request", "request_id": request_id}),
            500,
        )

    response_body = {
        "request_id": request_id,
        "status": "queued",
    }
    return jsonify(response_body), 202


@app.route("/api/agent/<request_id>", methods=["GET"])
def get_agent_request(request_id: str):
    record = _fetch_request(request_id)
    if not record:
        return jsonify({"message": "Request not found"}), 404

    return jsonify(record)


@app.route("/internal/agent-result", methods=["POST"])
def agent_result_callback():
    auth_header = request.headers.get("Authorization", "")
    expected_header = f"Bearer {AGENT_RESULT_TOKEN}"
    if auth_header != expected_header:
        abort(401)

    try:
        payload = AgentResultPayload.model_validate(request.get_json(force=True))
    except ValidationError as exc:
        return jsonify({"message": "Invalid result payload", "errors": exc.errors()}), 400

    status_normalised = payload.status.lower()
    if status_normalised not in {"completed", "failed"}:
        return jsonify({"message": "Unsupported status"}), 400

    is_updated = _update_request_status(
        payload.request_id, status_normalised, payload.result
    )
    if not is_updated:
        return jsonify({"message": "Request not found"}), 404

    return ("", 204)


@app.route("/")
def root():
    return jsonify({"message": "LLM Agent service is running"})


inngest.flask.serve(app, inngest_client, [])


if __name__ == "__main__":
    port = int(os.getenv("FLASK_RUN_PORT", "80" if IS_CONTAINER else "5000"))
    app.run(debug=not IS_CONTAINER, host="0.0.0.0", port=port)
