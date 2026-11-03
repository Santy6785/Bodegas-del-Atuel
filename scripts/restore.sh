#!/bin/sh
# =====================================================================
# restore.sh
#
# Restaura un dump en una BASE NUEVA y muestra el conteo de filas de
# algunas tablas para verificar la restauración.
#
# Uso:
#   ./scripts/restore.sh [archivo_dump.sql.gz] [nombre_nueva_base]
#
# Ejemplos:
#   ./scripts/restore.sh backups/dump_completo.sql.gz
#   ./scripts/restore.sh backups/dump_completo.sql.gz bodegas_del_atuel_restaurado
#
# Si se omite el archivo, se usa backups/dump_completo.sql.gz.
# Si se omite el nombre, se genera uno con marca de tiempo.
# =====================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Cargar variables de entorno (.env)
set -a
. "$PROJECT_ROOT/.env"
set +a

DUMP_FILE="${1:-$PROJECT_ROOT/backups/dump_completo.sql.gz}"
NEW_DB="${2:-bodegas_del_atuel_restaurado_$(date +%Y%m%d%H%M%S)}"

if [ ! -f "$DUMP_FILE" ]; then
  echo "[restore] ERROR: no se encuentra el dump: $DUMP_FILE" >&2
  exit 1
fi

echo "[restore] Creando base nueva '${NEW_DB}'..."
docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
  psql -h localhost -U "$POSTGRES_USER" -d postgres \
  -c "CREATE DATABASE \"$NEW_DB\";"

echo "[restore] Restaurando dump en '${NEW_DB}'..."
if echo "$DUMP_FILE" | grep -q '\.gz$'; then
  gunzip -c "$DUMP_FILE" | \
    docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
      psql -h localhost -U "$POSTGRES_USER" -d "$NEW_DB" -v ON_ERROR_STOP=1
else
  docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
    psql -h localhost -U "$POSTGRES_USER" -d "$NEW_DB" -v ON_ERROR_STOP=1 -f "$DUMP_FILE"
fi

echo "[restore] Conteo de filas (verificación):"
docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" db \
  psql -h localhost -U "$POSTGRES_USER" -d "$NEW_DB" -c "
SELECT 'cepa'           AS tabla, count(*) AS filas FROM cepa
UNION ALL SELECT 'vino',           count(*) FROM vino
UNION ALL SELECT 'sala_venta',     count(*) FROM sala_venta
UNION ALL SELECT 'cliente',        count(*) FROM cliente
UNION ALL SELECT 'comprobante',    count(*) FROM comprobante;
"

echo "[restore] OK: base '${NEW_DB}' restaurada."
