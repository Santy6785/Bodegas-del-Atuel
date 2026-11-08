"""Pruebas de integración para api/app/db/queries/clientes.py."""

from datetime import date
from decimal import Decimal
import psycopg
import pytest

from app.db.queries.clientes import (
    actualizar_cliente,
    crear_cliente,
    eliminar_cliente,
    listar_clientes,
    obtener_cliente,
    obtener_permisos_exportacion,
)


@pytest.mark.integration
def test_obtener_cliente_socio_descuento_10_pct(db_conn: psycopg.Connection):
    """Caso 10: obtener_cliente de tipo socio devuelve descuento_pct 10.00 (fn_descuento_cliente)."""
    # Crear localidad y cliente socio
    db_conn.execute(
        """
        INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
        VALUES ('TEST5600', 'San Rafael', 'Mendoza', 'Encargado')
        ON CONFLICT DO NOTHING;
        """
    )
    cur = db_conn.cursor()
    cur.execute(
        """
        INSERT INTO cliente (
            apellido_razon_social, nombre, tipo_documento,
            nro_documento, direccion, codigo_postal, tipo_cliente
        )
        VALUES ('TEST Pérez', 'Juan', 'DNI', '99111222', 'Av. San Martín 100', 'TEST5600', 'socio')
        RETURNING id_cliente;
        """
    )
    id_cliente = cur.fetchone()["id_cliente"]

    cliente = obtener_cliente(db_conn, id_cliente)
    assert cliente is not None
    assert cliente["apellido_razon_social"] == "TEST Pérez"
    assert cliente["tipo_cliente"] == "socio"
    # El descuento_pct debe provenir de fn_descuento_cliente(id_cliente) = 10.00
    assert cliente["descuento_pct"] == Decimal("10.00")
    assert "distribuidor" not in cliente
    assert "exportador" not in cliente


@pytest.mark.integration
def test_listar_clientes_paginado_y_filtro_tipo(db_conn: psycopg.Connection):
    """Prueba listar_clientes con paginación y filtro por tipo_cliente."""
    db_conn.execute(
        """
        INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
        VALUES ('TEST5601', 'General Alvear', 'Mendoza', 'Encargado')
        ON CONFLICT DO NOTHING;
        """
    )
    cur = db_conn.cursor()
    # Insertar un socio y un distribuidor
    cur.execute(
        """
        INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento, nro_documento, direccion, codigo_postal, tipo_cliente)
        VALUES ('TEST Socio 1', 'Ana', 'DNI', '99333444', 'Calle 1', 'TEST5601', 'socio')
        RETURNING id_cliente;
        """
    )
    cur.execute(
        """
        INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento, nro_documento, direccion, codigo_postal, tipo_cliente)
        VALUES ('TEST Dist S.A.', NULL, 'CUIT', '99555666778', 'Ruta 188', 'TEST5601', 'distribuidor')
        RETURNING id_cliente;
        """
    )
    id_dist = cur.fetchone()["id_cliente"]
    cur.execute(
        "INSERT INTO cliente_distribuidor (id_cliente, zona_cobertura, nro_habilitacion) VALUES (%s, 'Cuyo', 'HAB-9901')",
        (id_dist,),
    )

    # Filtrar por socio
    items_socios, total_socios = listar_clientes(db_conn, tipo_cliente="socio")
    assert total_socios >= 1
    assert all(c["tipo_cliente"] == "socio" for c in items_socios)
    assert all(c["descuento_pct"] == Decimal("10.00") for c in items_socios)

    # Filtrar por distribuidor
    items_dist, total_dist = listar_clientes(db_conn, tipo_cliente="distribuidor")
    assert total_dist >= 1
    assert any(c["id_cliente"] == id_dist for c in items_dist)
    dist_item = next(c for c in items_dist if c["id_cliente"] == id_dist)
    assert dist_item["descuento_pct"] == Decimal("20.00")


