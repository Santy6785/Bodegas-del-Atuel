"""Pruebas de integración para api/app/db/queries/vinos.py."""

from decimal import Decimal
import psycopg
import pytest

from app.db.queries.vinos import (
    actualizar_vino,
    crear_vino,
    eliminar_vino,
    listar_vinos,
    obtener_composicion_vino,
    obtener_maridajes_vino,
    obtener_vino,
)


@pytest.mark.integration
def test_obtener_vino_inexistente_retorna_none(db_conn: psycopg.Connection):
    """Caso 3: obtener_vino devuelve None para un código de vino que no existe."""
    resultado = obtener_vino(db_conn, cod_vino=999999)
    assert resultado is None


@pytest.mark.integration
def test_listar_vinos_paginacion_y_filtros(db_conn: psycopg.Connection):
    """Caso 1: listar_vinos con filtros combinados, total y paginación correcta."""
    # Insertar datos auxiliares de prueba
    db_conn.execute(
        """
        INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
        VALUES ('TEST0001', 'Ciudad Test', 'Mendoza', 'Encargado')
        ON CONFLICT DO NOTHING;
        INSERT INTO bodega (cuit, razon_social, domicilio)
        VALUES ('99999999991', 'TEST Bodega Norte', 'Ruta 40')
        ON CONFLICT DO NOTHING;
        INSERT INTO bodega (cuit, razon_social, domicilio)
        VALUES ('99999999992', 'TEST Bodega Sur', 'Ruta 143')
        ON CONFLICT DO NOTHING;
        INSERT INTO cepa (nombre, tipo) VALUES ('TEST Cepa Malbec', 'tinta') ON CONFLICT DO NOTHING;
        INSERT INTO cepa (nombre, tipo) VALUES ('TEST Cepa Syrah', 'tinta') ON CONFLICT DO NOTHING;
        """
    )
    cur = db_conn.cursor()
    cur.execute("SELECT id_cepa FROM cepa WHERE nombre = 'TEST Cepa Malbec'")
    cepa_malbec = cur.fetchone()["id_cepa"]
    cur.execute("SELECT id_cepa FROM cepa WHERE nombre = 'TEST Cepa Syrah'")
    cepa_syrah = cur.fetchone()["id_cepa"]

    # Insertamos 3 vinos de prueba
    cur.execute(
        """
        INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
        VALUES ('TEST Gran Reserva 1', 'tinto', 2020, 750, 14.5, 15000, '99999999991')
        RETURNING cod_vino;
        """
    )
    v1 = cur.fetchone()["cod_vino"]
    cur.execute(
        "INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje) VALUES (%s, %s, 100)",
        (v1, cepa_malbec),
    )

    cur.execute(
        """
        INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
        VALUES ('TEST Gran Reserva 2', 'tinto', 2020, 750, 14.0, 16000, '99999999991')
        RETURNING cod_vino;
        """
    )
    v2 = cur.fetchone()["cod_vino"]
    cur.execute(
        "INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje) VALUES (%s, %s, 100)",
        (v2, cepa_malbec),
    )

    cur.execute(
        """
        INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
        VALUES ('TEST Blanco Dulce', 'blanco', 2022, 750, 12.0, 8000, '99999999992')
        RETURNING cod_vino;
        """
    )
    v3 = cur.fetchone()["cod_vino"]
    cur.execute(
        "INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje) VALUES (%s, %s, 100)",
        (v3, cepa_syrah),
    )

    # 1. Filtro combinado: tipo='tinto', anada=2020, cuit_bodega='99999999991'
    items, total = listar_vinos(
        db_conn,
        page=1,
        page_size=10,
        tipo="tinto",
        anada=2020,
        cuit_bodega="99999999991",
        id_cepa=cepa_malbec,
    )
    assert total >= 2
    cods = [item["cod_vino"] for item in items]
    assert v1 in cods and v2 in cods
    assert v3 not in cods

    # 2. Paginación: page_size=1, página 2 debe traer exactamente 1 elemento
    items_p1, total_p = listar_vinos(
        db_conn,
        page=1,
        page_size=1,
        tipo="tinto",
        anada=2020,
        cuit_bodega="99999999991",
    )
    assert len(items_p1) == 1
    assert total_p == 2

    items_p2, total_p2 = listar_vinos(
        db_conn,
        page=2,
        page_size=1,
        tipo="tinto",
        anada=2020,
        cuit_bodega="99999999991",
    )
    assert len(items_p2) == 1
    assert items_p1[0]["cod_vino"] != items_p2[0]["cod_vino"]

    # 3. Página fuera de rango devuelve lista vacía y total correcto
    items_p100, total_p100 = listar_vinos(
        db_conn,
        page=100,
        page_size=10,
        tipo="tinto",
        anada=2020,
        cuit_bodega="99999999991",
    )
    assert items_p100 == []
    assert total_p100 == 2


