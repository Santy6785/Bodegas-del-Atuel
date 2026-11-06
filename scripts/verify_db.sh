#!/usr/bin/env bash
# =====================================================================
# verify_db.sh - Bodegas del Atuel
#
# Script de verificación para el servicio PostgreSQL (Issue #31).
# 1. Espera a que el contenedor alcance el estado 'healthy'.
# 2. Revisa los logs de db y falla si encuentra líneas con "ERROR".
# 3. Lista las tablas creadas (\dt).
# 4. Lista los tipos de datos y dominios creados (\dT).
# 5. Muestra la cantidad de constraints por tipo desde pg_constraint
#    (p = PRIMARY KEY, f = FOREIGN KEY, u = UNIQUE, c = CHECK).
# =====================================================================

set -euo pipefail

# Cargar variables de entorno locales si existe .env
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

DB_USER="${POSTGRES_USER:-owner_bodegas}"
DB_NAME="${POSTGRES_DB:-bodegas_atuel}"

echo "=========================================================="
echo "Verificación del Servicio de Base de Datos (db)"
echo "Base de datos: $DB_NAME | Usuario: $DB_USER"
echo "=========================================================="

echo ""
echo "[1/4] Esperando a que el contenedor 'db' esté 'healthy'..."
TIMEOUT=60
ELAPSED=0
STATUS=""

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
  CONTAINER_ID=$(docker compose ps -q db 2>/dev/null || true)
  if [ -n "$CONTAINER_ID" ]; then
    STATUS=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$CONTAINER_ID" 2>/dev/null || echo "starting")
    if [ "$STATUS" = "healthy" ]; then
      echo " -> Contenedor 'db' reporta estado HEALTHY tras ${ELAPSED}s."
      break
    elif [ "$STATUS" = "unhealthy" ]; then
      echo "ERROR: El contenedor 'db' pasó a estado UNHEALTHY." >&2
      docker compose logs db
      exit 1
    fi
  fi
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

if [ "$STATUS" != "healthy" ]; then
  echo "ERROR: Tiempo de espera agotado (${TIMEOUT}s) esperando el estado healthy. Estado actual: '$STATUS'." >&2
  docker compose logs db
  exit 1
fi

echo ""
echo "[2/4] Verificando logs del servicio 'db' en busca de errores..."
if docker compose logs db 2>&1 | grep "ERROR"; then
  echo ""
  echo "ERROR: Se encontraron líneas con 'ERROR' en los logs de inicialización del servicio 'db'." >&2
  exit 1
fi
echo " -> No se detectaron líneas con 'ERROR' en los logs."

echo ""
echo "[3/4] Listando esquemas y objetos de base de datos..."
echo ""
echo "--- Tablas (\dt) ---"
docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -c "\dt"

echo ""
echo "--- Tipos y Dominios (\dT) ---"
docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -c "\dT"

echo ""
echo "[4/4] Conteo de constraints por tipo en el esquema 'public'..."
docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -c "
SELECT 
    contype AS tipo,
    CASE contype
        WHEN 'p' THEN 'PRIMARY KEY (p)'
        WHEN 'f' THEN 'FOREIGN KEY (f)'
        WHEN 'u' THEN 'UNIQUE (u)'
        WHEN 'c' THEN 'CHECK (c)'
        ELSE contype::text
    END AS descripcion,
    COUNT(*) AS cantidad
FROM pg_constraint
WHERE connamespace = 'public'::regnamespace
  AND contype IN ('p', 'f', 'u', 'c')
GROUP BY contype
ORDER BY contype;
"

echo ""
echo "=========================================================="
echo "OK: Verificación completada con éxito. Todos los chequeos pasaron."
echo "=========================================================="
exit 0
