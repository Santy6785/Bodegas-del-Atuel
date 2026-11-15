#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Test de determinismo de generar_fechas_comprobantes en db/seed/seed.py.

Comando para correr dentro del contenedor seed:

    docker compose run --rm -v "$($PWD.Path)/db:/work/db" -w /work seed sh -c "pip install -q freezegun && python db/test/test_semilla.py"

freezegun se instala solo para la prueba y NO está en requirements.txt.

Exit codes:
  0 = todas las pruebas pasaron
  1 = falló un assert
  2 = falta freezegun

Pruebas (con asserts reales):
  a) Determinismo en el mismo proceso: dos llamadas a
     generar_fechas_comprobantes(1000, F_PRIMERA_VENTA, FECHA_REF, 1234)
     devuelven listas idénticas.
  b) Invarianza ante el reloj del sistema: bajo freezegun.freeze_time("2026-11-10")
     y freezegun.freeze_time("2027-03-01") las listas son idénticas.
  c) Orden y cotas: 1000 elementos, ordenada ascendente, min >= F_PRIMERA_VENTA
     y max <= FECHA_REF.
  d) Control negativo (regresión del bug original): el comportamiento viejo con
     Faker y date_between(end_date="today") difiere entre las dos fechas de
     sistema, demostrando que el test detecta el problema.
  e) Importar seed NO abre conexión a la base de datos.
"""

import hashlib
import importlib
import sys
from datetime import date
from pathlib import Path

# Agregar la carpeta seed (padre de db/) a sys.path
_seed_dir = Path(__file__).resolve().parents[1] / "seed"
if str(_seed_dir) not in sys.path:
    sys.path.insert(0, str(_seed_dir))


def md5(lista):
    s = "|".join(str(x) for x in lista)
    return hashlib.md5(s.encode("utf-8")).hexdigest()


def test_import_seed_no_db_connection():
    """e) Importar seed NO debe abrir conexión a la BD."""
    connect_called = {"flag": False}

    def fake_connect(*args, **kwargs):
        connect_called["flag"] = True
        raise AssertionError("psycopg.connect se llamo durante el import de seed")

    import psycopg

    orig_connect = psycopg.connect
    psycopg.connect = fake_connect
    try:
        import seed as seed_mod
        importlib.reload(seed_mod)
    finally:
        psycopg.connect = orig_connect

    assert not connect_called["flag"], "Importar seed abrio conexion a la BD"


def lista_vieja_faker():
    """Replica del comportamiento viejo con Faker y date_between(end_date='today')."""
    from faker import Faker

    Faker.seed(1234)
    fake = Faker("es_AR")
    return [fake.date_between(start_date=date(2018, 1, 1), end_date="today") for _ in range(1000)]


def main():
    # Verificar que freezegun este disponible
    try:
        from freezegun import freeze_time
    except ImportError:
        print("ERROR: freezegun no esta instalado. Ejecutá: pip install freezegun")
        sys.exit(2)

    # e) Importar seed sin abrir conexion a la BD
    print("=" * 70)
    print("e) Importar seed NO abre conexion a la BD")
    print("=" * 70)
    test_import_seed_no_db_connection()
    print("  OK: seed se importa sin tocar la BD\n")

    from seed import generar_fechas_comprobantes, F_PRIMERA_VENTA, FECHA_REF

    # a) Determinismo en el mismo proceso
    print("=" * 70)
    print("a) Mismo proceso, misma semilla: dos listas idénticas")
    print("=" * 70)
    l1 = generar_fechas_comprobantes(1000, F_PRIMERA_VENTA, FECHA_REF, 1234)
    l2 = generar_fechas_comprobantes(1000, F_PRIMERA_VENTA, FECHA_REF, 1234)
    print(f"  MD5 lista 1: {md5(l1)}")
    print(f"  MD5 lista 2: {md5(l2)}")
    assert l1 == l2, "FALLO: misma semilla deberia dar resultados idénticos"
    print("  OK: listas idénticas\n")

    # b) Invarianza ante el reloj del sistema
    print("=" * 70)
    print("b) Invarianza ante el reloj del sistema (freezegun): listas idénticas")
    print("=" * 70)

    with freeze_time("2026-11-10"):
        lb1 = generar_fechas_comprobantes(1000, F_PRIMERA_VENTA, FECHA_REF, 1234)
    md5_b1 = md5(lb1)
    print(f"  freeze_time=2026-11-10: MD5={md5_b1}")
    print(f"    Primeras 3: {lb1[:3]}")

    with freeze_time("2027-03-01"):
        lb2 = generar_fechas_comprobantes(1000, F_PRIMERA_VENTA, FECHA_REF, 1234)
    md5_b2 = md5(lb2)
    print(f"  freeze_time=2027-03-01: MD5={md5_b2}")
    print(f"    Primeras 3: {lb2[:3]}")

    assert md5_b1 == md5_b2, (
        "FALLO: version nueva deberia ser idéntica bajo diferentes fechas de sistema"
    )
    print("  OK: version nueva es independiente de la fecha del sistema\n")

    # c) Orden y cotas
    print("=" * 70)
    print("c) Orden y cotas de la lista generada")
    print("=" * 70)
    assert len(lb2) == 1000, f"FALLO: se esperaban 1000 elementos, hay {len(lb2)}"
    assert lb2 == sorted(lb2), "FALLO: la lista no esta ordenada ascendente"
    assert min(lb2) >= F_PRIMERA_VENTA, f"FALLO: min(lista) < F_PRIMERA_VENTA"
    assert max(lb2) <= FECHA_REF, f"FALLO: max(lista) > FECHA_REF"
    print(f"  largo={len(lb2)} ordenado=ascendente min={min(lb2)} max={max(lb2)}")
    print(f"  F_PRIMERA_VENTA={F_PRIMERA_VENTA} FECHA_REF={FECHA_REF}")
    print("  OK: orden y cotas correctos\n")

    # d) Control negativo: version vieja difiere entre fechas de sistema
    print("=" * 70)
    print("d) Control negativo: version VIEJA bajo dos fechas de sistema")
    print("   Las listas DEBEN ser distintas")
    print("=" * 70)

    with freeze_time("2026-11-10"):
        lv1 = lista_vieja_faker()
    md5_v1 = md5([str(x) for x in lv1])
    print(f"  freeze_time=2026-11-10: MD5={md5_v1}")
    print(f"    Primeras 3: {lv1[:3]}")

    with freeze_time("2027-03-01"):
        lv2 = lista_vieja_faker()
    md5_v2 = md5([str(x) for x in lv2])
    print(f"  freeze_time=2027-03-01: MD5={md5_v2}")
    print(f"    Primeras 3: {lv2[:3]}")

    assert lv1 != lv2, (
        "FALLO: version vieja deberia diferir entre fechas de sistema"
    )
    print("  OK: prueba negativa confirma que el test detecta el problema\n")

    print("TODAS LAS PRUEBAS PASARON")


if __name__ == "__main__":
    main()
