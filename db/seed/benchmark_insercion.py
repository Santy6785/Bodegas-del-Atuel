#!/usr/bin/env python3
"""Benchmark de inserción masiva en bench_renglon (réplica estructural de
renglon_comprobante SIN claves foráneas, por lo que no necesita datos de
referencia).

Métodos:
  A - fila por fila con COMMIT por fila                      (N=2000)
  B - fila por fila en una única transacción                 (N=10000)
  C - cur.executemany                                        (N=10000)
  D - INSERT multi-fila por lotes de 1000                    (N=10000 y 100000)
  E - COPY (cursor.copy)                                     (N=10000 y 100000)

Una calentamiento + 3 repeticiones por configuración; se reporta mediana y
filas/segundo.

Conexión mediante variables de entorno PG* (PGDATABASE, PGUSER, PGHOST,
PGPORT, PGPASSWORD). Dentro del contenedor bodegas-db se usa el socket local
(trust, sin contraseña): PGDATABASE=bodegas_atuel_bench PGUSER=owner_bodegas.
"""
import io
import os
import statistics
import time

import psycopg

DBNAME = os.environ.get("PGDATABASE", "bodegas_atuel_bench")
USER = os.environ.get("PGUSER", "owner_bodegas")
HOST = os.environ.get("PGHOST")          # None => socket local de Unix
PORT = os.environ.get("PGPORT", "5432")
PASSWORD = os.environ.get("PGPASSWORD")

REPS = 3
WARMUP_N = 2000

COLUMNS = ["nro_comprobante", "cod_vino", "cantidad", "precio_unitario",
           "descuento_pct", "subtotal"]
COL_LIST = ", ".join(COLUMNS)
PLACEHOLDERS = ", ".join(["%s"] * len(COLUMNS))
INSERT_SQL = f"INSERT INTO bench_renglon ({COL_LIST}) VALUES ({PLACEHOLDERS})"
COPY_SQL = f"COPY bench_renglon ({COL_LIST}) FROM STDIN WITH (FORMAT csv)"


def connect():
    kwargs = dict(dbname=DBNAME, user=USER, port=PORT)
    if HOST:
        kwargs["host"] = HOST
    if PASSWORD:
        kwargs["password"] = PASSWORD
    return psycopg.connect(**kwargs)


