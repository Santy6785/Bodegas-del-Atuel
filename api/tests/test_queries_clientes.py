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
    # descuento_pct proviene de fn_descuento_cliente (DEFAULT 30.00 en la base)
    assert cliente["descuento_pct"] == Decimal("30.00")
    assert "exportador" in cliente
    assert cliente["exportador"]["pais_destino"] == "Brasil"
    assert len(cliente["exportador"]["permisos"]) == 1
    assert cliente["exportador"]["permisos"][0]["codigo"] == "TEST-EXP-01"

    # Actualizar datos del exportador (sin campo calculado porcentaje_descuento)
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
    # descuento_pct no se envió en la actualización: se mantiene el DEFAULT 30.00
    assert act["descuento_pct"] == Decimal("30.00")
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
def test_listar_clientes_filtro_q(db_conn_commit: psycopg.Connection):
    """Caso: q de GET /clientes filtra por apellido, por prefijo de documento y trata % como literal.

    Crea dos clientes con apellidos distintos y comprueba:
      - q="Per" devuelve solo el cliente cuyo apellido contiene "Per".
      - q="30123" devuelve solo el cliente cuyo documento empieza con ese prefijo.
      - q="%" devuelve cero resultados (el % se trata como texto literal, no como comodín).
    """
    db_conn_commit.execute(
        """
        INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
        VALUES ('TEST5610', 'San Rafael', 'Mendoza', 'Encargado')
        ON CONFLICT DO NOTHING;
        """
    )
    cur = db_conn_commit.cursor()
    # Cliente 1: apellido Peralta (contiene "Per"), documento 30123456 (prefijo 30123)
    cur.execute(
        """
        INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento, nro_documento, direccion, codigo_postal, tipo_cliente)
        VALUES ('TEST Peralta', 'Juan', 'DNI', '30123456', 'Calle Falsa 123', 'TEST5610', 'socio')
        RETURNING id_cliente;
        """
    )
    id_peralta = cur.fetchone()["id_cliente"]
    # Cliente 2: apellido García (no contiene "Per"), documento 40987654 (no empieza con 30123)
    cur.execute(
        """
        INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento, nro_documento, direccion, codigo_postal, tipo_cliente)
        VALUES ('TEST García', 'María', 'DNI', '40987654', 'Avenida Siempre Viva 742', 'TEST5610', 'socio')
        RETURNING id_cliente;
        """
    )
    id_garcia = cur.fetchone()["id_cliente"]

    try:
        # q="Per" filtra por apellido que contiene "Per" (case-insensitive)
        items, total = listar_clientes(db_conn_commit, q="Per")
        assert total == 1
        assert items[0]["id_cliente"] == id_peralta
        assert items[0]["apellido_razon_social"] == "TEST Peralta"

        # q="30123" filtra por prefijo de documento
        items, total = listar_clientes(db_conn_commit, q="30123")
        assert total == 1
        assert items[0]["id_cliente"] == id_peralta
        assert items[0]["nro_documento"] == "30123456"

        # q="%" trata % como literal: no coincide con ningún documento ni apellido
        items, total = listar_clientes(db_conn_commit, q="%")
        assert total == 0
        assert items == []
    finally:
        # Limpieza manual de los clientes creados (prefijo TEST no alcanza: el conftest
        # solo borra apellidos/documentos TEST o 99%, y estos apellidos no empiezan por TEST)
        db_conn_commit.execute(
            "DELETE FROM cliente WHERE id_cliente IN (%s, %s)", (id_peralta, id_garcia)
        )


@pytest.mark.integration
def test_listar_clientes_filtro_q_documento_con_separadores(
    db_conn_commit: psycopg.Connection,
):
    """q con separadores de documento se normaliza y busca por prefijo de nro_documento.

    Crea dos clientes y comprueba:
      - q="301234" encuentra el cliente con documento 30123456.
      - q="30-1234" (con guion) devuelve lo mismo que q="301234".
      - q="12.345" (con punto) matchea el prefijo 12345 de otro cliente.
    """
    db_conn_commit.execute(
        """
        INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
        VALUES ('TEST5611', 'San Rafael', 'Mendoza', 'Encargado')
        ON CONFLICT DO NOTHING;
        """
    )
    cur = db_conn_commit.cursor()
    cur.execute(
        """
        INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento, nro_documento, direccion, codigo_postal, tipo_cliente)
        VALUES ('TEST Doc Guion', 'Juan', 'DNI', '30123456', 'Calle 1', 'TEST5611', 'socio')
        RETURNING id_cliente;
        """
    )
    id_guion = cur.fetchone()["id_cliente"]
    cur.execute(
        """
        INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento, nro_documento, direccion, codigo_postal, tipo_cliente)
        VALUES ('TEST Doc Punto', 'María', 'DNI', '12345678', 'Calle 2', 'TEST5611', 'socio')
        RETURNING id_cliente;
        """
    )
    id_punto = cur.fetchone()["id_cliente"]
    cur.execute(
        """
        INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento, nro_documento, direccion, codigo_postal, tipo_cliente)
        VALUES ('TEST Otro', 'Luis', 'DNI', '40987654', 'Calle 3', 'TEST5611', 'socio')
        RETURNING id_cliente;
        """
    )
    id_otro = cur.fetchone()["id_cliente"]

    try:
        # q="301234" encuentra el documento 30123456
        items, total = listar_clientes(db_conn_commit, q="301234")
        assert total == 1
        assert items[0]["id_cliente"] == id_guion
        assert items[0]["nro_documento"] == "30123456"

        # q="30-1234" (con guion) devuelve lo mismo que q="301234"
        items_g, total_g = listar_clientes(db_conn_commit, q="30-1234")
        assert total_g == total
        assert [c["id_cliente"] for c in items_g] == [c["id_cliente"] for c in items]

        # q="12.345" (con punto) matchea el prefijo 12345 del otro cliente
        items_p, total_p = listar_clientes(db_conn_commit, q="12.345")
        assert total_p == 1
        assert items_p[0]["id_cliente"] == id_punto
        assert items_p[0]["nro_documento"] == "12345678"

        # El cliente cuyo documento no empieza con ninguno de esos prefijos no aparece
        ids_devueltos = {c["id_cliente"] for c in items_g} | {c["id_cliente"] for c in items_p}
        assert id_otro not in ids_devueltos
    finally:
        db_conn_commit.execute(
            "DELETE FROM cliente WHERE id_cliente IN (%s, %s, %s)",
            (id_guion, id_punto, id_otro),
        )


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