@pytest.mark.integration
def test_listar_vinos_inyeccion_sql_fallida(db_conn: psycopg.Connection):
    """Caso 2: Inyección SQL en filtro nombre devuelve lista vacía sin error ni filas extras."""
    # Búsqueda con payload clásico de inyección SQL
    payload_inyeccion = "' OR '1'='1"
    items, total = listar_vinos(db_conn, nombre=payload_inyeccion)

    # Dado que ningún vino se llama literalmente "' OR '1'='1", debe retornar 0 coincidencias
    assert items == []
    assert total == 0


@pytest.mark.integration
def test_crear_vino_exitoso_y_obtener(db_conn_commit: psycopg.Connection):
    """Caso 4: crear_vino con composición que suma exactamente 100 % tiene éxito."""
    # Preparamos bodega y cepas auxiliares
    db_conn_commit.execute(
        """
        INSERT INTO bodega (cuit, razon_social, domicilio)
        VALUES ('99999999993', 'TEST Bodega Creacion', 'Ruta 50')
        ON CONFLICT DO NOTHING;
        INSERT INTO cepa (nombre, tipo) VALUES ('TEST Cepa A', 'tinta') ON CONFLICT DO NOTHING;
        INSERT INTO cepa (nombre, tipo) VALUES ('TEST Cepa B', 'tinta') ON CONFLICT DO NOTHING;
        INSERT INTO maridaje (nombre, temperatura_servicio) VALUES ('TEST Maridaje Asado', 18) ON CONFLICT DO NOTHING;
        """
    )
    cur = db_conn_commit.cursor()
    cur.execute("SELECT id_cepa FROM cepa WHERE nombre = 'TEST Cepa A'")
    ca = cur.fetchone()["id_cepa"]
    cur.execute("SELECT id_cepa FROM cepa WHERE nombre = 'TEST Cepa B'")
    cb = cur.fetchone()["id_cepa"]
    cur.execute("SELECT id_maridaje FROM maridaje WHERE nombre = 'TEST Maridaje Asado'")
    m1 = cur.fetchone()["id_maridaje"]

    cod_vino = crear_vino(
        db_conn_commit,
        {
            "nombre": "TEST Vino Blend 100",
            "tipo": "tinto",
            "anada": 2021,
            "volumen_ml": 750,
            "graduacion": Decimal("14.50"),
            "precio": Decimal("12500.00"),
            "cuit_bodega": "99999999993",
            "composicion": [
                {"id_cepa": ca, "porcentaje": Decimal("70.00")},
                {"id_cepa": cb, "porcentaje": Decimal("30.00")},
            ],
            "maridajes": [m1],
        },
    )
    assert cod_vino > 0

    vino = obtener_vino(db_conn_commit, cod_vino)
    assert vino is not None
    assert vino["nombre"] == "TEST Vino Blend 100"
    assert vino["precio"] == Decimal("12500.00")
    assert vino["bodega"]["cuit"] == "99999999993"
    assert vino["stock"]["total"] == 0

    comp = obtener_composicion_vino(db_conn_commit, cod_vino)
    assert len(comp) == 2
    assert sum(c["porcentaje"] for c in comp) == Decimal("100.00")

    maridajes = obtener_maridajes_vino(db_conn_commit, cod_vino)
    assert len(maridajes) == 1
    assert maridajes[0]["id_maridaje"] == m1


