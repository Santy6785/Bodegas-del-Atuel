"""Pruebas de traducción SQLSTATE → HTTP (api/app/errors.py).

Crea una aplicación FastAPI mínima dentro del módulo (sin usar app.main)
para lanzar excepciones de psycopg controladas y verificar que el handler
genérico las traduzca según el contrato §1.2 y el TPI Etapa 6.

Incluye una prueba de regresión contra GET /salud usando el cliente de
conftest.py para asegurar que el handler de base inaccesible sigue vigente.
"""

from collections.abc import Generator

import psycopg
import psycopg.errors as pge
import psycopg_pool
import pytest
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.testclient import TestClient

from app.errors import register_exception_handlers, traducir_error
from app.db.pool import get_conn


class FailConn:
    """Conexión falsa que falla en cualquier consulta (regresión /salud)."""

    def execute(self, query, params=None):
        raise psycopg.OperationalError("conexión simulada fallida")


def _fake_conn_fail() -> Generator[FailConn, None, None]:
    yield FailConn()


def _app_de_prueba() -> FastAPI:
    """App mínima con un handler de psycopg.Error y una ruta por SQLSTATE."""
    app = FastAPI()
    register_exception_handlers(app)

    @app.post("/unique")
    def unique():
        raise pge.UniqueViolation("duplicate key")

    @app.delete("/fk")
    def fk_delete():
        raise pge.ForeignKeyViolation("fk")

    @app.post("/fk")
    def fk_post():
        raise pge.ForeignKeyViolation("fk")

    @app.post("/check")
    def check():
        raise pge.CheckViolation("check")

    @app.post("/notnull")
    def notnull():
        raise pge.NotNullViolation("notnull")

    @app.post("/raise")
    def raise_exc():
        # Regla de negocio: el mensaje del RAISE debe llegar intacto al cliente.
        raise pge.RaiseException("Stock insuficiente del vino 10 en la sala 1 (RN-09)")

    @app.post("/invalidtext")
    def invalidtext():
        raise pge.InvalidTextRepresentation("invalid text")

    @app.post("/serialization")
    def serialization():
        raise pge.SerializationFailure("serialization failure")

    @app.post("/deadlock")
    def deadlock():
        raise pge.DeadlockDetected("deadlock detected")

    @app.post("/nomap")
    def nomap():
        raise pge.InsufficientPrivilege("insufficient privilege")

    return app


@pytest.fixture()
def app_client() -> TestClient:
    return TestClient(_app_de_prueba())


# ---------------------------------------------------------------------------
# Pruebas de traducción pura (sin HTTP)
# ---------------------------------------------------------------------------

def test_traducir_error_devuelve_tupla_de_tres():
    """traducir_error devuelve (status_code, cuerpo, headers)."""
    exc = pge.UniqueViolation("dup")
    status, cuerpo, headers = traducir_error(exc, "POST")
    assert isinstance(status, int)
    assert isinstance(cuerpo, dict)
    assert isinstance(headers, dict)


def test_traducir_error_no_filtra_texto_original_no_mapeado():
    """Errores no mapeados devuelven mensaje genérico, nunca el texto original."""
    exc = pge.InsufficientPrivilege("privilegios insuficientes para usuario app_rw")
    status, cuerpo, headers = traducir_error(exc, "POST")
    assert status == 500
    assert cuerpo["error"]["mensaje"] == "Error interno de la base de datos."
    assert "privilegios insuficientes" not in cuerpo["error"]["mensaje"]


def test_log_500_no_volca_texto_original(caplog):
    """P2: el log del caso 500 no contiene el texto original de la base.

    Solo se registran sqlstate, constraint y tabla (nunca datos personales
    ni cadenas de conexión).
    """
    exc = pge.InsufficientPrivilege("Key (nro_documento)=(30111222) already exists.")
    with caplog.at_level("ERROR", logger="bodegas.errors"):
        traducir_error(exc, "POST")
    assert caplog.records
    texto_log = caplog.records[0].getMessage()
    assert "30111222" not in texto_log
    assert "already exists" not in texto_log
    assert "sqlstate=42501" in texto_log


# ---------------------------------------------------------------------------
# Pruebas HTTP por SQLSTATE
# ---------------------------------------------------------------------------

def test_23505_unique_409(app_client: TestClient):
    """23505 → 409, cuerpo con sqlstate == '23505'."""
    resp = app_client.post("/unique")
    assert resp.status_code == 409
    body = resp.json()
    assert body["error"]["sqlstate"] == "23505"


def test_23503_delete_409(app_client: TestClient):
    """23503 con DELETE → 409."""
    resp = app_client.delete("/fk")
    assert resp.status_code == 409
    body = resp.json()
    assert body["error"]["sqlstate"] == "23503"
    assert body["error"]["mensaje"] == "No se puede eliminar: el registro tiene datos asociados."


def test_23503_post_422(app_client: TestClient):
    """23503 con POST → 422."""
    resp = app_client.post("/fk")
    assert resp.status_code == 422
    body = resp.json()
    assert body["error"]["sqlstate"] == "23503"
    assert body["error"]["mensaje"] == "El dato referenciado no existe."


def test_23514_check_422(app_client: TestClient):
    """23514 → 422."""
    resp = app_client.post("/check")
    assert resp.status_code == 422
    assert resp.json()["error"]["sqlstate"] == "23514"


def test_23502_notnull_422(app_client: TestClient):
    """23502 → 422."""
    resp = app_client.post("/notnull")
    assert resp.status_code == 422
    assert resp.json()["error"]["sqlstate"] == "23502"


