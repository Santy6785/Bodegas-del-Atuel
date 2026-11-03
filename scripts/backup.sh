#!/bin/sh
# =====================================================================
# backup.sh
#
# Crea un dump comprimido de la base de datos completa en
#   backups/dump_completo.sql.gz
#
# Requisitos:
#   - Archivo .env presente en la raíz del proyecto.
#   - Servicios levantados con docker compose (db sano).
#
# Se conecta a la base como el superusuario/propietario (POSTGRES_USER)
# para volcar todo el esquema y los datos.
# =====================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Cargar variables de entorno (.env)
set -a
. "$PROJECT_ROOT/.env"
set +a

DUMP_DIR="$PROJECT_ROOT/backups"
DUMP_FILE="$DUMP_DIR/dump_completo.sql.gz"

mkdir -p "$DUMP_DIR"

echo "[backup] Volcando la base '${POSTGRES_DB}' a '${DUMP_FILE}'..."

docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
  pg_dump -h localhost -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  | gzip > "$DUMP_FILE"

echo "[backup] OK: $DUMP_FILE"
