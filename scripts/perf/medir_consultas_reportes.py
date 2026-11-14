"""Mide el tiempo de las consultas de reportes (S1, S6, S7, S8) contra la base cargada.

Llama directamente a las funciones de api/app/db/queries/reportes.py usando el
mismo pool de conexiones que la API. No pasa por HTTP, asi que NO incluye el
tiempo de red ni de serializacion a JSON.

Requisitos (en la misma terminal):
  - Variables de entorno de conexion cargadas (DB_HOST, DB_PORT, DB_NAME,
    DB_USER, DB_PASSWORD), apuntando a bodegas_atuel_bench.
  - Docker con la base levantada.

Uso, desde la raiz del repo:
  python scripts/perf/medir_consultas_reportes.py --sala 1 --rep 5
"""

import argparse
import csv
import statistics
import sys
import time
from pathlib import Path

# Permite importar el paquete "app" de la API (api/app).
RAIZ = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(RAIZ / "api"))

from app.db.pool import close_pool, get_pool, open_pool  # noqa: E402
from app.db.queries.reportes import (  # noqa: E402
    top_vinos,
    transportista_activo,
    ventas_por_sala,
    vinos_sin_stock,
)


def medir(conn, funcion, repeticiones):
    """Ejecuta la consulta 1 vez (primera) y N veces mas. Devuelve tiempos en ms."""
    tiempos = []
    filas = 0
    for _ in range(repeticiones + 1):
        inicio = time.perf_counter()
        resultado = funcion(conn)
        tiempos.append((time.perf_counter() - inicio) * 1000)
        filas = len(resultado)
    primera, resto = tiempos[0], tiempos[1:]
    return {
        "filas": filas,
        "primera_ms": round(primera, 1),
        "mediana_ms": round(statistics.median(resto), 1),
        "min_ms": round(min(resto), 1),
        "max_ms": round(max(resto), 1),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sala", type=int, default=1, help="id_sala para S6")
    parser.add_argument("--rep", type=int, default=5, help="repeticiones")
    args = parser.parse_args()

    casos = [
        ("S1", "Top 10 vinos mas vendidos", lambda c: top_vinos(c, 10)),
        (
            "S6",
            f"Vinos sin stock en sala {args.sala}",
            lambda c: vinos_sin_stock(c, id_sala=args.sala),
        ),
        ("S7", "Transportista con mayor actividad (ultimo mes)", transportista_activo),
        (
            "S8",
            "Ventas por sala (ultimo trimestre)",
            lambda c: ventas_por_sala(c, periodo="ultimo_trimestre"),
        ),
        ("S8-total", "Ventas por sala (sin filtro de fecha)", ventas_por_sala),
    ]

    open_pool()
    resultados = []
    try:
        with get_pool().connection() as conn:
            for codigo, nombre, funcion in casos:
                datos = medir(conn, funcion, args.rep)
                datos.update({"codigo": codigo, "reporte": nombre})
                resultados.append(datos)
                print(f"{codigo}: {datos['mediana_ms']} ms (mediana), {datos['filas']} filas")
    finally:
        close_pool()

    salida = RAIZ / "scratch"
    salida.mkdir(exist_ok=True)
    campos = ["codigo", "reporte", "filas", "primera_ms", "mediana_ms", "min_ms", "max_ms"]
    with open(salida / "tiempos_consultas_reportes.csv", "w", newline="", encoding="utf-8") as f:
        escritor = csv.DictWriter(f, fieldnames=campos)
        escritor.writeheader()
        escritor.writerows(resultados)

    print()
    print("Tabla en Markdown (para pegar en el informe):")
    print("| Codigo | Reporte | Filas | Primera (ms) | Mediana (ms) | Min (ms) | Max (ms) |")
    print("|---|---|---|---|---|---|---|")
    for r in resultados:
        print(
            f"| {r['codigo']} | {r['reporte']} | {r['filas']} | {r['primera_ms']} | "
            f"{r['mediana_ms']} | {r['min_ms']} | {r['max_ms']} |"
        )
    print()
    print("Guardado en scratch/tiempos_consultas_reportes.csv")


if __name__ == "__main__":
    main()