def make_row(i):
    nro = (i // 10000) + 1
    vino = (i % 10000) + 1
    cantidad = (i % 50) + 1
    precio = round(1000.00 + (i % 9000) / 100.0, 2)
    desc = round([0, 10, 20, 30][i % 4], 2)
    subtotal = round(cantidad * precio * (100 - desc) / 100.0, 2)
    return (nro, vino, cantidad, precio, desc, subtotal)


def reset_table(cur):
    cur.execute("TRUNCATE bench_renglon")


def commit_reset(cur, con):
    reset_table(cur)
    con.commit()


def create_bench_table(cur):
    cur.execute("DROP TABLE IF EXISTS bench_renglon")
    cur.execute(
        "CREATE TABLE bench_renglon (LIKE renglon_comprobante "
        "INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING INDEXES)"
    )


def method_a(con, n):
    cur = con.cursor()
    commit_reset(cur, con)
    t0 = time.perf_counter()
    for i in range(n):
        cur = con.cursor()
        cur.execute(INSERT_SQL, make_row(i))
        con.commit()
    t1 = time.perf_counter()
    return t1 - t0


def method_b(con, n):
    cur = con.cursor()
    commit_reset(cur, con)
    t0 = time.perf_counter()
    for i in range(n):
        cur.execute(INSERT_SQL, make_row(i))
    con.commit()
    t1 = time.perf_counter()
    return t1 - t0


def method_c(con, n):
    cur = con.cursor()
    commit_reset(cur, con)
    rows = [make_row(i) for i in range(n)]
    t0 = time.perf_counter()
    cur.executemany(INSERT_SQL, rows)
    con.commit()
    t1 = time.perf_counter()
    return t1 - t0


def method_d(con, n, batch=1000):
    cur = con.cursor()
    commit_reset(cur, con)
    rows = [make_row(i) for i in range(n)]
    t0 = time.perf_counter()
    for start in range(0, n, batch):
        chunk = rows[start:start + batch]
        values = ", ".join(
            "(" + ",".join(str(v) for v in r) + ")" for r in chunk
        )
        cur.execute(f"INSERT INTO bench_renglon ({COL_LIST}) VALUES {values}")
    con.commit()
    t1 = time.perf_counter()
    return t1 - t0


def method_e(con, n):
    cur = con.cursor()
    commit_reset(cur, con)
    buf = io.StringIO()
    for i in range(n):
        buf.write(",".join(str(v) for v in make_row(i)) + "\n")
    buf.seek(0)
    t0 = time.perf_counter()
    with cur.copy(COPY_SQL) as cp:
        for line in buf:
            cp.write(line)
    con.commit()
    cur.execute("SELECT COUNT(*) FROM bench_renglon")
    carga = cur.fetchone()[0]
    if carga != n:
        print(f"  !! ADVERTENCIA COPY: esperadas {n} filas, cargadas {carga}")
    t1 = time.perf_counter()
    return t1 - t0


def run(label, fn, con, n):
    times = [fn(con, n) for _ in range(REPS)]
    med = statistics.median(times)
    rows_s = n / med if med > 0 else float("inf")
    print(f"{label}: N={n} reps={[round(t, 4) for t in times]} "
          f"mediana={med:.4f}s filas/s={rows_s:,.0f}")
    return med, rows_s


def optional_trigger_cost(con):
    """Costo de los triggers sobre la tabla real renglon_comprobante (ROLLBACK).

    La PK de renglon_comprobante es (nro_comprobante, cod_vino), por lo que se
    crean 10 comprobantes x 50 vinos = 500 pares distintos antes de insertar.
    Todo se revierte al final.
    """
    print("\n--- Opcional: costo de triggers sobre renglon_comprobante real (ROLLBACK) ---")
    cur = con.cursor()
    try:
        cur.execute(
            "INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional) "
            "VALUES ('5500','Mendoza','Mendoza','enc')")
        cur.execute(
            "INSERT INTO bodega (cuit, razon_social, domicilio) "
            "VALUES ('12345678901','Bodega X','Av X')")
        cur.execute(
            "INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal) "
            "VALUES ('Calle 1','1','lunes','5500')")
        cur.execute(
            "INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento, "
            "nro_documento, direccion, codigo_postal, fecha_alta, tipo_cliente) "
            "VALUES ('Perez','Juan','DNI','12345678','Dir','5500','2020-01-01','socio')")
        sala_id = cur.execute(
            "SELECT currval(pg_get_serial_sequence('public.sala_venta','id_sala'))"
        ).fetchone()[0]
        cli_id = cur.execute(
            "SELECT currval(pg_get_serial_sequence('public.cliente','id_cliente'))"
        ).fetchone()[0]

        cur.execute("INSERT INTO cepa (nombre, tipo) VALUES ('Malbec','tinta')")
        cepa_id = cur.execute(
            "SELECT currval(pg_get_serial_sequence('public.cepa','id_cepa'))"
        ).fetchone()[0]

        nros = []
        for _ in range(10):
            cur.execute(
                "INSERT INTO comprobante (fecha, id_cliente, id_sala, subtotal, descuento, total) "
                "VALUES ('2024-01-01', %s, %s, 0, 0, 0)", (cli_id, sala_id))
            nros.append(cur.execute(
                "SELECT currval(pg_get_serial_sequence('public.comprobante','nro_comprobante'))"
            ).fetchone()[0])

        vinos = []
        for k in range(50):
            cur.execute(
                "INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega) "
                "VALUES (%s,'tinto',2020,750,13.5,1000.00,'12345678901')", (f"Vino {k}",))
            v = cur.execute(
                "SELECT currval(pg_get_serial_sequence('public.vino','cod_vino'))"
            ).fetchone()[0]
            cur.execute(
                "INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje) VALUES (%s, %s, 100)",
                (v, cepa_id))
            cur.execute(
                "INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (%s, %s, 100000)",
                (sala_id, v))
            vinos.append(v)

        n = 500
        rows = []
        for nro in nros:
            for vino in vinos:
                if len(rows) >= n:
                    break
                rows.append((nro, vino, 5, 1000.00, 10.00, round(5 * 1000.00 * 0.9, 2)))
            if len(rows) >= n:
                break

        t0 = time.perf_counter()
        cur.executemany(
            "INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, "
            "precio_unitario, descuento_pct, subtotal) VALUES (%s,%s,%s,%s,%s,%s)",
            rows,
        )
        t1 = time.perf_counter()
        dt = t1 - t0
        print(f"triggers ON: N={n} tiempo={dt:.4f}s filas/s={n/dt:,.0f} (todo ROLLBACK)")
    finally:
        con.rollback()


def main():
    con = connect()
    try:
        with con.cursor() as cur:
            create_bench_table(cur)
            con.commit()

        print("== Calentamiento (method A, N=2000, se descarta) ==")
        method_a(con, WARMUP_N)

        print("\n== Medición (3 repeticiones, mediana + filas/s) ==")
        run("A  fila x fila + commit x fila", method_a, con, 2000)
        run("B  fila x fila, 1 transacción", method_b, con, 10000)
        run("C  executemany", method_c, con, 10000)
        run("D  INSERT multi-fila lotes 1000", method_d, con, 10000)
        run("E  COPY", method_e, con, 10000)
        run("D  INSERT multi-fila lotes 1000", method_d, con, 100000)
        run("E  COPY", method_e, con, 100000)

        optional_trigger_cost(con)

        with con.cursor() as cur:
            cur.execute("DROP TABLE IF EXISTS bench_renglon")
            con.commit()
        print("\nbench_renglon soltada (try/finally).")
    finally:
        con.close()


if __name__ == "__main__":
    main()
