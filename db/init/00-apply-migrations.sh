#!/bin/sh
# =====================================================================
# 00-apply-migrations.sh
#
# Se ejecuta al iniciar el contenedor de postgres
# (directorio /docker-entrypoint-initdb.d), SOLO cuando el volumen de
# datos esta vacio (primera creacion).
#
# Aplica las migraciones 001 a 007 en orden numerico estricto sobre la
# base POSTGRES_DB, que la imagen oficial de postgres crea automaticamente.
# La migracion 008 (indices) NO se aplica aqui: la etapa 4 exige medir
# rendimiento antes y despues de crear los indices, por lo que se aplica
# aparte con scripts/aplicar_indices.sh.
#
# Pasa la variable psql `app_password` (desde APP_DB_PASSWORD) para que
# 007_roles.sql pueda usar:  PASSWORD :'app_password'
#
# Cualquier error detiene el proceso: set -e y psql -v ON_ERROR_STOP=1.
# =====================================================================

set -euo pipefail

DB="${POSTGRES_DB:-bodegas_del_atuel}"
USER="${POSTGRES_USER:-postgres}"
APP_DB_PASSWORD="${APP_DB_PASSWORD:?Falta la variable de entorno APP_DB_PASSWORD}"
export PGPASSWORD="${POSTGRES_PASSWORD:?Falta la variable de entorno POSTGRES_PASSWORD}"

echo "[init] Aplicando migraciones 001 a 007 en orden numerico sobre la base '$DB'..."

for f in \
  /migrations/001_esquema.sql \
  /migrations/002_constraints.sql \
  /migrations/003_funciones.sql \
  /migrations/004_procedimientos.sql \
  /migrations/005_triggers.sql \
  /migrations/006_vistas.sql \
  /migrations/007_roles.sql
do
  echo "[init] -> $f"
  psql -v ON_ERROR_STOP=1 \
       -v app_password="$APP_DB_PASSWORD" \
       -U "$USER" \
       -d "$DB" \
       -f "$f"
done

echo "[init] Migraciones 001 a 007 aplicadas correctamente."
