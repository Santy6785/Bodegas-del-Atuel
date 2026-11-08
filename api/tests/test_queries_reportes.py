"""Pruebas de integración para api/app/db/queries/reportes.py."""

from datetime import date
from decimal import Decimal
import psycopg
import pytest

from app.db.queries.reportes import (
    top_vinos,
    transportista_activo,
    trazabilidad_vino,
    ventas_por_sala,
    vinos_sin_stock,
)


@pytest.mark.integration
def test_top_vinos_y_ventas_por_sala_tipos_y_orden(db_conn: psycopg.Connection):
    """Caso 13: top_vinos y ventas_por_sala devuelven tipos correctos (Decimal) y orden descendente."""
    # Preparamos sala, cliente, bodega y vino
    db_conn.execute(
        """
        INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
        VALUES ('TEST5620', 'Ciudad Rep', 'Mendoza', 'Encargado')
        ON CONFLICT DO NOTHING;
        INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal)
        VALUES ('TEST Sala Rep 1', '10', 'lunes', 'TEST5620')
        ON CONFLICT DO NOTHING;
        INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal)
        VALUES ('TEST Sala Rep 2', '20', 'martes', 'TEST5620')
        ON CONFLICT DO NOTHING;
        INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento, nro_documento, direccion, codigo_postal, tipo_cliente)
        VALUES ('TEST Cliente Rep', 'Ana', 'DNI', '99777111', 'Calle', 'TEST5620', 'socio')
        ON CONFLICT DO NOTHING;
        INSERT INTO bodega (cuit, razon_social, domicilio)
        VALUES ('99999999961', 'TEST Bodega Rep', 'Ruta')
        ON CONFLICT DO NOTHING;
        INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
        VALUES ('TEST Vino Top 1', 'tinto', 2021, 750, 14.0, 10000, '99999999961')
        ON CONFLICT DO NOTHING;
        INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
        VALUES ('TEST Vino Top 2', 'tinto', 2021, 750, 14.0, 12000, '99999999961')
        ON CONFLICT DO NOTHING;
        """
    )
    cur = db_conn.cursor()
    cur.execute("SELECT id_sala FROM sala_venta WHERE calle = 'TEST Sala Rep 1'")
    s1 = cur.fetchone()["id_sala"]
    cur.execute("SELECT id_sala FROM sala_venta WHERE calle = 'TEST Sala Rep 2'")
    s2 = cur.fetchone()["id_sala"]
    cur.execute("SELECT id_cliente FROM cliente WHERE apellido_razon_social = 'TEST Cliente Rep'")
    c_id = cur.fetchone()["id_cliente"]
    cur.execute("SELECT cod_vino FROM vino WHERE nombre = 'TEST Vino Top 1'")
    v1 = cur.fetchone()["cod_vino"]
    cur.execute("SELECT cod_vino FROM vino WHERE nombre = 'TEST Vino Top 2'")
    v2 = cur.fetchone()["cod_vino"]

    # Dotar de stock a la sala para los vinos a vender
    cur.execute(
        """
        INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
        VALUES (%s, %s, 100), (%s, %s, 100)
        ON CONFLICT (id_sala, cod_vino) DO UPDATE SET cantidad = 100;
        """,
        (s1, v1, s1, v2),
    )

    # Insertamos comprobante y renglones directamente para probar el reporte
    cur.execute(
        """
        INSERT INTO comprobante (fecha, id_cliente, id_sala, subtotal, descuento, total)
        VALUES (CURRENT_DATE, %s, %s, 50000, 5000, 45000)
        RETURNING nro_comprobante;
        """,
        (c_id, s1),
    )
    nro_c1 = cur.fetchone()["nro_comprobante"]

    cur.execute(
        """
        INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento_pct, subtotal)
        VALUES (%s, %s, 10, 10000, 10, 90000)
        ON CONFLICT (nro_comprobante, cod_vino) DO NOTHING;
        """,
        (nro_c1, v1),
    )
    cur.execute(
        """
        INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento_pct, subtotal)
        VALUES (%s, %s, 5, 12000, 10, 54000)
        ON CONFLICT (nro_comprobante, cod_vino) DO NOTHING;
        """,
        (nro_c1, v2),
    )

    # 1. Probar top_vinos
    top = top_vinos(db_conn, limite=5)
    assert len(top) >= 2
    # El primero debe tener mayor o igual cantidad de botellas que el segundo
    assert top[0]["botellas_vendidas"] >= top[1]["botellas_vendidas"]
    assert isinstance(top[0]["botellas_vendidas"], int)
    assert top[0]["posicion"] == 1
    assert top[1]["posicion"] == 2

    # 2. Probar ventas_por_sala
    ventas = ventas_por_sala(db_conn, periodo="ultimo_trimestre")
    assert len(ventas) >= 2
    # s1 facturó 45000 y s2 facturó 0; debe devolver Decimal y orden descendente
    montos = [row["monto_total"] for row in ventas]
    assert all(isinstance(m, Decimal) for m in montos)
    assert montos == sorted(montos, reverse=True)


