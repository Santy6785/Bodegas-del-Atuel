"""Verificación de identidad de rol (app_rw) bajo carga concurrente (Issue #72).

Dispara tráfico HTTP concurrente contra los endpoints activos de la API mientras
un monitor independiente muestrea `pg_stat_activity` en PostgreSQL para confirmar
que el 100% de las conexiones abiertas por el pool (`application_name = 'bodegas-api'`)
operan bajo el rol `app_rw` durante toda la prueba de carga y sin errores de permisos.
"""

from __future__ import annotations

import concurrent.futures
import os
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from collections import Counter

BASE_URL = os.environ.get("API_BASE_URL", "http://127.0.0.1:8000").rstrip("/")
DB_NAME = os.environ.get("BENCH_DB_NAME", "bodegas_atuel_bench")
CONCURRENCY = int(os.environ.get("LOAD_CONCURRENCY", "16"))
TOTAL_REQUESTS = int(os.environ.get("LOAD_REQUESTS", "320"))

ENDPOINTS = [
    "/salud",
    "/clientes?page=1&page_size=100",
    "/clientes?page=50&page_size=100",
    "/clientes?page=150&page_size=100",
    "/vinos",
    "/reportes/top-vinos",
    "/reportes/vinos-sin-stock",
    "/reportes/transportista-activo",
    "/reportes/ventas-por-sala",
]


def query_pg_stat_activity() -> list[tuple[str, str, str, str]]:
    sql = (
        "SELECT pid::text, usename, application_name, state "
        "FROM pg_stat_activity "
        f"WHERE datname = '{DB_NAME}' AND application_name = 'bodegas-api';"
    )
    cmd = [
        "docker", "compose", "exec", "-T", "db",
        "psql", "-U", "owner_bodegas", "-d", DB_NAME,
        "-At", "-F", "|", "-c", sql,
    ]
    res = subprocess.run(cmd, capture_output=True, text=True, check=False)
    filas: list[tuple[str, str, str, str]] = []
    for line in res.stdout.strip().splitlines():
        parts = line.split("|")
        if len(parts) == 4:
            filas.append((parts[0], parts[1], parts[2], parts[3]))
    return filas


def worker_request(idx: int) -> tuple[str, int, float, str]:
    path = ENDPOINTS[idx % len(ENDPOINTS)]
    url = f"{BASE_URL}{path}"
    t0 = time.perf_counter()
    try:
        with urllib.request.urlopen(url, timeout=15) as resp:
            resp.read()
            ms = (time.perf_counter() - t0) * 1000.0
            return (path, resp.status, ms, "")
    except urllib.error.HTTPError as exc:
        ms = (time.perf_counter() - t0) * 1000.0
        body = exc.read().decode("utf-8", errors="replace")[:200]
        return (path, exc.code, ms, body)
    except Exception as exc:  # noqa: BLE001
        ms = (time.perf_counter() - t0) * 1000.0
        return (path, 0, ms, str(exc))


def main() -> int:
    print(f"=== Prueba de carga y verificación de rol app_rw (Issue #72) ===")
    print(f"API: {BASE_URL} | Base muestreada: {DB_NAME}")
    print(f"Concurrencia: {CONCURRENCY} hilos | Total peticiones: {TOTAL_REQUESTS}\n")

    stop_event = threading.Event()
    muestras_totales = 0
    conexiones_observadas = 0
    max_conns_simultaneas = 0
    pids_unicos: set[str] = set()
    usuarios_detectados: Counter[str] = Counter()
    estados_detectados: Counter[str] = Counter()

    def monitor_loop() -> None:
        nonlocal muestras_totales, conexiones_observadas, max_conns_simultaneas
        while not stop_event.is_set():
            filas = query_pg_stat_activity()
            muestras_totales += 1
            n = len(filas)
            if n > max_conns_simultaneas:
                max_conns_simultaneas = n
            for pid, usename, _app, state in filas:
                conexiones_observadas += 1
                pids_unicos.add(pid)
                usuarios_detectados[usename] += 1
                estados_detectados[state] += 1
            time.sleep(0.08)

    monitor_thread = threading.Thread(target=monitor_loop, daemon=True)
    monitor_thread.start()

    # Breve espera para capturar estado inicial antes de la ráfaga
    time.sleep(0.25)

    t_start = time.perf_counter()
    resultados: list[tuple[str, int, float, str]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=CONCURRENCY) as pool:
        futures = [pool.submit(worker_request, i) for i in range(TOTAL_REQUESTS)]
        for fut in concurrent.futures.as_completed(futures):
            resultados.append(fut.result())
    duracion_s = time.perf_counter() - t_start

    # Captura final post-ráfaga antes de detener el monitor
    time.sleep(0.25)
    stop_event.set()
    monitor_thread.join(timeout=2.0)

    status_counts = Counter(r[1] for r in resultados)
    errores = [r for r in resultados if r[1] != 200]
    latencias = sorted(r[2] for r in resultados)
    p50 = latencias[len(latencias) // 2]
    p95 = latencias[int(len(latencias) * 0.95)]

    print(f"--- Resultados HTTP ---")
    print(f"Duración total: {duracion_s:.2f} s ({TOTAL_REQUESTS / duracion_s:.1f} req/s)")
    print(f"Códigos HTTP: {dict(status_counts)}")
    print(f"Latencia p50: {p50:.1f} ms | p95: {p95:.1f} ms | max: {latencias[-1]:.1f} ms\n")

    if errores:
        print("Primeros errores detectados:")
        for path, code, _ms, detail in errores[:5]:
            print(f"  - {path} -> HTTP {code}: {detail}")
        print()

    print(f"--- Auditoría pg_stat_activity (application_name = 'bodegas-api') ---")
    print(f"Muestras tomadas durante la carga: {muestras_totales}")
    print(f"Observaciones totales de sesiones: {conexiones_observadas}")
    print(f"PIDs distintos observados en el pool: {len(pids_unicos)}")
    print(f"Pico de conexiones simultáneas en el pool: {max_conns_simultaneas}")
    print(f"Roles (usename) detectados: {dict(usuarios_detectados)}")
    print(f"Estados observados: {dict(estados_detectados)}\n")

    checks = [
        (
            "Todas las peticiones HTTP respondieron 200 OK (sin errores de permisos)",
            len(errores) == 0 and status_counts.get(200, 0) == TOTAL_REQUESTS,
        ),
        (
            "Se observaron sesiones activas de 'bodegas-api' en pg_stat_activity",
            conexiones_observadas > 0 and max_conns_simultaneas >= 2,
        ),
        (
            "100% de las conexiones del pool usaron el rol 'app_rw'",
            set(usuarios_detectados.keys()) == {"app_rw"},
        ),
        (
            "Cero conexiones detectadas como 'owner_bodegas' o superusuario",
            "owner_bodegas" not in usuarios_detectados and "postgres" not in usuarios_detectados,
        ),
    ]

    all_ok = True
    for desc, ok in checks:
        tag = "PASS" if ok else "FAIL"
        print(f"[{tag}] {desc}")
        if not ok:
            all_ok = False

    print(f"\nRESULTADO FINAL: {'PASS' if all_ok else 'FAIL'}")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
