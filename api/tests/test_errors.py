"""Pruebas de traducción SQLSTATE → HTTP (api/app/errors.py).

Crea una aplicación FastAPI mínima dentro del módulo (sin usar app.main)
para lanzar excepciones de psycopg controladas y verificar que el handler
genérico las traduzca según el contrato §1.2 y el TPI Etapa 6.

Incluye una prueba de regresión contra GET /salud usando el cliente de
conftest.py para asegurar que el handler de base inaccesible sigue vigente.

También incluye pruebas contra la app real de app.main para verificar que
los errores de conexión (OperationalError / PoolTimeout sin SQLSTATE) en
endpoints de negocio respondan 503 con formato anidado.
"""

from collections.abc import Generator
from contextlib import asynccontextmanager

import psycopg
import psycopg.errors as pge
import psycopg_pool
import pytest
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.testclient import TestClient

from app.errors import register_exception_handlers, traducir_error
from app.db.pool import get_conn
from app.main import app


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

    # --- Rutas adicionales para verificar el contrato completo ---
    # (status_code, formato cuerpo, sqlstate, mensaje exacto, restriccion)

    @app.post("/unique-full")
    def unique_full():
        raise pge.UniqueViolation("duplicate key")

    @app.post("/check-full")
    def check_full():
        raise pge.CheckViolation("check violated")

    @app.post("/notnull-full")
    def notnull_full():
        raise pge.NotNullViolation("null value")

    @app.post("/invalidtext-full")
    def invalidtext_full():
        raise pge.InvalidTextRepresentation("invalid text")

    @app.post("/serialization-full")
    def serialization_full():
        raise pge.SerializationFailure("serialization failure")

    @app.post("/deadlock-full")
    def deadlock_full():
        raise pge.DeadlockDetected("deadlock detected")

    @app.post("/fk-full")
    def fk_full_post():
        raise pge.ForeignKeyViolation("fk")

    @app.delete("/fk-full")
    def fk_full_delete():
        raise pge.ForeignKeyViolation("fk")

    @app.post("/nomap-full")
    def nomap_full():
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
# Parte A: errores de conexión en endpoints de negocio (app mínima)
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
    """PoolTimeout en endpoint de negocio → 503 con formato del contrato (sin sqlstate).

    PoolTimeout hereda de psycopg.OperationalError y no expone sqlstate,
    por lo que traducir_error lo clasifica como error de conexión (503).
    """
    resp = conexion_client.post("/pool-timeout")
    assert resp.status_code == 503
    body = resp.json()
    assert set(body.keys()) == {"error"}
    assert set(body["error"].keys()) == {"sqlstate", "mensaje", "restriccion"}
    assert body["error"]["sqlstate"] is None
    assert body["error"]["mensaje"] == "No hay conexión con la base de datos."
    assert body["error"]["restriccion"] is None


# ---------------------------------------------------------------------------
# Parte B: errores de conexión en endpoints de negocio (app real)
# ---------------------------------------------------------------------------

class FailConnReal:
    """Conexión falsa cuyo transaction() lanza psycopg.OperationalError.

    Simula una caída de conexión (sin SQLSTATE del servidor) al iniciar
    una transacción, que es lo que hace crear_vino al llamar a
    ``conn.transaction()`` dentro de ``with conn.transaction()``.
    """

    def execute(self, query, params=None):
        raise psycopg.OperationalError("conexión caída")

    def cursor(self):
        raise psycopg.OperationalError("conexión caída")

    def transaction(self):
        return _FailingTransactionReal()

    def close(self):
        pass


class _FailingTransactionReal:
    """Context manager que lanza OperationalError al entrar."""

    def __enter__(self):
        raise psycopg.OperationalError("conexión caída")

    def __exit__(self, *args):
        return False


def _fake_fail_conn() -> Generator[FailConnReal, None, None]:
    yield FailConnReal()


@pytest.fixture()
def real_app_client() -> TestClient:
    """TestClient contra la app real de app.main con get_conn sobrescrito."""
    original_lifespan = app.router.lifespan_context

    @asynccontextmanager
    async def _lifespan_vacio(_app):
        yield

    app.router.lifespan_context = _lifespan_vacio
    try:
        with TestClient(app) as c:
            yield c
    finally:
        app.router.lifespan_context = original_lifespan
        app.dependency_overrides.clear()