@pytest.mark.integration
def test_crear_vino_violacion_rn05_composicion_no_100(db_conn_commit: psycopg.Connection):
    """Caso 5: Violación RN-05: composición que no suma 100 genera excepción P0001 al commit."""
    db_conn_commit.execute(
        """
        INSERT INTO bodega (cuit, razon_social, domicilio)
        VALUES ('99999999994', 'TEST Bodega RN05', 'Dir')
        ON CONFLICT DO NOTHING;
        INSERT INTO cepa (nombre, tipo) VALUES ('TEST Cepa RN05', 'tinta') ON CONFLICT DO NOTHING;
        """
    )
    cur = db_conn_commit.cursor()
    cur.execute("SELECT id_cepa FROM cepa WHERE nombre = 'TEST Cepa RN05'")
    c_id = cur.fetchone()["id_cepa"]

    with pytest.raises(psycopg.errors.RaiseException) as exc_info:
        crear_vino(
            db_conn_commit,
            {
                "nombre": "TEST Vino Ilegal RN05",
                "tipo": "tinto",
                "anada": 2021,
                "volumen_ml": 750,
                "graduacion": Decimal("14.00"),
                "precio": Decimal("10000.00"),
                "cuit_bodega": "99999999994",
                "composicion": [
                    {"id_cepa": c_id, "porcentaje": Decimal("80.00")}  # 80 != 100
                ],
            },
        )
    assert exc_info.value.sqlstate == "P0001"
    assert "RN-05" in str(exc_info.value)

    # Verificar que no quedó fila creada (rollback automático de la transacción)
    cur.execute("SELECT cod_vino FROM vino WHERE nombre = 'TEST Vino Ilegal RN05'")
    assert cur.fetchone() is None


@pytest.mark.integration
def test_crear_vino_violacion_precio_invalido(db_conn: psycopg.Connection):
    """Caso 6: Violación RN-01/RN-15: precio <= 0 genera CheckViolation (23514)."""
    db_conn.execute(
        """
        INSERT INTO bodega (cuit, razon_social, domicilio)
        VALUES ('99999999995', 'TEST Bodega Precio', 'Dir')
        ON CONFLICT DO NOTHING;
        """
    )
    with pytest.raises(psycopg.errors.CheckViolation) as exc_info:
        crear_vino(
            db_conn,
            {
                "nombre": "TEST Vino Precio Cero",
                "tipo": "tinto",
                "anada": 2021,
                "volumen_ml": 750,
                "graduacion": Decimal("14.00"),
                "precio": Decimal("0.00"),  # Inválido por check ck_vino_precio_positivo
                "cuit_bodega": "99999999995",
            },
        )
    assert exc_info.value.sqlstate == "23514"


@pytest.mark.integration
def test_crear_vino_violacion_unicidad(db_conn: psycopg.Connection):
    """Caso 7: Violación de unicidad (nombre, añada, volumen_ml) propaga 23505."""
    db_conn.execute(
        """
        INSERT INTO bodega (cuit, razon_social, domicilio)
        VALUES ('99999999996', 'TEST Bodega Unicidad', 'Dir')
        ON CONFLICT DO NOTHING;
        INSERT INTO cepa (nombre, tipo) VALUES ('TEST Cepa Unica', 'tinta') ON CONFLICT DO NOTHING;
        """
    )
    cur = db_conn.cursor()
    cur.execute("SELECT id_cepa FROM cepa WHERE nombre = 'TEST Cepa Unica'")
    c_id = cur.fetchone()["id_cepa"]

    datos_vino = {
        "nombre": "TEST Vino Repetido",
        "tipo": "tinto",
        "anada": 2020,
        "volumen_ml": 750,
        "graduacion": Decimal("13.50"),
        "precio": Decimal("10000.00"),
        "cuit_bodega": "99999999996",
        "composicion": [{"id_cepa": c_id, "porcentaje": Decimal("100.00")}],
    }

    # Primer alta directa en SQL para no disparar trigger al commit del fixture
    cur.execute(
        """
        INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
        VALUES ('TEST Vino Repetido', 'tinto', 2020, 750, 13.50, 10000.00, '99999999996');
        """
    )

    # Segundo alta idéntica debe fallar por unicidad
    with pytest.raises(psycopg.errors.UniqueViolation) as exc_info:
        crear_vino(db_conn, datos_vino)
    assert exc_info.value.sqlstate == "23505"


