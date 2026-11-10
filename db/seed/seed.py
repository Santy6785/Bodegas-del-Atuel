#!/usr/bin/env python3
"""db/seed/seed.py – Carga masiva determinística de Bodegas del Atuel.

Ejecuta EXCLUSIVAMENTE sobre bodegas_atuel_bench (base descartable de bench),
nunca sobre bodegas_atuel.

Flujo (según consigna Etapa 3):
  1. Verifica migraciones y usuario owner_bodegas.
  2. Ejecuta 01_pre_carga.sql (deshabilita triggers críticos de stock/estado/fecha).
  3. Carga catálogos reales desde CSV (cepa, maridaje, localidad, departamento,
     bodega) y datos maestros con Faker (seed 1234).
  4. Genera stock suficiente (depósito + salas) para evitar ventas con stock
     negativo (RN-09).
  5. Inserta comprobantes y renglones masivamente con COPY (método más rápido
     del benchmark).
  6. Ejecuta 03_post_carga.sql (habilita triggers, valida tgenabled='O', setval
     de secuencias IDENTITY, REFRESH MATERIALIZED VIEW, ANALYZE).
  7. Recalcula totales de comprobante (quedaron en 0 mientras triggers
     deshabilitados) para que C5 de 02_controles.sql devuelva 0 filas.

Variables de entorno: PGDATABASE, PGUSER, PGHOST, PGPORT, PGPASSWORD.
Dentro del contenedor bodegas-db se usa el socket local (trust).
"""
import csv
import os
import random
import sys
import time
from datetime import date

import psycopg
from faker import Faker

# ---------------------------------------------------------------------------
# Semillas determinísticas (obligatorio)
# ---------------------------------------------------------------------------
Faker.seed(1234)
random.seed(1234)
fake = Faker("es_AR")

DBNAME = os.environ.get("PGDATABASE", "bodegas_atuel_bench")
USER = os.environ.get("PGUSER", "owner_bodegas")
HOST = os.environ.get("PGHOST")          # None => socket local de Unix
PORT = os.environ.get("PGPORT", "5432")
PASSWORD = os.environ.get("PGPASSWORD")

SEED_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "catalogos")
SQL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sql")

RUTA_01 = os.path.join(SQL_DIR, "01_pre_carga.sql")
RUTA_03 = os.path.join(SQL_DIR, "03_post_carga.sql")

# ---------------------------------------------------------------------------
# Volúmenes objetivo (TPI: >150.000 comprobantes, >500.000 renglones)
# ---------------------------------------------------------------------------
N_FINCAS = 8
N_PARCELAS_POR_FINCA = 3
N_VINOS = 40
N_CLIENTES = 200
N_SALAS = 15
N_TRANSPORTISTAS = 6
N_COMPROBANTES = 170000          # > 150.000 (TPI)
MIN_RENGLONES_X_COMPROBANTE = 3
MAX_RENGLONES_X_COMPROBANTE = 5
# Stock inicial por vino en depósito (botellas)
STOCK_DEPOSITO_POR_VINO = 200000
# Stock transferido a cada sala por vino (botellas)
STOCK_SALA_POR_VINO = 60000


# ---------------------------------------------------------------------------
# Conexión
# ---------------------------------------------------------------------------
def conectar():
    kwargs = dict(dbname=DBNAME, user=USER, port=PORT)
    if HOST:
        kwargs["host"] = HOST
    if PASSWORD:
        kwargs["password"] = PASSWORD
    return psycopg.connect(**kwargs)


def ejecutar_sql_archivo(con, ruta, etiqueta):
    t0 = time.perf_counter()
    with open(ruta, "r", encoding="utf-8") as f:
        sql = f.read()
    with con.cursor() as cur:
        cur.execute(sql)
    con.commit()
    dt = time.perf_counter() - t0
    print(f"[OK] {etiqueta}: {dt:.3f}s")