def test_post_vinos_operational_error_503(real_app_client: TestClient):
    """POST /vinos con OperationalError sin SQLSTATE → 503, formato anidado.

    Usa la app real de app.main con el handler registrado. El override de
    get_conn devuelve una conexión cuyo transaction() lanza
    psycopg.OperationalError("conexión caída") sin sqlstate.
    """
    app.dependency_overrides[get_conn] = _fake_fail_conn
    try:
        resp = real_app_client.post(
            "/vinos",
            json={
                "nombre": "TEST Vino Error Conexión",
                "tipo": "tinto",
                "anada": 2021,
                "volumen_ml": 750,
                "graduacion": "14.00",
                "precio": "10000.00",
                "cuit_bodega": "99999999901",
                "composicion": [{"id_cepa": 1, "porcentaje": "100.00"}],
            },
        )
    finally:
        app.dependency_overrides.clear()
    assert resp.status_code == 503, resp.text
    body = resp.json()
    assert set(body.keys()) == {"error"}
    assert set(body["error"].keys()) == {"sqlstate", "mensaje", "restriccion"}
    assert body["error"]["sqlstate"] is None
    assert body["error"]["mensaje"] == "No hay conexión con la base de datos."
    assert body["error"]["restriccion"] is None


def test_post_vinos_pool_timeout_503(real_app_client: TestClient):
    """POST /vinos con PoolTimeout → 503, formato anidado, sqlstate None.

    PoolTimeout hereda de psycopg.OperationalError y no trae sqlstate.
    """
    app.dependency_overrides[get_conn] = _fake_fail_conn
    try:
        resp = real_app_client.post(
            "/vinos",
            json={
                "nombre": "TEST Vino Pool Timeout",
                "tipo": "tinto",
                "anada": 2021,
                "volumen_ml": 750,
                "graduacion": "14.00",
                "precio": "10000.00",
                "cuit_bodega": "99999999902",
                "composicion": [{"id_cepa": 1, "porcentaje": "100.00"}],
            },
        )
    finally:
        app.dependency_overrides.clear()
    assert resp.status_code == 503, resp.text
    body = resp.json()
    assert body["error"]["sqlstate"] is None
    assert body["error"]["mensaje"] == "No hay conexión con la base de datos."
    assert body["error"]["restriccion"] is None


def test_salud_operational_error_sigue_cuerpo_propio(real_app_client: TestClient):
    """GET /salud con OperationalError → 503 con cuerpo propio de base inaccesible.

    El handler específico de /salud tiene prioridad y conserva su cuerpo:
    {"estado": "error", "base_de_datos": "inaccesible"}.
    """
    app.dependency_overrides[get_conn] = _fake_fail_conn
    try:
        resp = real_app_client.get("/salud")
    finally:
        app.dependency_overrides.clear()
    assert resp.status_code == 503
    assert resp.json() == {"estado": "error", "base_de_datos": "inaccesible"}


# ---------------------------------------------------------------------------
# Contrato completo por SQLSTATE (Sección 6 del TP)
# ---------------------------------------------------------------------------
# Cada prueba valida por HTTP (TestClient -> handler real de FastAPI):
#   status_code, formato {"error": {"sqlstate","mensaje","restriccion"}},
#   sqlstate exacto, mensaje exacto según api/app/errors.py y restriccion.
# Los mensajes son los reales de errors.py (no se parcha errors.py; las
# discrepancias con la tabla del TP se documentan en el informe final).


def _assert_cuerpo_contrato(body: dict) -> None:
    """Verifica el formato anidado exacto del contrato §1.1."""
    assert set(body.keys()) == {"error"}
    assert set(body["error"].keys()) == {"sqlstate", "mensaje", "restriccion"}


def test_23505_unique_formato_completo(app_client: TestClient):
    """23505 (Unicidad) -> 409, mensaje de errors.py, restriccion None."""
    resp = app_client.post("/unique-full")
    assert resp.status_code == 409
    body = resp.json()
    _assert_cuerpo_contrato(body)
    assert body["error"]["sqlstate"] == "23505"
    assert body["error"]["mensaje"] == "Ya existe un registro con esos datos."
    assert body["error"]["restriccion"] is None


def test_23503_delete_formato_completo(app_client: TestClient):
    """23503 FK en DELETE -> 409, mensaje DELETE, restriccion None."""
    resp = app_client.delete("/fk-full")
    assert resp.status_code == 409
    body = resp.json()
    _assert_cuerpo_contrato(body)
    assert body["error"]["sqlstate"] == "23503"
    assert body["error"]["mensaje"] == "No se puede eliminar: el registro tiene datos asociados."
    assert body["error"]["restriccion"] is None


