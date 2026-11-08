#!/usr/bin/env bash
# =====================================================================
# run_demo.sh - Concurrency Demo: Two sessions, last bottle
# Bodegas del Atuel - Issue #36
#
# Escenarios demo:
#   1. CON FOR UPDATE: A bloquea, B espera, A confirma, B ve stock=0
#   2. SIN FOR UPDATE (ver aparte): Doble venta (lost update)
#   3. REPEATABLE READ: Error 40001 serialización
# =====================================================================

set -euo pipefail

# Cargar variables de entorno desde .env
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

# Validar variables requeridas
if [ -z "${POSTGRES_USER:-}" ]; then
  echo "ERROR: POSTGRES_USER no definida en .env" >&2
  exit 1
fi

if [ -z "${POSTGRES_DB:-}" ]; then
  echo "ERROR: POSTGRES_DB no definida en .env" >&2
  exit 1
fi

if [ -z "${APP_DB_PASSWORD:-}" ]; then
  echo "ERROR: APP_DB_PASSWORD no definida en .env" >&2
  exit 1
fi

DB_USER="${POSTGRES_USER}"
DB_NAME="${POSTGRES_DB}"
APP_PASSWORD="${APP_DB_PASSWORD}"
DEMO_DIR="$(dirname "$0")"

# Colores en output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================================="
echo "Demo de Concurrencia: Ultima botella de vino"
echo "=========================================================="
echo ""
echo "Datos de demo:"
echo "  - Sala: 7 (id_sala)"
echo "  - Vino: 9 (cod_vino, Demo Wine Tinto)"
echo "  - Stock inicial: 1 botella"
echo "  - Usuario: ${DB_USER}"
echo "  - Nivel de aislamiento por defecto: READ COMMITTED"
echo ""
echo "Notas:"
echo "  - La sesion A BEGIN...FOR UPDATE bloquea la fila"
echo "  - La sesion B BEGIN...FOR UPDATE espera a que A confirme"
echo "  - Los timestamps usan clock_timestamp() para mostrar la diferencia"
echo "  - PGPASSWORD se usa solo para la sesion actual (variable de entorno)"
echo ""
echo "Presione CTRL+C para cancelar o Enter para continuar..."
read -r
echo ""

# Función para ejecutar un script SQL y capturar salida con timestamps
run_sql_session() {
  local nombre="$1"
  local archivo="$2"
  local pid_espera="$3"
  
  echo ""
  echo "--- Iniciando ${nombre} (PID expected: ${pid_espera}) ---"
  echo "Archivo SQL: ${archivo}"
  echo ""
  
  # Ejecutar el script SQL dentro del contenedor db
  # Usar PGPASSWORD solo para esta sesión
  export PGPASSWORD="${APP_PASSWORD}"
  
  # Ejecutar en segundo plano para sesiones paralelas
  # Usar timeout para evitar que se quede colgado eternamente
  timeout 60 docker compose exec -T db psql -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -f "${archivo}" > "/tmp/conc_demo_${nombre}.out" 2> "/tmp/conc_demo_${nombre}.err" &
  local pid_puerto=$!
  
  # Guardar el PID para esperar después
  eval "PID_${nombre}=${pid_puerto}"
  
  unset PGPASSWORD
}

# Ejecutar las sesiones en PARALELO
echo "=== Lanzando sesiones A y B en paralelo ==="
echo "La sesión A tomará el lock de la última botella."
echo "La sesión B intentará bloquear y esperará a que A termine."
echo ""
echo "--- PASO 1: Lanzando sesión A (bloqueo primero) ---"
run_sql_session "A" "${DEMO_DIR}/sesion_a.sql" "espera_B"
PID_A=$!

echo ""
echo "--- PASO 2: Lanzando sesión B (después de A) ---"
run_sql_session "B" "${DEMO_DIR}/sesion_b.sql" "espera_A"
PID_B=$!

echo ""
echo "--- PASO 3: Esperando a que ambas sesiones terminen ---"
# Esperar a la sesión A primero (ella es la que inicia el lock)
wait $PID_A 2>/dev/null && echo "Sesión A finalizada" || echo "Sesión A termino con timeout o error"

# Esperar a la sesión B
wait $PID_B 2>/dev/null && echo "Sesión B finalizada" || echo "Sesión B termino con timeout o error"

echo ""
echo "--- REVISANDO RESULTADOS ---"

# Mostrar outputs resumidos
if [ -f "/tmp/conc_demo_A.out" ]; then
    echo ""
    echo "--- Output Sesión A (resumen) ---"
    grep -E '(inicio_sesion|fin_sesion|hora_commit|Stock|PID)' "/tmp/conc_demo_A.out" || echo "No se encontraron marcas de tiempo esperadas"
fi

if [ -f "/tmp/conc_demo_B.out" ]; then
    echo ""
    echo "--- Output Sesión B (resumen) ---"
    grep -E '(inicio_sesion|fin_sesion|Stock|Decision)' "/tmp/conc_demo_B.out" || echo "No se encontraron marcas de tiempo esperadas"
fi

# Limpiar archivos temporales
rm -f "/tmp/conc_demo_A.out" "/tmp/conc_demo_A.err" "/tmp/conc_demo_B.out" "/tmp/conc_demo_B.err"

echo ""
echo "=== Demo finalizada ==="
echo ""
echo "Para un análisis detallado, revisar los logs completos en /tmp/conc_demo_*.out y .err"
echo "=========================================================="