@pytest.mark.integration
def test_crear_cliente_exportador_con_permisos(db_conn_commit: psycopg.Connection):
    """Prueba alta transaccional de cliente exportador con su subtipo y permisos."""
    db_conn_commit.execute(
        """
        INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
        VALUES ('TEST5602', 'Malargüe', 'Mendoza', 'Encargado')
        ON CONFLICT DO NOTHING;
        """
    )
    datos_exportador = {
        "apellido_razon_social": "TEST Exportadora Global S.A.",
        "nombre": None,
        "tipo_documento": "CUIT",
        "nro_documento": "99888777665",
        "direccion": "Parque Industrial",
        "codigo_postal": "TEST5602",
        "tipo_cliente": "exportador",
        "exportador": {
            "pais_destino": "Brasil",
            "porcentaje_descuento": Decimal("30.00"),
            "permisos": [
                {
                    "codigo": "TEST-EXP-01",
                    "fecha_emision": date(2026, 1, 1),
                    "fecha_vencimiento": date(2027, 1, 1),
                }
            ],
        },
    }

    id_cliente = crear_cliente(db_conn_commit, datos_exportador)
    assert id_cliente > 0

    cliente = obtener_cliente(db_conn_commit, id_cliente)
    assert cliente is not None
    assert cliente["tipo_cliente"] == "exportador"
    assert cliente["descuento_pct"] == Decimal("30.00")
    assert "exportador" in cliente
    assert cliente["exportador"]["pais_destino"] == "Brasil"
    assert len(cliente["exportador"]["permisos"]) == 1
    assert cliente["exportador"]["permisos"][0]["codigo"] == "TEST-EXP-01"

    # Actualizar datos del exportador
    actualizar_cliente(
        db_conn_commit,
        id_cliente,
        {
            "apellido_razon_social": "TEST Exportadora Global Actualizada S.A.",
            "nombre": None,
            "tipo_documento": "CUIT",
            "nro_documento": "99888777665",
            "direccion": "Nueva Dirección 123",
            "codigo_postal": "TEST5602",
            "exportador": {
                "pais_destino": "Uruguay",
                "porcentaje_descuento": Decimal("35.00"),
                "permisos": [
                    {
                        "codigo": "TEST-EXP-02",
                        "fecha_emision": date(2026, 2, 1),
                        "fecha_vencimiento": date(2027, 2, 1),
                    }
                ],
            },
        },
    )

    act = obtener_cliente(db_conn_commit, id_cliente)
    assert act["apellido_razon_social"] == "TEST Exportadora Global Actualizada S.A."
    assert act["exportador"]["pais_destino"] == "Uruguay"
    assert act["descuento_pct"] == Decimal("35.00")
    assert act["exportador"]["permisos"][0]["codigo"] == "TEST-EXP-02"

    # Eliminar exportador directamente falla por restricción de FK en cliente_exportador
    # (En 002_constraints.sql falta ON DELETE CASCADE en fk_cliente_exportador_cliente, reportado en diferencias)
    with pytest.raises(psycopg.errors.ForeignKeyViolation) as exc_info:
        eliminar_cliente(db_conn_commit, id_cliente)
    assert exc_info.value.sqlstate == "23503"

    # Limpieza manual del exportador para no dejar datos residuales
    with db_conn_commit.transaction():
        db_conn_commit.execute(
            "DELETE FROM permiso_exportacion WHERE id_cliente = %s", (id_cliente,)
        )
        db_conn_commit.execute(
            "DELETE FROM cliente_exportador WHERE id_cliente = %s", (id_cliente,)
        )
        db_conn_commit.execute(
            "DELETE FROM cliente WHERE id_cliente = %s", (id_cliente,)
        )

    # En cambio, un cliente distribuidor sí se elimina en cascada correctamente
    id_distribuidor = crear_cliente(
        db_conn_commit,
        {
            "apellido_razon_social": "TEST Dist Borrable S.A.",
            "nombre": None,
            "tipo_documento": "CUIT",
            "nro_documento": "99888777111",
            "direccion": "Ruta 40",
            "codigo_postal": "TEST5602",
            "tipo_cliente": "distribuidor",
            "distribuidor": {
                "zona_cobertura": "Valle de Uco",
                "nro_habilitacion": "HAB-BORRABLE-01",
            },
        },
    )
    filas_del = eliminar_cliente(db_conn_commit, id_distribuidor)
    assert filas_del == 1
    assert obtener_cliente(db_conn_commit, id_distribuidor) is None


@pytest.mark.integration
def test_crear_cliente_incoherencia_subtipo_falla_trigger(db_conn_commit: psycopg.Connection):
    """Prueba que el trigger diferido ctg_cliente_tipo rechace tipo socio con subtipo."""
    db_conn_commit.execute(
        """
        INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
        VALUES ('TEST5603', 'San Rafael Este', 'Mendoza', 'Encargado')
        ON CONFLICT DO NOTHING;
        """
    )
    # Intentamos insertar directamente un cliente marcado como 'socio' pero con fila en cliente_distribuidor
    with pytest.raises(psycopg.errors.RaiseException) as exc_info:
        with db_conn_commit.transaction():
            cur = db_conn_commit.cursor()
            cur.execute(
                """
                INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento, nro_documento, direccion, codigo_postal, tipo_cliente)
                VALUES ('TEST Ilegal', 'Pedro', 'DNI', '99000111', 'Calle X', 'TEST5603', 'socio')
                RETURNING id_cliente;
                """
            )
            cid = cur.fetchone()["id_cliente"]
            cur.execute(
                "INSERT INTO cliente_distribuidor (id_cliente, zona_cobertura, nro_habilitacion) VALUES (%s, 'Zona', 'HAB-ILEGAL')",
                (cid,),
            )
    assert exc_info.value.sqlstate == "P0001"
    assert "Incoherencia de tipo de cliente" in str(exc_info.value)