def test_23503_post_formato_completo(app_client: TestClient):
    """23503 FK en POST (no DELETE) -> 422, mensaje no-DELETE, restriccion None."""
    resp = app_client.post("/fk-full")
    assert resp.status_code == 422
    body = resp.json()
    _assert_cuerpo_contrato(body)
    assert body["error"]["sqlstate"] == "23503"
    assert body["error"]["mensaje"] == "El dato referenciado no existe."
    assert body["error"]["restriccion"] is None


def test_23514_check_formato_completo(app_client: TestClient):
    """23514 (CHECK/dominio) -> 422, mensaje de errors.py, restriccion None."""
    resp = app_client.post("/check-full")
    assert resp.status_code == 422
    body = resp.json()
    _assert_cuerpo_contrato(body)
    assert body["error"]["sqlstate"] == "23514"
    assert body["error"]["mensaje"] == "Un valor no cumple una restricción de dominio."
    assert body["error"]["restriccion"] is None


def test_23502_notnull_formato_completo(app_client: TestClient):
    """23502 (NOT NULL) -> 422, mensaje de errors.py, restriccion None."""
    resp = app_client.post("/notnull-full")
    assert resp.status_code == 422
    body = resp.json()
    _assert_cuerpo_contrato(body)
    assert body["error"]["sqlstate"] == "23502"
    assert body["error"]["mensaje"] == "Falta un dato obligatorio."
    assert body["error"]["restriccion"] is None


def test_22p02_invalidtext_formato_completo(app_client: TestClient):
    """22P02 (representación inválida) -> 400, mensaje de errors.py, restriccion None."""
    resp = app_client.post("/invalidtext-full")
    assert resp.status_code == 400
    body = resp.json()
    _assert_cuerpo_contrato(body)
    assert body["error"]["sqlstate"] == "22P02"
    assert body["error"]["mensaje"] == "Formato inválido para un dato."
    assert body["error"]["restriccion"] is None


def test_p0001_raise_formato_completo(app_client: TestClient):
    """P0001 (RAISE EXCEPTION negocio) -> 409, mensaje original intacto, restriccion None."""
    resp = app_client.post("/raise")
    assert resp.status_code == 409
    body = resp.json()
    _assert_cuerpo_contrato(body)
    assert body["error"]["sqlstate"] == "P0001"
    assert body["error"]["mensaje"] == "Stock insuficiente del vino 10 en la sala 1 (RN-09)"
    assert body["error"]["restriccion"] is None


def test_40001_serialization_formato_completo(app_client: TestClient):
    """40001 (serialización) -> 503, Retry-After: 1, mensaje de errors.py, restriccion None."""
    resp = app_client.post("/serialization-full")
    assert resp.status_code == 503
    assert resp.headers["Retry-After"] == "1"
    body = resp.json()
    _assert_cuerpo_contrato(body)
    assert body["error"]["sqlstate"] == "40001"
    assert body["error"]["mensaje"] == "La operación no pudo completarse por concurrencia. Intente nuevamente."
    assert body["error"]["restriccion"] is None


def test_40p01_deadlock_formato_completo(app_client: TestClient):
    """40P01 (deadlock) -> 503, Retry-After: 1, mensaje de errors.py, restriccion None."""
    resp = app_client.post("/deadlock-full")
    assert resp.status_code == 503
    assert resp.headers["Retry-After"] == "1"
    body = resp.json()
    _assert_cuerpo_contrato(body)
    assert body["error"]["sqlstate"] == "40P01"
    assert body["error"]["mensaje"] == "La operación no pudo completarse por concurrencia. Intente nuevamente."
    assert body["error"]["restriccion"] is None


def test_42601_no_mapeado_formato_completo(app_client: TestClient):
    """SQLSTATE no mapeado (42601) -> 500, mensaje genérico, no filtra texto técnico."""
    resp = app_client.post("/nomap-full")
    assert resp.status_code == 500
    body = resp.json()
    _assert_cuerpo_contrato(body)
    assert body["error"]["sqlstate"] == "42501"
    assert body["error"]["mensaje"] == "Error interno de la base de datos."
    assert body["error"]["restriccion"] is None
    assert "insufficient privilege" not in body["error"]["mensaje"]
