"""Pruebas de integración para api/app/db/queries/catalogos.py."""

import psycopg
import pytest

from app.db.queries.catalogos import (
    listar_bodegas,
    listar_cepas,
    listar_localidades,
    listar_maridajes,
    listar_salas,
    listar_transportistas,
)


@pytest.mark.integration
def test_catalogos_lectura_y_estructura(db_conn: psycopg.Connection):
    """Verifica que todos los catálogos devuelvan listas de diccionarios con las claves esperadas."""
    # Insertamos un registro de cada tipo para asegurar contenido
    db_conn.execute(
        """
        INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
        VALUES ('TEST9999', 'Localidad Cat', 'Mendoza', 'Encargado')
        ON CONFLICT DO NOTHING;
        INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal)
        VALUES ('TEST Calle Cat', '1', 'lunes', 'TEST9999')
        ON CONFLICT DO NOTHING;
        INSERT INTO cepa (nombre, tipo) VALUES ('TEST Cepa Cat', 'tinta') ON CONFLICT DO NOTHING;
        INSERT INTO bodega (cuit, razon_social, domicilio)
        VALUES ('99999999941', 'TEST Bodega Cat', 'Ruta 1')
        ON CONFLICT DO NOTHING;
        INSERT INTO maridaje (nombre, temperatura_servicio) VALUES ('TEST Maridaje Cat', 16) ON CONFLICT DO NOTHING;
        INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio)
        VALUES ('TEST Trans Cat', '99999999942', 'cat@trans.com', '123', 'Dir')
        ON CONFLICT DO NOTHING;
        """
    )

    # 1. Salas
    salas = listar_salas(db_conn)
    assert isinstance(salas, list)
    assert len(salas) >= 1
    assert {"id_sala", "calle", "numero", "dia_cierre", "codigo_postal"}.issubset(
        salas[0].keys()
    )

    # 2. Cepas
    cepas = listar_cepas(db_conn)
    assert isinstance(cepas, list)
    assert len(cepas) >= 1
    assert {"id_cepa", "nombre", "tipo"}.issubset(cepas[0].keys())

    # 3. Bodegas
    bodegas = listar_bodegas(db_conn)
    assert isinstance(bodegas, list)
    assert len(bodegas) >= 1
    assert {"cuit", "razon_social", "domicilio"}.issubset(bodegas[0].keys())

    # 4. Maridajes
    maridajes = listar_maridajes(db_conn)
    assert isinstance(maridajes, list)
    assert len(maridajes) >= 1
    assert {"id_maridaje", "nombre", "temperatura_servicio"}.issubset(
        maridajes[0].keys()
    )

    # 5. Transportistas
    transportistas = listar_transportistas(db_conn)
    assert isinstance(transportistas, list)
    assert len(transportistas) >= 1
    assert {"cod_transportista", "razon_social", "cuit"}.issubset(
        transportistas[0].keys()
    )

    # 6. Localidades
    localidades = listar_localidades(db_conn)
    assert isinstance(localidades, list)
    assert len(localidades) >= 1
    assert {"codigo_postal", "nombre", "provincia"}.issubset(
        localidades[0].keys()
    )
