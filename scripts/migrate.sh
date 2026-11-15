#!/usr/bin/env bash
# =====================================================================
# migrate.sh - Bodegas del Atuel
#
# Ejecutor determinístico de migraciones para PostgreSQL (Issue #32).
# - Aplica los archivos .sql en orden alfabético estricto (LC_ALL=C).
# - Se detiene inmediatamente ante el primer error (-v ON_ERROR_STOP=1).
# - Ejecuta cada archivo dentro de una transacción única (--single-transaction).
# - Soporta modo Docker Compose (local por defecto) y modo directo (DATABASE_URL).
# =====================================================================

set -euo pipefail

# Configuración y valores por defecto
MIGRATIONS_DIR="db/migrations"
DATABASE_URL="${DATABASE_URL:-}"
CONNECTION_MODE="docker"

# Cargar variables de entorno desde .env si existe
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

DB_USER="${POSTGRES_USER:-owner_bodegas}"
DB_NAME="${POSTGRES_DB:-bodegas_atuel}"

# Contraseña del rol de aplicación (app_rw) y de solo lectura (reportes_ro),
# leídas de APP_DB_PASSWORD y APP_RO_PASSWORD en .env. Se inyectan al contenedor
# Docker mediante -e (sin exponerlas en la línea de comandos) y, en modo
# directo, se exportan como PGPASSWORD justo antes de invocar psql.
APP_DB_PASSWORD="${APP_DB_PASSWORD:-}"
APP_RO_PASSWORD="${APP_RO_PASSWORD:-${APP_DB_PASSWORD:-}}"

# Variables psql: solo ON_ERROR_STOP=1 (las contraseñas viajan por entorno,
# nunca con -v en la línea de comandos).
PSQL_VARS=(-v ON_ERROR_STOP=1)

# Función de ayuda
show_help() {
  cat << 'EOF'
Uso: ./scripts/migrate.sh [OPCIONES]

Aplica las migraciones SQL en orden determinístico y se detiene ante el primer error.

Opciones:
  --dir <carpeta>      Directorio con archivos .sql (por defecto: db/migrations).
  --url <cadena>       Cadena de conexión PostgreSQL (DATABASE_URL).
                       Si se especifica, activa el modo directo con psql.
  -h, --help           Muestra esta ayuda y finaliza.

Modos de conexión:
  1. Modo Docker (por defecto):
     Ejecuta las migraciones dentro del contenedor 'db' vía 'docker compose exec'.
     Utiliza las variables POSTGRES_USER y POSTGRES_DB (de .env o entorno).
     Las contraseñas (APP_DB_PASSWORD y APP_RO_PASSWORD) se inyectan al contenedor
     con -e, por entorno, sin exponerlas en la línea de comandos.
  2. Modo Directo:
     Se activa si se pasa --url o si existe la variable DATABASE_URL.
     Ejecuta psql directamente con la cadena provista (adecuado para la nube o bases remotas).
     La contraseña se exporta como PGPASSWORD (desde APP_DB_PASSWORD en .env) justo
     antes de invocar psql, sin exponerla en la línea de comandos.

Comportamiento:
  - Ejecuta cada migración con -v ON_ERROR_STOP=1 y --single-transaction (-1).
  - Si un archivo falla, la ejecución se detiene de inmediato sin tocar los siguientes.
  - El script NO es idempotente: reejecutar sobre una base ya migrada fallará
    en la primera migración por conflicto de objetos existentes.
  - 008_indices.sql no se aplica aquí: ejecútala aparte con
    scripts/aplicar_indices.sh (etapa 4 del TPI, para medir rendimiento).
  - Las contraseñas viajan por entorno (APP_DB_PASSWORD / APP_RO_PASSWORD),
    nunca en la línea de comandos ni en URLs.
EOF
}

# Parseo de argumentos de línea de comandos
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: La opción --dir requiere un argumento." >&2
        exit 1
      fi
      MIGRATIONS_DIR="$2"
      shift 2
      ;;
    --url)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: La opción --url requiere un argumento." >&2
        exit 1
      fi
      DATABASE_URL="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "ERROR: Opción no reconocida: $1" >&2
      show_help >&2
      exit 1
      ;;
  esac
done

# Determinar el modo de conexión activo
if [[ -n "$DATABASE_URL" ]]; then
  CONNECTION_MODE="direct"
else
  CONNECTION_MODE="docker"
fi

# Argumentos extra para 'docker compose exec ... psql'.
# -e APP_DB_PASSWORD y -e APP_RO_PASSWORD inyectan las contraseñas por entorno
# (Docker toma el valor del entorno del script; no aparecen en la línea de comandos).
DOCKER_PSQL_ARGS=(-T db -e APP_DB_PASSWORD -e APP_RO_PASSWORD)

# Validación previa: existencia del directorio de migraciones
if [[ ! -d "$MIGRATIONS_DIR" ]]; then
  echo "ERROR: El directorio de migraciones '$MIGRATIONS_DIR' no existe." >&2
  exit 1
fi

# Obtener lista ordenada de migraciones (LC_ALL=C para orden de bytes determinístico)
MIGRATION_FILES=()
while IFS= read -r file; do
  [[ -n "$file" ]] && MIGRATION_FILES+=("$file")
done < <(find "$MIGRATIONS_DIR" -maxdepth 1 -name "*.sql" -not -name "008_indices.sql" -type f | LC_ALL=C sort)

