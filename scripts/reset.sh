#!/bin/sh
# =====================================================================
# reset.sh
#
# Ejecuta 'docker compose down -v' (detiene y elimina contenedores y
# VOLÚMENES, borrando TODOS los datos de PostgreSQL) y vuelve a levantar
# los servicios con 'docker compose up --build -d'.
#
# Las migraciones se aplican de nuevo sobre la base vacía al iniciar db.
# Para cargar datos de prueba:
#   docker compose --profile seed run --rm seed
#
# Uso:
#   ./scripts/resest.sh          (pide confirmación)
#   ./scripts/reset.sh --yes     (sin confirmación)
# =====================================================================

set -euo pipefail

SKIP_PROMPT=0
if [ "${1:-}" = "--yes" ]; then
  SKIP_PROMPT=1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "!!! ADVERTENCIA !!!"
echo "Este script ejecuta 'docker compose down -v', lo que BORRA TODOS LOS DATOS"
echo "almacenados en el volumen de PostgreSQL y los recrea vacíos."
echo "Luego levanta los servicios con 'docker compose up --build -d'."
echo ""
echo "Las migraciones se aplicarán de nuevo sobre la base vacía al iniciar."
echo "Para cargar datos de prueba: docker compose --profile seed run --rm seed"
echo ""

if [ "$SKIP_PROMPT" -eq 0 ]; then
  printf "¿Desea continuar? (s/N): "
  read -r respuesta
  if [ "$respuesta" != "s" ] && [ "$respuesta" != "S" ]; then
    echo "Operación cancelada."
    exit 0
  fi
fi

cd "$PROJECT_ROOT"

echo "[reset] Ejecutando docker compose down -v ..."
docker compose down -v

echo "[reset] Levantando servicios con docker compose up --build -d ..."
docker compose up --build -d

echo "[reset] Listo. Volumen de base de datos recreado (vacío)."
