"""Pruebas de documentación OpenAPI: /docs y /openapi.json.

Verifica que la documentación expuesta por FastAPI refleje las rutas
reales de los routers de negocio (vinos, clientes, comprobantes,
ingresos, transferencias, reportes, catálogos, salud) y que no existan
rutas de borrador, plantilla o prueba.

No requiere PostgreSQL: la introspección de OpenAPI no abre conexiones a
base de datos. Se reemplaza el ``lifespan`` para no abrir el pool real
(igual que hacen los tests de ``test_errors.py``).
"""

from contextlib import asynccontextmanager

import pytest
from fastapi.testclient import TestClient

from app.main import app


# ---------------------------------------------------------------------------
# Cliente contra la app real sin abrir el pool de BD (lifespan vacío)
# ---------------------------------------------------------------------------

@pytest.fixture()
def docs_client() -> TestClient:
    """TestClient contra app.real con lifespan vacío (sin pool de BD)."""
    original_lifespan = app.router.lifespan_context

    @asynccontextmanager
    async def _lifespan_vacio(_app):
        yield

    app.router.lifespan_context = _lifespan_vacio
    try:
        with TestClient(app) as client:
            yield client
    finally:
        app.router.lifespan_context = original_lifespan


# ---------------------------------------------------------------------------
# Rutas reales esperadas (método, path) extraídas de api/app/routers/
# ---------------------------------------------------------------------------
# Cada tupla es (METODO, path_completo_tal_como_aparece_en_openapi).
# FastAPI normaliza los parámetros de ruta con llaves {param}.

RUTAS_REALES = [
    # vinos
    ("get", "/vinos"),
    ("get", "/vinos/{cod_vino}"),
    ("post", "/vinos"),
    ("put", "/vinos/{cod_vino}"),
    ("delete", "/vinos/{cod_vino}"),
    # comprobantes
    ("post", "/comprobantes"),
    # reportes
    ("get", "/reportes/top-vinos"),
    ("get", "/reportes/vinos-sin-stock"),
    ("get", "/reportes/transportista-activo"),
    ("get", "/reportes/ventas-por-sala"),
    ("get", "/reportes/trazabilidad/{cod}"),
    # transferencias
    ("get", "/transferencias"),
    ("get", "/transferencias/{nro}"),
    ("post", "/transferencias"),
    ("post", "/transferencias/{nro}/renglones"),
    ("post", "/transferencias/{nro}/terminar"),
    ("post", "/transferencias/{nro}/procesar"),
    # clientes
    ("get", "/clientes"),
    ("get", "/clientes/{id_cliente}"),
    ("post", "/clientes"),
    ("put", "/clientes/{id_cliente}"),
    ("delete", "/clientes/{id_cliente}"),
    # catalogos (sin prefijo)
    ("get", "/cepas"),
    ("get", "/bodegas"),
    ("get", "/salas"),
    ("get", "/maridajes"),
    ("get", "/transportistas"),
    ("get", "/localidades"),
    # ingresos
    ("get", "/ingresos"),
    ("get", "/ingresos/{cod}"),
    ("post", "/ingresos"),
    ("post", "/ingresos/{cod}/renglones"),
    ("post", "/ingresos/{cod}/terminar"),
    ("post", "/ingresos/{cod}/procesar"),
    # salud (definida directamente en main.py)
    ("get", "/salud"),
]

# Rutas de borrador/plantilla que NO deben aparecer.
RUTAS_BORRADOR = ("/items", "/users", "/borrador", "/draft", "/ejemplo", "/test")


# ---------------------------------------------------------------------------
# Pruebas
# ---------------------------------------------------------------------------

def test_docs_devuelve_swagger_ui(docs_client: TestClient):
    """GET /docs → 200 (text/html), renderiza Swagger UI apuntando a /openapi.json."""
    resp = docs_client.get("/docs")
    assert resp.status_code == 200, resp.text
    assert "text/html" in resp.headers.get("content-type", "")
    html = resp.text
    assert "swagger-ui" in html.lower(), html
    assert "/openapi.json" in html, html


def test_openapi_json_devuelve_paths(docs_client: TestClient):
    """GET /openapi.json → 200 con claves "openapi" y "paths"."""
    resp = docs_client.get("/openapi.json")
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert "openapi" in body, body
    assert "paths" in body, body


def test_todas_las_rutas_reales_estan_en_openapi(docs_client: TestClient):
    """Cada ruta real de negocio aparece en openapi["paths"] con su método."""
    resp = docs_client.get("/openapi.json")
    assert resp.status_code == 200
    paths = resp.json()["paths"]

    for metodo, ruta in RUTAS_REALES:
        assert ruta in paths, f"Ruta faltante en OpenAPI: {metodo.upper()} {ruta}"
        operacion = paths[ruta].get(metodo)
        assert operacion is not None, (
            f"Método faltante en OpenAPI: {metodo.upper()} {ruta}"
        )
        # Cada operación documentada debe tener summary/operationId y responses válidas.
        assert "responses" in operacion, f"Sin responses en {metodo.upper()} {ruta}"
        assert (
            "summary" in operacion or "operationId" in operacion
        ), f"Sin summary/operationId en {metodo.upper()} {ruta}"


def test_no_hay_rutas_de_borrador_en_openapi(docs_client: TestClient):
    """openapi["paths"] no contiene rutas de borrador, plantilla o prueba."""
    resp = docs_client.get("/openapi.json")
    assert resp.status_code == 200
    paths = resp.json()["paths"]

    for ruta_borrador in RUTAS_BORRADOR:
        assert ruta_borrador not in paths, (
            f"Ruta de borrador detectada en OpenAPI: {ruta_borrador}"
        )

    # Ninguna ruta documentada debe contener palabras de borrador.
    for ruta in paths:
        ruta_lower = ruta.lower()
        for palabra in ("item", "user", "borrador", "draft", "ejemplo", "mock", "placeholder"):
            assert palabra not in ruta_lower, (
                f"Ruta sospechosa de borrador en OpenAPI: {ruta}"
            )