# ---------------------------------------------------------------------------
# Catálogos desde CSV
# ---------------------------------------------------------------------------
def cargar_csv(nombre_archivo):
    ruta = os.path.join(SEED_DIR, nombre_archivo)
    with open(ruta, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def insertar_catalogos(con):
    """departamento, localidad, bodega, cepa, maridaje (IDs reales de CSV)."""
    with con.cursor() as cur:
        for d in cargar_csv("departamento.csv"):
            cur.execute(
                "INSERT INTO departamento (id_departamento, nombre, provincia) "
                "OVERRIDING SYSTEM VALUE VALUES (%s, %s, %s)",
                (int(d["id_departamento"]), d["nombre"], d["provincia"]),
            )
        for l in cargar_csv("localidad.csv"):
            cur.execute(
                "INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional) "
                "VALUES (%s, %s, %s, %s)",
                (l["codigo_postal"], l["nombre"], l["provincia"], l["encargado_regional"]),
            )
        for b in cargar_csv("bodega.csv"):
            cur.execute(
                "INSERT INTO bodega (cuit, razon_social, domicilio) VALUES (%s, %s, %s)",
                (b["cuit"], b["razon_social"], b["domicilio"]),
            )
        for c in cargar_csv("cepa.csv"):
            cur.execute(
                "INSERT INTO cepa (id_cepa, nombre, tipo) "
                "OVERRIDING SYSTEM VALUE VALUES (%s, %s, %s)",
                (int(c["id_cepa"]), c["nombre"], c["tipo"]),
            )
        for m in cargar_csv("maridaje.csv"):
            cur.execute(
                "INSERT INTO maridaje (id_maridaje, nombre, temperatura_servicio) "
                "OVERRIDING SYSTEM VALUE VALUES (%s, %s, %s)",
                (int(m["id_maridaje"]), m["nombre"], int(m["temperatura_servicio"])),
            )
    con.commit()


# ---------------------------------------------------------------------------
# Datos maestros
# ---------------------------------------------------------------------------
def insertar_maestros(con):
    """Fincas, parcelas, lotes de uva, vinos, composición, maridaje, trazabilidad."""
    with con.cursor() as cur:
        cuits = ["20123456781", "20123456782", "20123456783",
                 "20123456784", "20123456785"]
        cepa_ids = list(range(1, 9))
        mar_id_range = list(range(1, 9))

        # Fincas
        finca_ids = []
        for i in range(1, N_FINCAS + 1):
            id_dep = ((i - 1) % 5) + 1
            cur.execute(
                "INSERT INTO finca (id_finca, nombre, superficie_ha, id_departamento) "
                "OVERRIDING SYSTEM VALUE VALUES (%s, %s, %s, %s) RETURNING id_finca",
                (i, f"Finca {fake.company()}", round(random.uniform(50, 500), 2), id_dep),
            )
            finca_ids.append(cur.fetchone()[0])

        # Parcelas + lotes (cosecha en 2023, antes de ingreso/venta)
        id_lote = 1
        lotes_por_bodega = {c: [] for c in cuits}
        for finca_id in finca_ids:
            parcelas_de_finca = 0
            for _ in range(N_PARCELAS_POR_FINCA):
                parcelas_de_finca += 1
                id_cepa = random.choice(cepa_ids)
                cur.execute(
                    "INSERT INTO parcela (id_finca, nro_parcela, superficie_ha, "
                    "anio_plantacion, id_cepa) "
                    "VALUES (%s, %s, %s, %s, %s)",
                    (finca_id, parcelas_de_finca,
                     round(random.uniform(5, 50), 2),
                     random.randint(2010, 2023), id_cepa),
                )
                cuit_bodega_lote = random.choice(cuits)
                cur.execute(
                    "INSERT INTO lote_uva (id_lote, id_finca, nro_parcela, campania, "
                    "nro_lote, fecha_cosecha, kilos, cuit_bodega) "
                    "OVERRIDING SYSTEM VALUE VALUES (%s, %s, %s, %s, %s, %s, %s, %s) "
                    "RETURNING id_lote",
                    (
                        id_lote, finca_id, parcelas_de_finca,
                        random.randint(2020, 2023), id_lote,
                        date(2023, random.randint(1, 12), random.randint(1, 28)),
                        round(random.uniform(1000, 20000), 2),
                        cuit_bodega_lote,
                    ),
                )
                lotes_por_bodega[cuit_bodega_lote].append(id_lote)
                id_lote += 1

        # Vinos + composición (suma EXACTAMENTE 100) + maridaje + trazabilidad
        for i in range(1, N_VINOS + 1):
            cuit_bodega_vino = random.choice(cuits)
            cur.execute(
                "INSERT INTO vino (cod_vino, nombre, tipo, anada, volumen_ml, "
                "graduacion, precio, cuit_bodega) "
                "OVERRIDING SYSTEM VALUE VALUES (%s, %s, %s, %s, %s, %s, %s, %s) "
                "RETURNING cod_vino",
                (
                    i, f"Vino {fake.word().capitalize()} {i}",
                    random.choice(["tinto", "blanco", "rosado", "espumante"]),
                    random.randint(2018, 2023), 750,
                    round(random.uniform(5, 20), 2),
                    round(random.uniform(500, 3000), 2),
                    cuit_bodega_vino,
                ),
            )
            cod_vino = cur.fetchone()[0]
            c1, c2 = random.sample(cepa_ids, 2)
            cur.execute(
                "INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje) "
                "VALUES (%s, %s, %s)", (cod_vino, c1, 70.00),
            )
            cur.execute(
                "INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje) "
                "VALUES (%s, %s, %s)", (cod_vino, c2, 30.00),
            )
            for id_m in random.sample(mar_id_range, 2):
                cur.execute(
                    "INSERT INTO vino_maridaje (cod_vino, id_maridaje) "
                    "VALUES (%s, %s)", (cod_vino, id_m),
                )
            # Trazabilidad: lote de la misma bodega que el vino
            id_lote_elegido = random.choice(lotes_por_bodega[cuit_bodega_vino])
            cur.execute(
                "INSERT INTO vino_lote (cod_vino, id_lote) VALUES (%s, %s)",
                (cod_vino, id_lote_elegido),
            )
    con.commit()


def insertar_clientes(con):
    """Clientes con subtipos y permisos de exportación (determinan descuento 30/35)."""
    with con.cursor() as cur:
        codigos_postales = ["5500", "5505", "5561", "5565", "5515", "5530",
                            "5507", "5550", "5562", "5509"]
        for i in range(1, N_CLIENTES + 1):
            tipo = random.choice(["socio", "distribuidor", "exportador"])
            cur.execute(
                "INSERT INTO cliente (id_cliente, apellido_razon_social, nombre, "
                "tipo_documento, nro_documento, direccion, codigo_postal, "
                "fecha_alta, tipo_cliente) "
                "OVERRIDING SYSTEM VALUE VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s) "
                "RETURNING id_cliente",
                (
                    i, fake.last_name(), fake.first_name(),
                    random.choice(["DNI", "CUIT", "CUIL", "PASAPORTE"]),
                    f"{random.randint(10000000, 99999999)}",
                    fake.street_address(), random.choice(codigos_postales),
                    date(2018, random.randint(1, 12), random.randint(1, 28)),
                    tipo,
                ),
            )
            id_cliente = cur.fetchone()[0]
            if tipo == "distribuidor":
                cur.execute(
                    "INSERT INTO cliente_distribuidor (id_cliente, zona_cobertura, nro_habilitacion) "
                    "VALUES (%s, %s, %s)",
                    (id_cliente, fake.city(), f"HAB-{id_cliente:05d}"),
                )
            elif tipo == "exportador":
                cur.execute(
                    "INSERT INTO cliente_exportador (id_cliente, pais_destino, porcentaje_descuento) "
                    "VALUES (%s, %s, %s)",
                    (id_cliente, fake.country(), 30.00),
                )
                for j in range(random.randint(1, 4)):
                    cur.execute(
                        "INSERT INTO permiso_exportacion (id_cliente, codigo, fecha_emision, "
                        "fecha_vencimiento) VALUES (%s, %s, %s, %s)",
                        (
                            id_cliente, f"PERM-{id_cliente}-{j:02d}",
                            date(2022, random.randint(1, 12), random.randint(1, 28)),
                            date(2024, random.randint(1, 12), random.randint(1, 28)),
                        ),
                    )
    con.commit()


def insertar_salas_y_transportistas(con):
    with con.cursor() as cur:
        codigos_postales = ["5500", "5505", "5561", "5565", "5515", "5530",
                            "5507", "5550", "5562", "5509"]
        dias = ["lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo"]
        for i in range(1, N_SALAS + 1):
            cur.execute(
                "INSERT INTO sala_venta (id_sala, calle, numero, dia_cierre, codigo_postal) "
                "OVERRIDING SYSTEM VALUE VALUES (%s, %s, %s, %s, %s)",
                (i, fake.street_name(), str(random.randint(1, 999)),
                 random.choice(dias), random.choice(codigos_postales)),
            )
        for i in range(1, N_TRANSPORTISTAS + 1):
            cur.execute(
                "INSERT INTO transportista (cod_transportista, razon_social, cuit, email, "
                "telefono, domicilio) OVERRIDING SYSTEM VALUE VALUES (%s, %s, %s, %s, %s, %s)",
                (
                    i, fake.company(),
                    f"20{random.randint(100000000, 999999999)}",
                    fake.email(), f"+54 9 260 {random.randint(1000000, 9999999)}",
                    fake.address(),
                ),
            )
            cur.execute(
                "INSERT INTO transportista_localidad (cod_transportista, codigo_postal) "
                "VALUES (%s, %s)", (i, random.choice(codigos_postales)),
            )
    con.commit()


# ---------------------------------------------------------------------------
# Stock: depósito central + salas de venta (persistido en DB)
# ---------------------------------------------------------------------------
def poblar_stock(con, vinos, salas):
    """Crea stock_deposito y stock_sala con volumen suficiente para las ventas."""
    t0 = time.perf_counter()
    with con.cursor() as cur:
        # stock_deposito: una fila por vino
        filas_deposito = [(v, STOCK_DEPOSITO_POR_VINO) for v in vinos]
        args = ",".join(
            f"({v},{c})" for v, c in filas_deposito
        )
        cur.execute(
            f"INSERT INTO stock_deposito (cod_vino, cantidad) VALUES {args}"
        )

        # stock_sala: una fila por (id_sala, cod_vino)
        filas_sala = []
        for s in salas:
            for v in vinos:
                filas_sala.append((s, v, STOCK_SALA_POR_VINO))
        args = ",".join(
            f"({s},{v},{c})" for s, v, c in filas_sala
        )
        cur.execute(
            f"INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES {args}"
        )
    con.commit()
    dt = time.perf_counter() - t0
    print(f"[OK] Stock poblado: deposito={len(vinos)} vinos, "
          f"salas={len(salas)*len(vinos)} pares en {dt:.3f}s")
    return {v: STOCK_DEPOSITO_POR_VINO for v in vinos}, \
           {(s, v): STOCK_SALA_POR_VINO for s in salas for v in vinos}


def poblar_movimientos_stock(con, vinos, salas, bodega_cuits):
    """Crea ingresos y transferencias que justifican el stock inicial,
    para que C7 y C8 de 02_controles.sql devuelvan cero filas."""
    t0 = time.perf_counter()
    with con.cursor() as cur:
        stock_total_por_vino = STOCK_DEPOSITO_POR_VINO + STOCK_SALA_POR_VINO * len(salas)
        # 1) Un ingreso por vino con stock_total = deposito + todas las salas
        for idx, v in enumerate(vinos, start=1):
            cur.execute(
                "INSERT INTO ingreso (cod_ingreso, fecha, estado, cod_transportista, "
                "cuit_bodega) OVERRIDING SYSTEM VALUE VALUES (%s, %s, %s, %s, %s)",
                (idx, date(2023, 1, 1), 'procesado',
                 ((idx - 1) % N_TRANSPORTISTAS) + 1,
                 bodega_cuits[(idx - 1) % len(bodega_cuits)]),
            )
            cur.execute(
                "INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad) "
                "VALUES (%s, %s, %s)",
                (idx, v, stock_total_por_vino),
            )

        # 2) Una transferencia por (sala, vino) con STOCK_SALA_POR_VINO
        nro = len(vinos) + 1
        for s in salas:
            for v in vinos:
                cur.execute(
                    "INSERT INTO transferencia (nro_transferencia, id_sala, fecha_confeccion, "
                    "estado) OVERRIDING SYSTEM VALUE VALUES (%s, %s, %s, %s)",
                    (nro, s, date(2023, 1, 2), 'procesado'),
                )
                cur.execute(
                    "INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad) "
                    "VALUES (%s, %s, %s)",
                    (nro, v, STOCK_SALA_POR_VINO),
                )
                nro += 1
    con.commit()
    dt = time.perf_counter() - t0
    print(f"[OK] Movimientos de stock: {len(vinos)} ingresos, "
          f"{len(salas)*len(vinos)} transferencias en {dt:.3f}s")


# ---------------------------------------------------------------------------
# Ventas masivas: comprobantes + renglones con COPY
# ---------------------------------------------------------------------------
def descuento_por_cliente_map(con):
    """RN-06: socio 10, distribuidor 20, exportador su porcentaje_descuento."""
    with con.cursor() as cur:
        cur.execute("""
            SELECT c.id_cliente,
                   CASE c.tipo_cliente
                     WHEN 'socio' THEN 10
                     WHEN 'distribuidor' THEN 20
                     ELSE COALESCE(e.porcentaje_descuento, 30)
                   END
            FROM cliente c
            LEFT JOIN cliente_exportador e ON e.id_cliente = c.id_cliente
        """)
        return {r[0]: float(r[1]) for r in cur.fetchall()}


def generar_ventas(con, salas, stock_sala_disp, vinos, precio_por_vino,
                   descuento_por_cliente):
    """Insertar comprobantes (lotes con INSERT ... VALUES) y renglones (COPY).
    Stock de sala gestionado internamente para no generar stock negativo (RN-09)."""
    t0 = time.perf_counter()

    # stock disponible mutable por (id_sala, cod_vino)
    stock_disp = dict(stock_sala_disp)

    comprobante_rows = []   # (nro, fecha, id_cliente, id_sala)
    renglon_rows = []       # (nro, cod_vino, cantidad, precio, desc_pct, subtotal)
    total_renglones = 0

    # obtener max nro_comprobante existente
    with con.cursor() as cur:
        cur.execute("SELECT COALESCE(MAX(nro_comprobante), 0) FROM comprobante")
        nro_base = cur.fetchone()[0]

    for i in range(1, N_COMPROBANTES + 1):
        nro = nro_base + i
        id_cliente = random.randint(1, N_CLIENTES)
        id_sala = random.choice(salas)
        # fecha de comprobante posterior a 2018 (coherencia con alta de cliente)
        fecha_comp = fake.date_between(start_date=date(2018, 1, 1),
                                       end_date="today")
        desc_pct = descuento_por_cliente.get(id_cliente, 10)
        comprobante_rows.append((nro, fecha_comp, id_cliente, id_sala))

        n_renglones = random.randint(MIN_RENGLONES_X_COMPROBANTE,
                                     MAX_RENGLONES_X_COMPROBANTE)
        disponibles = [v for v in vinos if stock_disp.get((id_sala, v), 0) > 0]
        if not disponibles:
            continue
        elegidos = random.sample(disponibles,
                                 min(n_renglones, len(disponibles)))
        for cod_vino in elegidos:
            disp = stock_disp[(id_sala, cod_vino)]
            if disp <= 0:
                continue
            cantidad = random.randint(1, min(30, disp))
            precio = precio_por_vino[cod_vino]
            subtotal = round(cantidad * precio * (100 - desc_pct) / 100, 2)
            renglon_rows.append((nro, cod_vino, cantidad, precio, desc_pct, subtotal))
            stock_disp[(id_sala, cod_vino)] -= cantidad
            total_renglones += 1

    # 1) Cabeceras de comprobante por lotes con INSERT ... VALUES
    t_ins = time.perf_counter()
    BATCH = 10000
    with con.cursor() as cur:
        for ini in range(0, len(comprobante_rows), BATCH):
            chunk = comprobante_rows[ini:ini + BATCH]
            args = ",".join(
                f"({r[0]},'{r[1]}',{r[2]},{r[3]})" for r in chunk
            )
            cur.execute(
                f"INSERT INTO comprobante (nro_comprobante, fecha, id_cliente, id_sala) "
                f"OVERRIDING SYSTEM VALUE VALUES {args}"
            )
    con.commit()

    # 2) Renglones con COPY (context manager, verificado funcional)
    if renglon_rows:
        buf = []
        for r in renglon_rows:
            buf.append("\t".join(str(x) for x in r) + "\n")
        with con.cursor() as cur:
            with cur.copy(
                "COPY renglon_comprobante (nro_comprobante, cod_vino, cantidad, "
                "precio_unitario, descuento_pct, subtotal) "
                "FROM STDIN WITH (FORMAT text)"
            ) as cp:
                cp.write("".join(buf))

    # 3) Actualizar stock_sala con el remanente tras las ventas
    #    (el trigger descuento estaba deshabilitado durante la carga)
    if stock_disp:
        args = ",".join(
            f"({s},{v},{c})" for (s, v), c in stock_disp.items()
        )
        with con.cursor() as cur:
            cur.execute(
                f"UPDATE stock_sala ss SET cantidad = v.cantidad "
                f"FROM (VALUES {args}) AS v(id_sala, cod_vino, cantidad) "
                f"WHERE ss.id_sala = v.id_sala AND ss.cod_vino = v.cod_vino"
            )
    con.commit()

    dt = time.perf_counter() - t0
    print(f"[OK] Ventas masivas: {len(comprobante_rows)} comprobantes, "
          f"{total_renglones} renglones en {dt:.3f}s")
    return len(comprobante_rows), total_renglones


# ---------------------------------------------------------------------------
# Recalcular totales de comprobante (triggers estaban deshabilitados al insertar)
# ---------------------------------------------------------------------------
def recalcular_totales_comprobante(con):
    t0 = time.perf_counter()
    with con.cursor() as cur:
        cur.execute("""
            UPDATE comprobante c
            SET subtotal  = x.bruto,
                descuento = x.bruto - x.neto,
                total     = x.neto
            FROM (
              SELECT nro_comprobante,
                     COALESCE(SUM(cantidad * precio_unitario), 0)::NUMERIC(12,2) AS bruto,
                     COALESCE(SUM(ROUND(cantidad * precio_unitario * (100 - descuento_pct) / 100, 2)), 0)
                       ::NUMERIC(12,2) AS neto
              FROM renglon_comprobante
              GROUP BY nro_comprobante
            ) x
            WHERE c.nro_comprobante = x.nro_comprobante
        """)
    con.commit()
    dt = time.perf_counter() - t0
    print(f"[OK] Totales de comprobante recalculados: {dt:.3f}s")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print(f"Conectando a {DBNAME} como {USER}...")
    con = conectar()
    try:
        with con.cursor() as cur:
            cur.execute("SELECT current_user, current_database()")
            u, d = cur.fetchone()
            print(f"  Usuario: {u}, Base: {d}")

        with con.cursor() as cur:
            cur.execute("SELECT to_regclass('public.vino')")
            if cur.fetchone()[0] is None:
                print("ERROR: Base no migrada (falta public.vino).", file=sys.stderr)
                sys.exit(1)

        # 1) 01_pre_carga
        print("\n=== 01_pre_carga: deshabilitando triggers críticos ===")
        ejecutar_sql_archivo(con, RUTA_01, "01_pre_carga")

        # 2) Catálogos desde CSV
        print("\n=== Catálogos desde CSV ===")
        insertar_catalogos(con)
        print("  departamento, localidad, bodega, cepa, maridaje: OK")

        # 3) Datos maestros
        print("\n=== Datos maestros ===")
        insertar_maestros(con)
        print("  fincas, parcelas, lotes, vinos, composición, maridaje, trazabilidad: OK")
        insertar_clientes(con)
        print(f"  clientes ({N_CLIENTES}) + subtipos + permisos exportación: OK")
        insertar_salas_y_transportistas(con)
        print(f"  salas ({N_SALAS}) + transportistas ({N_TRANSPORTISTAS}): OK")

        # 4) IDs para ventas
        with con.cursor() as cur:
            cur.execute("SELECT cod_vino, precio FROM vino")
            vinos_rows = cur.fetchall()
            vinos = [r[0] for r in vinos_rows]
            precio_por_vino = {r[0]: float(r[1]) for r in vinos_rows}
            cur.execute("SELECT id_sala FROM sala_venta")
            salas = [r[0] for r in cur.fetchall()]
            cur.execute("SELECT cuit FROM bodega")
            bodega_cuits = [r[0] for r in cur.fetchall()]

        if not vinos or not salas:
            print("ERROR: No hay vinos o salas para ventas.", file=sys.stderr)
            sys.exit(1)

        # 5) Stock (depósito + salas), persistido en DB
        print("\n=== Poblado de stock (depósito y salas) ===")
        stock_deposito, stock_sala_disp = poblar_stock(con, vinos, salas)

        # 6) Movimientos de stock que justifican el stock inicial (para C7/C8)
        print("\n=== Movimientos de stock (ingresos/transferencias) ===")
        poblar_movimientos_stock(con, vinos, salas, bodega_cuits)

        # 7) Descuentos por cliente
        descuento_por_cliente = descuento_por_cliente_map(con)

        # 7) Ventas masivas
        print("\n=== Ventas masivas (comprobantes + renglones) ===")
        generar_ventas(con, salas, stock_sala_disp, vinos, precio_por_vino,
                       descuento_por_cliente)

        # 8) 03_post_carga
        print("\n=== 03_post_carga: habilitando triggers y validando ===")
        ejecutar_sql_archivo(con, RUTA_03, "03_post_carga")

        # 9) Recalcular totales de comprobante
        print("\n=== Recalcular totales de comprobante ===")
        recalcular_totales_comprobante(con)

        # Resumen
        with con.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM comprobante")
            n_comp = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM renglon_comprobante")
            n_ren = cur.fetchone()[0]
            cur.execute("""
                SELECT COUNT(*) FROM pg_trigger t
                JOIN pg_class c ON c.oid = t.tgrelid
                WHERE NOT t.tgisinternal
                  AND c.relnamespace = 'public'::regnamespace
                  AND t.tgenabled <> 'O'
            """)
            n_disabled = cur.fetchone()[0]
        print("\n=== RESUMEN DE CARGA ===")
        print(f"  Comprobantes: {n_comp}")
        print(f"  Renglones de comprobante: {n_ren}")
        print(f"  Triggers de usuario deshabilitados: {n_disabled} (debe ser 0)")
        print("\nSeed completado exitosamente.")
    finally:
        con.close()


if __name__ == "__main__":
    main()
