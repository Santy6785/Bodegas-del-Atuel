#!/bin/sh
# =====================================================================
# aplicar_indices.sh
#
# Ejecuta la migracion 008_indices.sql contra el contenedor db con el
# PROPIETARIO de la base y -v ON_ERROR_STOP=1.
#
# Esta migracion NO se aplica en el init automatico de docker
# (docker-entrypoint-initdb.d), porque la etapa 4 exige medir el
# rendimiento antes y despues de crear los indices. Se ejecuta aparte:
#
#   ./scripts/aplicar_indices.sh
#
# Requisitos:
#   - Archivo .env presente en la raiz del proyecto.
#   - Servicio db levantado y sano.
# =====================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Cargar variables de entorno (.env)
set -a
. "$PROJECT_ROOT/.env"
set +a

export PGPASSWORD="${POSTGRES_PASSWORD:?Falta POSTGRES_PASSWORD en .env}"

echo "[aplicar_indices] Ejecutando 008_indices.sql como propietario '${POSTGRES_USER}'..."

docker compose exec -T db \
  psql -v ON_ERROR_STOP=1 \
       -U "$POSTGRES_USER" \
       -d "$POSTGRES_DB" \
       -f /migrations/008_indices.sql

echo "[aplicar_indices] OK: indices aplicados."
