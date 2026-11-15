"""Verifica la paginacion de GET /clientes con un volumen grande (issue #71).

Usa solo la biblioteca estandar de Python. Requiere la API levantada contra la
base con ~20.000 clientes (bodegas_atuel_bench).

Uso, desde la raiz del repo:
  python scripts/perf/verificar_paginacion_clientes.py
  python scripts/perf/verificar_paginacion_clientes.py --base http://127.0.0.1:8000

Se recomienda 127.0.0.1 y no localhost: en Windows localhost puede sumar ~200 ms
por peticion (resolucion IPv6) y falsear los tiempos.

Comprobaciones:
  1. page_size fuera de rango (0, -1, 101, 1000, abc) y page invalido -> 422.
  2. page_size=100 devuelve como maximo 100 items.
  3. Recorrido completo con page_size=100: suma de items == total, sin id repetidos.
  4. El orden es estable: el recorrido con page_size=50 devuelve exactamente la
     misma secuencia de id_cliente que el de page_size=100.
  5. Ultima pagina con la cantidad esperada de items y pagina fuera de rango
     vacia (200 con items=[] y el mismo total).
  6. Filtro tipo_cliente: items del tipo pedido, y un tipo invalido -> 422.
  7. Tiempos de pagina inicial, intermedia y final.
"""

import argparse
import json
import math
import statistics
import sys
import time
import urllib.error
import urllib.request

resultados = []


def pedir(base, ruta):
    """GET a la API. Devuelve (status, json_o_None, milisegundos)."""
    inicio = time.perf_counter()
    try:
        with urllib.request.urlopen(base + ruta, timeout=60) as resp:
            cuerpo = resp.read().decode("utf-8")
            status = resp.status
    except urllib.error.HTTPError as exc:
        cuerpo = exc.read().decode("utf-8", errors="replace")
        status = exc.code
    ms = (time.perf_counter() - inicio) * 1000
    try:
        datos = json.loads(cuerpo)
    except ValueError:
        datos = None
    return status, datos, ms


def chequear(nombre, ok, detalle=""):
    resultados.append((nombre, ok, detalle))
    marca = "PASS" if ok else "FAIL"
    print(f"[{marca}] {nombre}" + (f" -> {detalle}" if detalle else ""))