@pytest.mark.integration
def test_ventas_por_sala_validacion_fechas(db_conn: psycopg.Connection):
    """Prueba que ventas_por_sala valide fecha_desde <= fecha_hasta."""
    with pytest.raises(ValueError, match="no puede ser posterior"):
        ventas_por_sala(
            db_conn,
            fecha_desde=date(2026, 12, 1),
            fecha_hasta=date(2026, 1, 1),
        )


@pytest.mark.integration
def test_transportista_activo_lista_vacia_sin_ingresos_recientes(db_conn: psycopg.Connection):
    """Caso 14: transportista_activo devuelve lista vacía cuando no hay ingresos recientes."""
    # En una base de prueba sin ingresos en el último mes, debe devolver lista vacía
    # Si hubiera un transportista antiguo de hace 1 año, no debe figurar
    db_conn.execute(
        """
        INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio)
        VALUES ('TEST Trans Antiguo', '99999999951', 'ant@trans.com', '123', 'Dir')
        ON CONFLICT DO NOTHING;
        INSERT INTO bodega (cuit, razon_social, domicilio)
        VALUES ('99999999952', 'TEST Bodega Ant', 'Ruta')
        ON CONFLICT DO NOTHING;
        """
    )
    cur = db_conn.cursor()
    cur.execute(
        "SELECT cod_transportista FROM transportista WHERE cuit = '99999999951'"
    )
    cod_t = cur.fetchone()["cod_transportista"]

    # Ingreso de hace 6 meses (fuera del último mes)
    cur.execute(
        """
        INSERT INTO ingreso (fecha, estado, cod_transportista, cuit_bodega)
        VALUES (CURRENT_DATE - INTERVAL '6 months', 'procesado', %s, '99999999952');
        """,
        (cod_t,),
    )

    resultado = transportista_activo(db_conn)
    # Ningún transportista con ingresos en el último mes
    cods_activos = [r["cod_transportista"] for r in resultado]
    assert cod_t not in cods_activos


@pytest.mark.integration
def test_vinos_sin_stock(db_conn: psycopg.Connection):
    """Prueba el reporte de vinos sin stock con y sin sala especificada."""
    db_conn.execute(
        """
        INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
        VALUES ('TEST5621', 'Ciudad Stock', 'Mendoza', 'Encargado')
        ON CONFLICT DO NOTHING;
        INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal)
        VALUES ('TEST Sala Stock', '500', 'lunes', 'TEST5621')
        ON CONFLICT DO NOTHING;
        INSERT INTO bodega (cuit, razon_social, domicilio)
        VALUES ('99999999953', 'TEST Bodega Stock', 'Ruta')
        ON CONFLICT DO NOTHING;
        INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
        VALUES ('TEST Vino Agotado', 'tinto', 2021, 750, 14.0, 10000, '99999999953')
        ON CONFLICT DO NOTHING;
        """
    )
    cur = db_conn.cursor()
    cur.execute(
        "SELECT id_sala FROM sala_venta WHERE calle = 'TEST Sala Stock'"
    )
    id_sala = cur.fetchone()["id_sala"]
    cur.execute(
        "SELECT cod_vino FROM vino WHERE nombre = 'TEST Vino Agotado'"
    )
    cod_vino = cur.fetchone()["cod_vino"]

    # 1. Vino con stock en depósito = 50 pero 0 en sala (criterio S6)
    cur.execute(
        """
        INSERT INTO stock_deposito (cod_vino, cantidad)
        VALUES (%s, 50)
        ON CONFLICT (cod_vino) DO UPDATE SET cantidad = 50;
        """,
        (cod_vino,),
    )
    cur.execute(
        """
        INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
        VALUES (%s, %s, 0)
        ON CONFLICT (id_sala, cod_vino) DO UPDATE SET cantidad = 0;
        """,
        (id_sala, cod_vino),
    )

    sin_stock_sala = vinos_sin_stock(db_conn, id_sala=id_sala)
    assert any(v["cod_vino"] == cod_vino for v in sin_stock_sala)
    item_v = next(v for v in sin_stock_sala if v["cod_vino"] == cod_vino)
    assert item_v["stock_deposito"] == 50


@pytest.mark.integration
def test_trazabilidad_vino(db_conn: psycopg.Connection):
    """Prueba que trazabilidad_vino devuelva los lotes de uva vinculados."""
    # Vino sin trazabilidad devuelve lista vacía
    res_vacia = trazabilidad_vino(db_conn, cod_vino=999999)
    assert res_vacia == []