TOTAL_MIGRATIONS=${#MIGRATION_FILES[@]}
if [[ "$TOTAL_MIGRATIONS" -eq 0 ]]; then
  echo "ERROR: No se encontraron archivos .sql en el directorio '$MIGRATIONS_DIR'." >&2
  exit 1
fi

# Enmascarar la cadena de conexión mostrando únicamente host y base de datos
mask_connection_url() {
  local url="$1"
  local host_info=""
  local db_info=""

  if [[ "$url" =~ @([^/?]+) ]]; then
    host_info="${BASH_REMATCH[1]}"
  elif [[ "$url" =~ ://([^/@?]+) ]]; then
    host_info="${BASH_REMATCH[1]}"
  else
    host_info="desconocido"
  fi

  if [[ "$url" =~ /([^/?]+)(\?.*)?$ ]]; then
    db_info="${BASH_REMATCH[1]}"
  else
    db_info="desconocida"
  fi

  echo "Host: ${host_info} | Base: ${db_info}"
}

# Si estamos en modo directo y psql no está en PATH, intentar ubicarlo en rutas comunes (ej. Windows)
if [[ "$CONNECTION_MODE" = "direct" ]] && ! command -v psql >/dev/null 2>&1; then
  for pg_bin in /c/"Program Files"/PostgreSQL/*/bin /c/"Program Files (x86)"/PostgreSQL/*/bin; do
    if [ -d "$pg_bin" ] && [ -x "$pg_bin/psql.exe" ]; then
      export PATH="$PATH:$pg_bin"
      break
    fi
  done
fi

# Validaciones de herramientas y conectividad previa (SELECT 1)
if [[ "$CONNECTION_MODE" = "direct" ]]; then
  if ! command -v psql >/dev/null 2>&1; then
    echo "ERROR: El modo directo requiere la herramienta 'psql' en el PATH del sistema." >&2
    exit 1
  fi
  # PGPASSWORD viaja por entorno (desde APP_DB_PASSWORD en .env), no en la línea de comandos.
  if [[ -n "${APP_DB_PASSWORD:-}" ]]; then
    export PGPASSWORD="$APP_DB_PASSWORD"
  fi
  TARGET_INFO=$(mask_connection_url "$DATABASE_URL")
  echo "Modo de conexión: DIRECTO (${TARGET_INFO})"
  echo "Comprobando conectividad inicial con la base de datos..."
  if ! psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "SELECT 1;" >/dev/null 2>&1; then
    echo "ERROR: No se pudo conectar a la base de datos en modo directo (${TARGET_INFO})." >&2
    echo "Verifique que el host y puerto estén disponibles, y que las credenciales sean válidas." >&2
    exit 1
  fi
else
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: El modo Docker requiere 'docker' disponible en el PATH del sistema." >&2
    exit 1
  fi
  echo "Modo de conexión: DOCKER COMPOSE (Contenedor 'db' | Base: ${DB_NAME} | Usuario: ${DB_USER})"
  echo "Comprobando conectividad con el contenedor 'db'..."
  if ! docker compose exec "${DOCKER_PSQL_ARGS[@]}" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -c "SELECT 1;" >/dev/null 2>&1; then
    echo "ERROR: No se pudo conectar a PostgreSQL dentro del contenedor 'db'." >&2
    echo "Asegúrese de que el servicio 'db' esté iniciado (ej. 'docker compose up -d') y en estado saludable." >&2
    exit 1
  fi
fi

echo "Conectividad confirmada. Iniciando ejecución."
echo ""
echo "=========================================================="
echo "Plan de ejecución (${TOTAL_MIGRATIONS} migraciones detectadas en '${MIGRATIONS_DIR}'):"
for mig in "${MIGRATION_FILES[@]}"; do
  echo "  - $(basename "$mig")"
done
echo "=========================================================="
echo ""

START_TIME=$(date +%s)
APPLIED_COUNT=0

# Aplicación secuencial de migraciones
for mig in "${MIGRATION_FILES[@]}"; do
  MIG_NAME=$(basename "$mig")
  IDX=$((APPLIED_COUNT + 1))
  echo "[$IDX/$TOTAL_MIGRATIONS] Aplicando $MIG_NAME..."

  if [[ "$CONNECTION_MODE" = "direct" ]]; then
    if ! psql "$DATABASE_URL" "${PSQL_VARS[@]}" --single-transaction < "$mig"; then
      echo "" >&2
      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
      echo "ERROR CRÍTICO: Falló la migración '$MIG_NAME'." >&2
      echo "Se detuvo la ejecución. Las migraciones posteriores NO fueron ejecutadas." >&2
      echo "Debido a --single-transaction, cualquier cambio en '$MIG_NAME' fue revertido." >&2
      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
      exit 1
    fi
  else
    if ! docker compose exec "${DOCKER_PSQL_ARGS[@]}" psql -U "$DB_USER" -d "$DB_NAME" "${PSQL_VARS[@]}" --single-transaction < "$mig"; then
      echo "" >&2
      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
      echo "ERROR CRÍTICO: Falló la migración '$MIG_NAME'." >&2
      echo "Se detuvo la ejecución. Las migraciones posteriores NO fueron ejecutadas." >&2
      echo "Debido a --single-transaction, cualquier cambio en '$MIG_NAME' fue revertido." >&2
      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
      exit 1
    fi
  fi

  APPLIED_COUNT=$((APPLIED_COUNT + 1))
  echo " -> $MIG_NAME aplicado exitosamente."
done

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "=========================================================="
echo "RESUMEN: Migraciones aplicadas con éxito: $APPLIED_COUNT de $TOTAL_MIGRATIONS"
echo "Tiempo transcurrido: ${ELAPSED}s"
echo "=========================================================="
exit 0
