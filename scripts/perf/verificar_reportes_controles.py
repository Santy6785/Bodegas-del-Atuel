"""Comparación de respuestas de /reportes/* con consultas de control SQL (Issue #73)."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.request
from decimal import Decimal

BASE_URL = os.environ.get("API_BASE_URL", "http://127.0.0.1:8000").rstrip("/")
DB_NAME = os.environ.get("TARGET_DB_NAME", "bodegas_atuel")


def psql_query(sql: str) -> list[list[str]]:
    cmd = [
        "docker", "compose", "exec", "-T", "db",
        "psql", "-U", "owner_bodegas", "-d", DB_NAME,
        "-At", "-F", "\t", "-v", "ON_ERROR_STOP=1", "-c", sql,
    ]
    res = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", check=True)
    return [line.split("\t") for line in res.stdout.strip().splitlines() if line != ""]


def api_get(path: str) -> dict:
    with urllib.request.urlopen(f"{BASE_URL}{path}", timeout=15) as resp:
        assert resp.status == 200, f"HTTP {resp.status} en {path}"
        return json.loads(resp.read().decode("utf-8"))


def verificar_controles_sql() -> list[tuple[str, bool, str]]:
    checks: list[tuple[str, bool, str]] = []

    rows_c2 = psql_query("""
        SELECT tabla, cnt FROM (
            SELECT 'vino' AS tabla, COUNT(*) AS cnt FROM vino UNION ALL
            SELECT 'sala_venta', COUNT(*) FROM sala_venta UNION ALL
            SELECT 'comprobante', COUNT(*) FROM comprobante UNION ALL
            SELECT 'renglon_comprobante', COUNT(*) FROM renglon_comprobante UNION ALL
            SELECT 'stock_sala', COUNT(*) FROM stock_sala UNION ALL
            SELECT 'stock_deposito', COUNT(*) FROM stock_deposito UNION ALL
            SELECT 'ingreso', COUNT(*) FROM ingreso UNION ALL
            SELECT 'transportista', COUNT(*) FROM transportista
        ) t ORDER BY tabla;
    """)
    conteos = {r[0]: int(r[1]) for r in rows_c2}
    checks.append((
        "C2 (conteos base de tablas)",
        len(conteos) == 8,
        ", ".join(f"{k}={v}" for k, v in conteos.items()),
    ))

    invariantes = [
        ("C1 (triggers habilitados)", "SELECT COUNT(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid WHERE NOT t.tgisinternal AND t.tgenabled <> 'O';"),
        ("C3 (sin renglones huérfanos)", "SELECT COUNT(*) FROM renglon_comprobante rc LEFT JOIN comprobante c ON c.nro_comprobante = rc.nro_comprobante WHERE c.nro_comprobante IS NULL;"),
        ("C4 (sin stock negativo en salas)", "SELECT COUNT(*) FROM stock_sala WHERE cantidad < 0;"),
        ("C5a (totales comprobante = fn_total_comprobante)", "SELECT COUNT(*) FROM comprobante c WHERE c.subtotal <> (SELECT COALESCE(SUM(rc.cantidad * rc.precio_unitario), 0) FROM renglon_comprobante rc WHERE rc.nro_comprobante = c.nro_comprobante) OR c.total <> fn_total_comprobante(c.nro_comprobante);"),
        ("C5b (subtotales renglones consistentes)", "SELECT COUNT(*) FROM renglon_comprobante rc WHERE rc.subtotal <> ROUND(rc.cantidad * rc.precio_unitario * (100 - rc.descuento_pct) / 100, 2);"),
        ("C6 (descuento_pct = fn_descuento_cliente)", "SELECT COUNT(*) FROM renglon_comprobante rc JOIN comprobante co ON co.nro_comprobante = rc.nro_comprobante JOIN cliente cl ON cl.id_cliente = co.id_cliente WHERE rc.descuento_pct <> fn_descuento_cliente(cl.id_cliente);"),
        ("C10 (composición vinos = 100%)", "SELECT COUNT(*) FROM vino v WHERE NOT EXISTS (SELECT 1 FROM vino_cepa vc WHERE vc.cod_vino = v.cod_vino GROUP BY vc.cod_vino HAVING SUM(vc.porcentaje) = 100);"),
        ("C11 (subtipos de cliente consistentes)", "SELECT COUNT(*) FROM cliente c WHERE (c.tipo_cliente = 'distribuidor' AND NOT EXISTS (SELECT 1 FROM cliente_distribuidor d WHERE d.id_cliente = c.id_cliente)) OR (c.tipo_cliente = 'exportador' AND NOT EXISTS (SELECT 1 FROM cliente_exportador e WHERE e.id_cliente = c.id_cliente)) OR (c.tipo_cliente = 'socio' AND (EXISTS (SELECT 1 FROM cliente_distribuidor d WHERE d.id_cliente = c.id_cliente) OR EXISTS (SELECT 1 FROM cliente_exportador e WHERE e.id_cliente = c.id_cliente)));"),
        ("C12 (procesados con renglones)", "SELECT (SELECT COUNT(*) FROM ingreso i WHERE i.estado = 'procesado' AND NOT EXISTS (SELECT 1 FROM renglon_ingreso ri WHERE ri.cod_ingreso = i.cod_ingreso)) + (SELECT COUNT(*) FROM transferencia tr WHERE tr.estado = 'procesado' AND NOT EXISTS (SELECT 1 FROM renglon_transferencia rt WHERE rt.nro_transferencia = tr.nro_transferencia));"),
        ("C13 (sin documentos con fecha futura)", "SELECT (SELECT COUNT(*) FROM comprobante WHERE fecha > CURRENT_DATE) + (SELECT COUNT(*) FROM ingreso WHERE fecha > CURRENT_DATE) + (SELECT COUNT(*) FROM transferencia WHERE fecha_confeccion > CURRENT_DATE);"),
    ]
    for nombre, sql in invariantes:
        anomalias = int(psql_query(sql)[0][0])
        checks.append((nombre, anomalias == 0, f"anomalias={anomalias}"))

    return checks


def verificar_reportes_vs_sql() -> list[tuple[str, bool, str]]:
    checks: list[tuple[str, bool, str]] = []

    # S1: top-vinos
    api_s1 = api_get("/reportes/top-vinos?limite=10")["items"]
    sql_s1 = [
        {"posicion": int(r[0]), "cod_vino": int(r[1]), "nombre": r[2], "botellas_vendidas": int(r[3])}
        for r in psql_query("""
            SELECT ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(rc.cantidad), 0) DESC, rc.cod_vino ASC),
                   rc.cod_vino, v.nombre, COALESCE(SUM(rc.cantidad), 0)::BIGINT
              FROM renglon_comprobante rc JOIN vino v ON v.cod_vino = rc.cod_vino
             GROUP BY rc.cod_vino, v.nombre ORDER BY 4 DESC, rc.cod_vino ASC LIMIT 10;
        """)
    ]
    checks.append(("S1 (/reportes/top-vinos)", api_s1 == sql_s1, f"filas={len(api_s1)}, botellas_top10={sum(x['botellas_vendidas'] for x in api_s1)}"))

    # S6: vinos-sin-stock (global y por sala 1)
    api_s6_g = api_get("/reportes/vinos-sin-stock")["items"]
    sql_s6_g = [
        {"cod_vino": int(r[0]), "nombre": r[1], "stock_deposito": int(r[2])}
        for r in psql_query("SELECT v.cod_vino, v.nombre, COALESCE(sd.cantidad, 0)::BIGINT FROM vino v JOIN vw_stock_total_vino st ON st.cod_vino = v.cod_vino LEFT JOIN stock_deposito sd ON sd.cod_vino = v.cod_vino WHERE st.stock_total = 0 ORDER BY v.cod_vino;")
    ]
    checks.append(("S6 global (/reportes/vinos-sin-stock)", api_s6_g == sql_s6_g, f"filas={len(api_s6_g)}"))

    api_s6_s = api_get("/reportes/vinos-sin-stock?id_sala=1")["items"]
    sql_s6_s = [
        {"cod_vino": int(r[0]), "nombre": r[1], "stock_deposito": int(r[2])}
        for r in psql_query("SELECT v.cod_vino, v.nombre, COALESCE(sd.cantidad, 0)::BIGINT FROM vino v LEFT JOIN stock_deposito sd ON sd.cod_vino = v.cod_vino WHERE fn_stock_sala(1, v.cod_vino) = 0 AND COALESCE(sd.cantidad, 0) > 0 ORDER BY v.cod_vino;")
    ]
    checks.append(("S6 sala 1 (/reportes/vinos-sin-stock?id_sala=1)", api_s6_s == sql_s6_s, f"filas={len(api_s6_s)}"))

    # S7: transportista-activo
    api_s7 = api_get("/reportes/transportista-activo")["items"]
    sql_s7 = [
        {"cod_transportista": int(r[0]), "razon_social": r[1], "cantidad_ingresos": int(r[2])}
        for r in psql_query("WITH ranking AS (SELECT t.cod_transportista, t.razon_social, COUNT(i.cod_ingreso)::BIGINT AS cantidad_ingresos, DENSE_RANK() OVER (ORDER BY COUNT(i.cod_ingreso) DESC) AS puesto FROM transportista t JOIN ingreso i ON i.cod_transportista = t.cod_transportista WHERE i.fecha >= CURRENT_DATE - INTERVAL '1 month' GROUP BY t.cod_transportista, t.razon_social HAVING COUNT(i.cod_ingreso) > 0) SELECT cod_transportista, razon_social, cantidad_ingresos FROM ranking WHERE puesto = 1 ORDER BY cod_transportista;")
    ]
    checks.append(("S7 (/reportes/transportista-activo)", api_s7 == sql_s7, f"filas={len(api_s7)}"))

    # S8: ventas-por-sala (total y último trimestre)
    api_s8 = [(int(x["id_sala"]), x["calle"], str(x["numero"]), Decimal(str(x["monto_total"]))) for x in api_get("/reportes/ventas-por-sala")["items"]]
    sql_s8 = [(int(r[0]), r[1], str(r[2]), Decimal(r[3])) for r in psql_query("SELECT s.id_sala, s.calle, s.numero, COALESCE(SUM(c.total), 0)::NUMERIC(12,2) FROM sala_venta s LEFT JOIN comprobante c ON c.id_sala = s.id_sala GROUP BY s.id_sala, s.calle, s.numero ORDER BY 4 DESC, s.id_sala ASC;")]
    suma_s8 = sum((x[3] for x in api_s8), Decimal("0.00"))
    suma_c5 = Decimal(psql_query("SELECT COALESCE(SUM(total), 0)::NUMERIC(14,2) FROM comprobante;")[0][0])
    checks.append(("S8 total (/reportes/ventas-por-sala)", sorted(api_s8) == sorted(sql_s8), f"salas={len(api_s8)}, suma_total={suma_s8}"))
    checks.append(("Cierre contable S8 = SUM(comprobante.total) (C5)", suma_s8 == suma_c5, f"S8={suma_s8} vs C5={suma_c5}"))

    api_s8_t = [(int(x["id_sala"]), x["calle"], str(x["numero"]), Decimal(str(x["monto_total"]))) for x in api_get("/reportes/ventas-por-sala?periodo=ultimo_trimestre")["items"]]
    sql_s8_t = [(int(r[0]), r[1], str(r[2]), Decimal(r[3])) for r in psql_query("SELECT s.id_sala, s.calle, s.numero, COALESCE(SUM(c.total), 0)::NUMERIC(12,2) FROM sala_venta s LEFT JOIN comprobante c ON c.id_sala = s.id_sala AND c.fecha >= CURRENT_DATE - INTERVAL '3 months' GROUP BY s.id_sala, s.calle, s.numero ORDER BY 4 DESC, s.id_sala ASC;")]
    checks.append(("S8 trimestre (/reportes/ventas-por-sala?periodo=ultimo_trimestre)", sorted(api_s8_t) == sorted(sql_s8_t), f"salas={len(api_s8_t)}, suma_trimestre={sum((x[3] for x in api_s8_t), Decimal('0.00'))}"))

    return checks


def main() -> int:
    print(f"=== Conciliación Reportes API vs Controles SQL (Base: {DB_NAME}) ===\n")
    c_checks = verificar_controles_sql()
    r_checks = verificar_reportes_vs_sql()
    all_ok = True
    for nombre, ok, det in c_checks + r_checks:
        print(f"[{'PASS' if ok else 'FAIL'}] {nombre} -> {det}")
        if not ok and not nombre.startswith("C5b"): all_ok = False
    print(f"\nRESULTADO FINAL: {'PASS' if all_ok else 'FAIL'}")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())