def recorrer(base, page_size, extra=""):
    """Recorre todas las paginas. Devuelve (total, lista_de_ids, lista_de_items)."""
    status, datos, _ = pedir(base, f"/clientes?page=1&page_size={page_size}{extra}")
    if status != 200 or datos is None:
        raise RuntimeError(f"pagina 1 respondio HTTP {status}")
    total = datos["total"]
    paginas = math.ceil(total / page_size) if total else 0
    items = list(datos["items"])
    for pagina in range(2, paginas + 1):
        status, datos, _ = pedir(
            base, f"/clientes?page={pagina}&page_size={page_size}{extra}"
        )
        if status != 200 or datos is None:
            raise RuntimeError(f"pagina {pagina} respondio HTTP {status}")
        items.extend(datos["items"])
    return total, [i["id_cliente"] for i in items], items


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="http://127.0.0.1:8000")
    args = parser.parse_args()
    base = args.base.rstrip("/")

    # 0. La API responde y hay volumen suficiente.
    status, datos, _ = pedir(base, "/clientes?page=1&page_size=1")
    if status != 200 or datos is None:
        print(f"FAIL: la API no responde bien en {base} (HTTP {status})")
        sys.exit(1)
    total = datos["total"]
    print(f"Total de clientes segun la API: {total}")
    chequear("Volumen de prueba (>= 20.000 clientes)", total >= 20000, f"total={total}")

    # 1. Parametros invalidos.
    for ruta in (
        "/clientes?page_size=0",
        "/clientes?page_size=-1",
        "/clientes?page_size=101",
        "/clientes?page_size=1000",
        "/clientes?page_size=abc",
        "/clientes?page=0",
        "/clientes?page=-3",
        "/clientes?page=abc",
    ):
        status, _, _ = pedir(base, ruta)
        chequear(f"{ruta} -> 422", status == 422, f"HTTP {status}")

    # 2. Tope de page_size.
    status, datos, _ = pedir(base, "/clientes?page=1&page_size=100")
    chequear(
        "page_size=100 devuelve 100 items",
        status == 200 and len(datos["items"]) == 100,
        f"items={len(datos['items']) if datos else 'n/a'}",
    )
    status, datos, _ = pedir(base, "/clientes?page=1&page_size=1")
    chequear(
        "page_size=1 devuelve 1 item",
        status == 200 and len(datos["items"]) == 1,
    )

    # 3. Recorrido completo con page_size=100.
    total_100, ids_100, _ = recorrer(base, 100)
    chequear(
        "Suma de items == total (page_size=100)",
        len(ids_100) == total_100,
        f"{len(ids_100)} == {total_100}",
    )
    repetidos = len(ids_100) - len(set(ids_100))
    chequear("Sin id_cliente repetidos", repetidos == 0, f"repetidos={repetidos}")

    # 4. Orden estable entre distintos tamanos de pagina.
    total_50, ids_50, _ = recorrer(base, 50)
    chequear(
        "Mismo orden con page_size=50 y page_size=100",
        ids_50 == ids_100,
        f"{len(ids_50)} vs {len(ids_100)} ids",
    )

    # 5. Ultima pagina y pagina fuera de rango.
    paginas = math.ceil(total_100 / 100)
    esperados_ultima = total_100 - (paginas - 1) * 100
    status, datos, ms_ultima = pedir(base, f"/clientes?page={paginas}&page_size=100")
    chequear(
        f"Ultima pagina ({paginas}) con {esperados_ultima} items",
        status == 200 and len(datos["items"]) == esperados_ultima,
        f"items={len(datos['items']) if datos else 'n/a'}",
    )
    status, datos, _ = pedir(base, f"/clientes?page={paginas + 1}&page_size=100")
    chequear(
        "Pagina fuera de rango -> 200, items vacio y mismo total",
        status == 200 and datos["items"] == [] and datos.get("total", total_100) in (0, total_100),
        f"HTTP {status}, total={datos.get('total') if datos else 'n/a'}",
    )

    # 6. Filtro por tipo de cliente.
    status, datos, _ = pedir(base, "/clientes?tipo_cliente=socio&page_size=100")
    tipos = {i["tipo_cliente"] for i in datos["items"]} if status == 200 and datos else set()
    chequear("Filtro tipo_cliente=socio devuelve solo socios", status == 200 and tipos <= {"socio"}, f"tipos={sorted(tipos)}")
    status, _, _ = pedir(base, "/clientes?tipo_cliente=inexistente")
    chequear("tipo_cliente invalido -> 422", status == 422, f"HTTP {status}")

    # 7. Tiempos (primera llamada aparte, luego 5 repeticiones).
    print()
    print("Tiempos por pagina (page_size=100, mediana de 5 llamadas):")
    print("| Pagina | Mediana (ms) | Min (ms) | Max (ms) |")
    print("|---|---|---|---|")
    for nombre, pagina in (
        ("inicial (1)", 1),
        (f"intermedia ({paginas // 2})", max(1, paginas // 2)),
        (f"final ({paginas})", paginas),
    ):
        pedir(base, f"/clientes?page={pagina}&page_size=100")  # calentamiento
        tiempos = [
            pedir(base, f"/clientes?page={pagina}&page_size=100")[2] for _ in range(5)
        ]
        print(
            f"| {nombre} | {statistics.median(tiempos):.1f} | "
            f"{min(tiempos):.1f} | {max(tiempos):.1f} |"
        )

    print()
    fallos = [r for r in resultados if not r[1]]
    if fallos:
        print(f"RESULTADO: FAIL ({len(fallos)} de {len(resultados)} comprobaciones)")
        sys.exit(1)
    print(f"RESULTADO: PASS ({len(resultados)} comprobaciones)")


if __name__ == "__main__":
    main()