@pytest.mark.integration
def test_actualizar_y_eliminar_vino(db_conn_commit: psycopg.Connection):
    """Prueba actualización completa de vino y posterior eliminación."""
    db_conn_commit.execute(
        """
        INSERT INTO bodega (cuit, razon_social, domicilio)
        VALUES ('99999999997', 'TEST Bodega Edit', 'Dir')
        ON CONFLICT DO NOTHING;
        INSERT INTO cepa (nombre, tipo) VALUES ('TEST Cepa E1', 'tinta') ON CONFLICT DO NOTHING;
        INSERT INTO cepa (nombre, tipo) VALUES ('TEST Cepa E2', 'blanca') ON CONFLICT DO NOTHING;
        """
    )
    cur = db_conn_commit.cursor()
    cur.execute("SELECT id_cepa FROM cepa WHERE nombre = 'TEST Cepa E1'")
    e1 = cur.fetchone()["id_cepa"]
    cur.execute("SELECT id_cepa FROM cepa WHERE nombre = 'TEST Cepa E2'")
    e2 = cur.fetchone()["id_cepa"]

    cod_vino = crear_vino(
        db_conn_commit,
        {
            "nombre": "TEST Vino Para Editar",
            "tipo": "tinto",
            "anada": 2020,
            "volumen_ml": 750,
            "graduacion": Decimal("14.00"),
            "precio": Decimal("10000.00"),
            "cuit_bodega": "99999999997",
            "composicion": [{"id_cepa": e1, "porcentaje": Decimal("100.00")}],
        },
    )

    # Actualizar con nuevo precio y nueva composición
    filas = actualizar_vino(
        db_conn_commit,
        cod_vino,
        {
            "nombre": "TEST Vino Modificado",
            "tipo": "blanco",
            "anada": 2021,
            "volumen_ml": 750,
            "graduacion": Decimal("13.00"),
            "precio": Decimal("15000.00"),
            "cuit_bodega": "99999999997",
            "composicion": [{"id_cepa": e2, "porcentaje": Decimal("100.00")}],
        },
    )
    assert filas == 1

    actualizado = obtener_vino(db_conn_commit, cod_vino)
    assert actualizado["nombre"] == "TEST Vino Modificado"
    assert actualizado["precio"] == Decimal("15000.00")

    comp = obtener_composicion_vino(db_conn_commit, cod_vino)
    assert len(comp) == 1
    assert comp[0]["id_cepa"] == e2

    # Intentar eliminar un vino con cambio de precio falla por auditoria_precio (RN-14)
    with pytest.raises(psycopg.errors.ForeignKeyViolation) as exc_del:
        eliminar_vino(db_conn_commit, cod_vino)
    assert exc_del.value.sqlstate == "23503"

    # Un vino nuevo sin cambios de precio ni ventas puede eliminarse sin conflicto
    cod_vino_nuevo = crear_vino(
        db_conn_commit,
        {
            "nombre": "TEST Vino Borrable",
            "tipo": "tinto",
            "anada": 2022,
            "volumen_ml": 750,
            "graduacion": Decimal("13.50"),
            "precio": Decimal("9000.00"),
            "cuit_bodega": "99999999997",
            "composicion": [{"id_cepa": e1, "porcentaje": Decimal("100.00")}],
        },
    )
    filas_del = eliminar_vino(db_conn_commit, cod_vino_nuevo)
    assert filas_del == 1
    assert obtener_vino(db_conn_commit, cod_vino_nuevo) is None