def test_p0001_raise_intacto(app_client: TestClient):
    """P0001 → 409 y mensaje igual al texto del RAISE (regla de negocio intacta).

    Regla de negocio: RN-09.
    """
    resp = app_client.post("/raise")
    assert resp.status_code == 409
    body = resp.json()
    assert body["error"]["sqlstate"] == "P0001"
    assert body["error"]["mensaje"] == "Stock insuficiente del vino 10 en la sala 1 (RN-09)"
    assert body["error"]["restriccion"] is None


def test_22p02_400(app_client: TestClient):
    """22P02 → 400."""
    resp = app_client.post("/invalidtext")
    assert resp.status_code == 400
    assert resp.json()["error"]["sqlstate"] == "22P02"


def test_40001_503_retry_after(app_client: TestClient):
    """40001 → 503 con header Retry-After: 1."""
    resp = app_client.post("/serialization")
    assert resp.status_code == 503
    assert resp.headers["Retry-After"] == "1"
    assert resp.json()["error"]["sqlstate"] == "40001"


def test_40p01_503_retry_after(app_client: TestClient):
    """40P01 → 503 con header Retry-After: 1."""
    resp = app_client.post("/deadlock")
    assert resp.status_code == 503
    assert resp.headers["Retry-After"] == "1"
    assert resp.json()["error"]["sqlstate"] == "40P01"


def test_error_no_mapeado_500_generico(app_client: TestClient):
    """42501 (no mapeado) → 500 con mensaje genérico, sin filtrar texto original."""
    resp = app_client.post("/nomap")
    assert resp.status_code == 500
    body = resp.json()
    assert body["error"]["sqlstate"] == "42501"
    assert body["error"]["mensaje"] == "Error interno de la base de datos."
    assert "insufficient privilege" not in body["error"]["mensaje"]


def test_formato_cuerpo_anidado_exacto(app_client: TestClient):
    """La raíz es 'error' y contiene exactamente sqlstate, mensaje, restriccion."""
    resp = app_client.post("/unique")
    assert resp.status_code == 409
    body = resp.json()
    assert set(body.keys()) == {"error"}
    assert set(body["error"].keys()) == {"sqlstate", "mensaje", "restriccion"}


# ---------------------------------------------------------------------------
# Regresión: GET /salud sigue devolviendo su cuerpo distinto (503)
# ---------------------------------------------------------------------------

def test_salud_regresion_503_base_inaccesible(client: TestClient):
    """GET /salud con falla de conexión → 503 y cuerpo de base inaccesible.

    Usa el cliente de conftest.py y la app real de app.main. Verifica que el
    handler específico de psycopg.OperationalError / PoolTimeout tiene prioridad
    sobre el genérico de psycopg.Error.
    """
    app = client.app  # type: ignore[attr-defined]
    app.dependency_overrides[get_conn] = _fake_conn_fail
    try:
        resp = client.get("/salud")
    finally:
        app.dependency_overrides.clear()
    assert resp.status_code == 503
    assert resp.json() == {"estado": "error", "base_de_datos": "inaccesible"}


# ---------------------------------------------------------------------------
# Parte A: errores de conexión en endpoints de negocio
# ---------------------------------------------------------------------------

def _app_conexion() -> FastAPI:
    """App mínima con ambos handlers: conexión (OperationalError/PoolTimeout)
    y genérico (psycopg.error). Reproduce el comportamiento real de main.py."""
    app = FastAPI()
    register_exception_handlers(app)

    @app.exception_handler(psycopg.OperationalError)
    @app.exception_handler(psycopg_pool.PoolTimeout)
    async def _error_conexion(request: Request, exc: psycopg.Error):
        if request.url.path == "/salud":
            return JSONResponse(
                status_code=503,
                content={"estado": "error", "base_de_datos": "inaccesible"},
            )
        status_code, cuerpo, headers = traducir_error(exc, request.method)
        return JSONResponse(status_code=status_code, content=cuerpo, headers=headers)

    @app.post("/negocio")
    def negocio():
        # ConnectionFailure tiene sqlstate '08006' (clase 08).
        raise pge.ConnectionFailure("no se pudo conectar a la base de datos")

    @app.post("/pool-timeout")
    def pool_timeout():
        # PoolTimeout no expone sqlstate; cae al caso no mapeado (500).
        raise psycopg_pool.PoolTimeout("tiempo de espera del pool agotado")

    return app


@pytest.fixture()
def conexion_client() -> TestClient:
    return TestClient(_app_conexion())


def test_conexion_endpoint_negocio_formato_contrato(conexion_client: TestClient):
    """ConnectionFailure (08006) en endpoint de negocio → 503 con formato anidado."""
    resp = conexion_client.post("/negocio")
    assert resp.status_code == 503
    body = resp.json()
    assert set(body.keys()) == {"error"}
    assert set(body["error"].keys()) == {"sqlstate", "mensaje", "restriccion"}
    assert body["error"]["sqlstate"] == "08006"
    assert body["error"]["mensaje"] == "No hay conexión con la base de datos."
    assert body["error"]["restriccion"] is None


def test_pool_timeout_endpoint_negocio_formato_contrato(conexion_client: TestClient):
    """PoolTimeout en endpoint de negocio → formato del contrato (500, sin sqlstate)."""
    resp = conexion_client.post("/pool-timeout")
    assert resp.status_code == 500
    body = resp.json()
    assert set(body.keys()) == {"error"}
    assert set(body["error"].keys()) == {"sqlstate", "mensaje", "restriccion"}
    assert body["error"]["sqlstate"] is None
    assert body["error"]["mensaje"] == "Error interno de la base de datos."
