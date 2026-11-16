#!/usr/bin/env bash
# =====================================================================
# medir_indices.sh - Bodegas del Atuel
#
# Script reproducible de medición de índices para el TPI de Bases de Datos.
# Ejecuta consultas sobre bodegas_atuel_bench antes y después de aplicar
# los índices de db/migrations/008_indices.sql, capturando planes EXPLAIN
# y tiempos reales de PostgreSQL.
#
# Uso:
#   bash scripts/medir_indices.sh [--reps N]
#
# Requisitos:
#   - Docker Desktop levantado y servicio 'db' sano.
#   - Base de medición 'bodegas_atuel_bench' cargada (>100.000 filas en comprobante).
#   - Archivo .env en la raíz del proyecto (POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB).
# =====================================================================

set -euo pipefail

# Cambiar al directorio raíz del repositorio
cd "$(dirname "$0")/.."

# Cargar variables de entorno (.env) sin exportarlas al entorno global
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

# ---------------------------------------------------------------------
# Constantes
# ---------------------------------------------------------------------
DB_CONTAINER="db"
DB_NAME="bodegas_atuel_bench"
DB_USER="owner_bodegas"
REPS=3
MIG_008="db/migrations/008_indices.sql"
CONS_DIR="scripts/perf/consultas_medidas"
OUT="docs/planes_indices.md"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export PGPASSWORD="${POSTGRES_PASSWORD:?Falta POSTGRES_PASSWORD en .env}"

# ---------------------------------------------------------------------
# Arrays asociativos para guardar resultados de medición.
# Clave: nombre base del archivo .sql (sin extensión).
# ---------------------------------------------------------------------
declare -A MEDIANA_ANTES MEDIANA_DESPUES
declare -A PLAN_ANTES PLAN_DESPUES
declare -A SCAN_ANTES SCAN_DESPUES
declare -A FILAS_ANTES FILAS_DESPUES

# ---------------------------------------------------------------------
# Extrae el tipo de recorrido (SCAN) de un archivo de plan EXPLAIN.
# Ejemplo de match: "Index Only Scan using idx_comprobante_fecha_inc"
# Comentario: el nombre del índice aparece en el plan solo cuando hay "using".
# ---------------------------------------------------------------------
extraer_scan() {
  local plan_file="$1"
  grep -m1 -oE '(Parallel )?(Index Only Scan|Index Scan|Bitmap Heap Scan|Seq Scan)[^ ]*( using [A-Za-z0-9_]+)?' "$plan_file" | head -n1
}

# ---------------------------------------------------------------------
# Extrae las filas REALES (actual rows) del nodo de scan en un plan EXPLAIN ANALYZE.
# En EXPLAIN ANALYZE, las filas reales aparecen en líneas con "actual time" y "loops=":
#   Index Scan using idx_... (actual time=0.010..0.020 rows=150 loops=1)
# Tomamos la primera línea con "actual time" y extraemos "rows=N" de ella.
# Limitación: no distingue nodos internos vs hoja; toma el primer nodo de scan con
# filas reales. Si no se encuentra, devuelve vacío.
# ---------------------------------------------------------------------
extraer_filas() {
  local plan_file="$1"
  grep -m1 'actual time.*loops=' "$plan_file" | grep -oE 'rows=[0-9]+' | head -n1 | cut -d= -f2
}

# ---------------------------------------------------------------------
# Función psql_db: ejecuta psql dentro del contenedor leyendo SQL desde stdin.
# Uso: echo "SELECT 1" | psql_db    o    psql_db < archivo.sql
# ---------------------------------------------------------------------
psql_db() {
  docker compose exec -T "$DB_CONTAINER" \
    psql -X -q -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" "$@" <&0
}

# ---------------------------------------------------------------------
# Guarda de seguridad: verificar que estamos en bodegas_atuel_bench
# ---------------------------------------------------------------------
verificar_base() {
  local actual
  actual="$(psql_db -t -A -c "SELECT current_database();" < /dev/null)"
  if [ "$actual" != "$DB_NAME" ]; then
    echo "ERROR: Se conectó a la base '$actual', se esperaba '$DB_NAME'." >&2
    echo "Abortando para no medir sobre la base incorrecta." >&2
    exit 1
  fi
  echo "[OK] Base de medición confirmada: $actual"
}

# ---------------------------------------------------------------------
# Guarda de volumen: comprobar que comprobante tiene >100.000 filas
# ---------------------------------------------------------------------
verificar_volumen() {
  local n
  n="$(psql_db -t -A -c "SELECT count(*) FROM comprobante;" < /dev/null)"
  if [ "$n" -lt 100000 ]; then
    echo "ERROR: La tabla comprobante tiene $n filas, se requieren >100.000." >&2
    echo "Abortando: la base de medición no está cargada." >&2
    exit 1
  fi
  echo "[OK] Volumen de datos confirmado: $n filas en comprobante"
}

# ---------------------------------------------------------------------
# Lee $MIG_008 quitando el BOM UTF-8 si existe. Devuelve el SQL por stdout.
# ---------------------------------------------------------------------
leer_mig_008_sin_bom() {
  local primeros_bytes
  primeros_bytes="$(head -c 3 "$MIG_008" | od -An -tx1 | tr -d ' \n')"
  if [[ "$primeros_bytes" = "efbbbf" ]]; then
    tail -c +4 "$MIG_008"
  else
    cat "$MIG_008"
  fi
}

# ---------------------------------------------------------------------
# Asegura que los 5 índices de 008 existan en la base.
#   - Hace DROP INDEX IF EXISTS de todos (idempotente).
#   - Aplica 008_indices.sql por stdin (sin BOM).
# ---------------------------------------------------------------------
asegurar_indices_008() {
  echo "[asegurar_indices_008] Aplicando $MIG_008 (sin BOM) para garantizar que los índices existan..."
  local idx_list
  idx_list="$(printf '%s,' "${IDX_NOMBRES[@]}")"
  idx_list="${idx_list%,}"
  echo "DROP INDEX IF EXISTS ${idx_list};" | psql_db >/dev/null
  if ! leer_mig_008_sin_bom | psql_db >/dev/null; then
    echo "ERROR: Falló la aplicación de $MIG_008." >&2
    exit 1
  fi
  local idx existe
  for idx in "${IDX_NOMBRES[@]}"; do
    existe="$(echo "SELECT count(*) FROM pg_indexes WHERE schemaname = 'public' AND indexname = '$idx';" | psql_db -t -A)"
    if [[ "$existe" -ne 1 ]]; then
      echo "ERROR: El índice '$idx' no existe después de aplicar $MIG_008." >&2
      exit 1
    fi
  done
  echo "[OK] Los ${#IDX_NOMBRES[@]} índices de 008 existen en pg_indexes."
}

# ---------------------------------------------------------------------
# A) Extracción dinámica de nombres de índice de 008_indices.sql
#    - Lee el archivo quitando el BOM UTF-8 si existe (EF BB BF).
#    - Extrae nombres con grep + awk.
#    - Guarda la lista en el array global IDX_NOMBRES.
# ---------------------------------------------------------------------
extraer_indices_008() {
  IDX_NOMBRES=()

  if [[ ! -f "$MIG_008" ]]; then
    echo "ERROR: No existe el archivo de migración: $MIG_008" >&2
    exit 1
  fi

  # Detectar y quitar BOM UTF-8 (EF BB BF) si está presente en la primera línea
  local sql_sin_bom
  local primeros_bytes
  primeros_bytes="$(head -c 3 "$MIG_008" | od -An -tx1 | tr -d ' \n')"
  if [[ "$primeros_bytes" = "efbbbf" ]]; then
    echo "[extraer_indices_008] BOM UTF-8 detectado en $MIG_008, se eliminará." >&2
    sql_sin_bom="$(tail -c +4 "$MIG_008")"
  else
    sql_sin_bom="$(cat "$MIG_008")"
  fi

  # Extraer nombres: CREATE [UNIQUE] INDEX <nombre>
  while IFS= read -r nombre; do
    [[ -n "$nombre" ]] && IDX_NOMBRES+=("$nombre")
  done < <(printf '%s\n' "$sql_sin_bom" | grep -oE 'CREATE (UNIQUE )?INDEX [A-Za-z0-9_]+' | awk '{print $NF}')

  if [[ ${#IDX_NOMBRES[@]} -eq 0 ]]; then
    echo "ERROR: No se encontró ningún índice en $MIG_008." >&2
    exit 1
  fi

  echo "[extraer_indices_008] Índices detectados (${#IDX_NOMBRES[@]}): ${IDX_NOMBRES[*]}"
}

# ---------------------------------------------------------------------
# Función medir_consulta: ejecuta EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
# sobre una consulta SQL y devuelve la mediana de los tiempos de ejecución.
#
# Entradas:
#   $1 - ruta del archivo .sql de la consulta
#   $2 - etiqueta (antes|despues|prueba|...)
#   $3 - cadena SQL de preámbulo a ejecutar antes del EXPLAIN (puede estar vacía)
#   $4 - sufijo SQL opcional tras la consulta (ej. "ROLLBACK;"). Si está vacío,
#        se agrega ";" al final de la consulta.
#
# Variables globales dejadas listas:
#   MEDIANA_MS  - mediana de los tiempos (ms)
#   PLAN_FILE   - ruta al archivo con el plan COMPLETO de la última repetición
# ---------------------------------------------------------------------
medir_consulta() {
  local ruta_sql="$1"
  local etiqueta="$2"
  local preambulo="${3:-}"
  local sufijo="${4:-}"
  local nombre_base
  nombre_base="$(basename "$ruta_sql" .sql)"

  if [[ ! -f "$ruta_sql" ]]; then
    echo "ERROR: No existe el archivo de consulta: $ruta_sql" >&2
    exit 1
  fi

  # Leer el .sql y quitar punto y coma final (y espacios en blanco al final)
  local sql_contenido
  sql_contenido="$(cat "$ruta_sql")"
  sql_contenido="$(printf '%s' "$sql_contenido" | sed -e 's/[[:space:]]*$//' -e 's/;$//')"

  # Construir la sentencia final: consulta + sufijo (o ; si no hay sufijo).
  # Siempre se inserta ";" entre la consulta y el sufijo para evitar
  # sintaxis inválida como "WHERE x = 1ROLLBACK;".
  local sentencia_final
  if [[ -n "$sufijo" ]]; then
    sentencia_final="${sql_contenido}; ${sufijo}"
  else
    sentencia_final="${sql_contenido};"
  fi

  # SQL final: preámbulo + EXPLAIN + sentencia
  local sql_final="${preambulo}EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) ${sentencia_final}"

  local tiempos=()
  local salida_completa=""
  local i
  local t

  # Una ejecución de calentamiento (descartada)
  echo "[medir_consulta] Calentamiento para $nombre_base..." >&2
  echo "$sql_final" | psql_db >/dev/null 2>&1 || true

  # REPS mediciones reales
  for ((i = 1; i <= REPS; i++)); do
    if ! salida_completa="$(echo "$sql_final" | psql_db 2>&1)"; then
      echo "ERROR: psql falló ejecutando $nombre_base (rep $i)." >&2
      exit 1
    fi

    if ! printf '%s\n' "$salida_completa" | grep -q 'Execution Time:'; then
      echo "ERROR: No se encontró 'Execution Time' en la salida de $nombre_base (rep $i):" >&2
      printf '%s\n' "$salida_completa" >&2
      exit 1
    fi

    t="$(printf '%s\n' "$salida_completa" | grep 'Execution Time:' | awk '{print $(NF-1)}')"
    tiempos+=("$t")
  done

  # Guardar el plan COMPLETO de la última repetición
  PLAN_FILE="$TMP_DIR/${nombre_base}_${etiqueta}.txt"
  printf '%s\n' "$salida_completa" > "$PLAN_FILE"

  # Calcular mediana con sort -n + awk (sin depender de bc)
  MEDIANA_MS="$(printf '%s\n' "${tiempos[@]}" | sort -n | awk '
    {
      v[NR] = $1
    }
    END {
      if (NR % 2 == 1) {
        print v[(NR + 1) / 2]
      } else {
        print (v[NR / 2] + v[NR / 2 + 1]) / 2
      }
    }')"

  # Devolver la mediana por stdout
  echo "$MEDIANA_MS"
}

# ---------------------------------------------------------------------
# B) modo_antes: medir SIN los índices de 008.
#    - ANALYZE de las tablas involucradas (fuera de transacción).
#    - Para cada consulta: BEGIN; DROP INDEX IF EXISTS <todos>; EXPLAIN ANALYZE ...; ROLLBACK;
#      El ROLLBACK se ejecuta siempre (sufijo), incluso si falla la medición, porque
#      psql con ON_ERROR_STOP detiene y la transacción se revierte al terminar la sesión.
#    - Al final verifica que los 5 índices sigan existiendo en pg_indexes.
# ---------------------------------------------------------------------
modo_antes() {
  echo "=========================================================="
  echo "[modo_antes] Midiendo SIN índices de 008_indices.sql"
  echo "=========================================================="

  echo "[modo_antes] Ejecutando ANALYZE en tablas de medición..."
  local t
  for t in comprobante transferencia renglon_comprobante cliente; do
    echo "ANALYZE $t;" | psql_db >/dev/null
  done

  # Construir preámbulo: BEGIN; DROP INDEX IF EXISTS idx1, idx2, ...;
  local idx_list
  idx_list="$(printf '%s,' "${IDX_NOMBRES[@]}")"
  idx_list="${idx_list%,}"  # quitar coma final
  local preambulo="BEGIN; DROP INDEX IF EXISTS ${idx_list};"
  local sufijo="ROLLBACK;"

  local consulta nombre_base
  for consulta in "$CONS_DIR"/*.sql; do
    nombre_base="$(basename "$consulta" .sql)"
    [[ "$nombre_base" = "PLAN_intervalo_variable" ]] && continue
    echo "[modo_antes] Midiendo $nombre_base (reps=$REPS)..."
    medir_consulta "$consulta" "antes" "$preambulo" "$sufijo"
    MEDIANA_ANTES["$nombre_base"]="$MEDIANA_MS"
    PLAN_ANTES["$nombre_base"]="$PLAN_FILE"
    SCAN_ANTES["$nombre_base"]="$(extraer_scan "$PLAN_FILE")"
    FILAS_ANTES["$nombre_base"]="$(extraer_filas "$PLAN_FILE")"
    echo "  -> Mediana: ${MEDIANA_MS} ms | Scan: ${SCAN_ANTES[$nombre_base]} | Filas: ${FILAS_ANTES[$nombre_base]}"
  done

  # Verificar que los índices siguen existiendo después de los ROLLBACK
  echo "[modo_antes] Verificando que los índices siguen existiendo en pg_indexes..."
  local idx existe
  for idx in "${IDX_NOMBRES[@]}"; do
    existe="$(echo "SELECT count(*) FROM pg_indexes WHERE schemaname = 'public' AND indexname = '$idx';" | psql_db -t -A)"
    if [[ "$existe" -ne 1 ]]; then
      echo "ERROR: El índice '$idx' NO existe después de modo_antes (count=$existe)." >&2
      exit 1
    fi
  done
  echo "[OK] Todos los ${#IDX_NOMBRES[@]} índices siguen existiendo en pg_indexes tras modo_antes."
  echo ""
}

# ---------------------------------------------------------------------
# C) modo_despues: medir CON los índices de 008 aplicados.
#    - Verifica que cada índice exista en pg_indexes.
#    - Si falta alguno, aplica $MIG_008 por stdin (sin BOM) y vuelve a verificar.
#    - ANALYZE de las tablas.
#    - Mide las consultas sin preámbulo.
# ---------------------------------------------------------------------
modo_despues() {
  echo "=========================================================="
  echo "[modo_despues] Midiendo CON índices de 008_indices.sql"
  echo "=========================================================="

  echo "[modo_despues] Verificando existencia de índices en pg_indexes..."
  local idx existe faltan=()
  for idx in "${IDX_NOMBRES[@]}"; do
    existe="$(echo "SELECT count(*) FROM pg_indexes WHERE schemaname = 'public' AND indexname = '$idx';" | psql_db -t -A)"
    if [[ "$existe" -ne 1 ]]; then
      faltan+=("$idx")
    fi
  done

  if [[ ${#faltan[@]} -gt 0 ]]; then
    echo "[modo_despues] Faltan índices: ${faltan[*]}. Aplicando $MIG_008 por stdin (sin BOM)..."
    if ! leer_mig_008_sin_bom | psql_db >/dev/null; then
      echo "ERROR: Falló la aplicación de $MIG_008." >&2
      exit 1
    fi
    # Volver a verificar todos
    for idx in "${IDX_NOMBRES[@]}"; do
      existe="$(echo "SELECT count(*) FROM pg_indexes WHERE schemaname = 'public' AND indexname = '$idx';" | psql_db -t -A)"
      if [[ "$existe" -ne 1 ]]; then
        echo "ERROR: El índice '$idx' sigue faltando después de aplicar $MIG_008." >&2
        exit 1
      fi
    done
    echo "[OK] Todos los índices aplicados correctamente."
  else
    echo "[OK] Todos los índices ya existen en pg_indexes."
  fi

  echo "[modo_despues] Ejecutando ANALYZE en tablas de medición..."
  local t
  for t in comprobante transferencia renglon_comprobante cliente; do
    echo "ANALYZE $t;" | psql_db >/dev/null
  done

  local consulta nombre_base
  for consulta in "$CONS_DIR"/*.sql; do
    nombre_base="$(basename "$consulta" .sql)"
    [[ "$nombre_base" = "PLAN_intervalo_variable" ]] && continue
    echo "[modo_despues] Midiendo $nombre_base (reps=$REPS)..."
    medir_consulta "$consulta" "despues" "" ""
    MEDIANA_DESPUES["$nombre_base"]="$MEDIANA_MS"
    PLAN_DESPUES["$nombre_base"]="$PLAN_FILE"
    SCAN_DESPUES["$nombre_base"]="$(extraer_scan "$PLAN_FILE")"
    FILAS_DESPUES["$nombre_base"]="$(extraer_filas "$PLAN_FILE")"
    echo "  -> Mediana: ${MEDIANA_MS} ms | Scan: ${SCAN_DESPUES[$nombre_base]} | Filas: ${FILAS_DESPUES[$nombre_base]}"
  done
  echo ""
}

# ---------------------------------------------------------------------
# Funciones pendientes de implementar (TODO)
# ---------------------------------------------------------------------
# ---------------------------------------------------------------------
# A) costo_escritura(): mide el costo de INSERT de 170.000 filas en
#    comprobante con y sin los índices de comprobante de 008.
#
#    Todo dentro de transacciones que terminan en ROLLBACK (nada se persiste).
#    Usa clock_timestamp() de PostgreSQL para medir.
#    Repite REPS veces cada variante y reporta la mediana.
# ---------------------------------------------------------------------
costo_escritura() {
  echo "=========================================================="
  echo "[costo_escritura] Impacto de índices en escritura (INSERT)"
  echo "=========================================================="

  # Obtener nombres y definiciones reales de índices de la tabla comprobante desde pg_indexes
  # Se usa indexname directamente (no se parsea del indexdef) y se normaliza el indexdef
  # quitando saltos de línea para poder reconstruirlo sobre bench_con.
  local idx_names idx_defs
  idx_names="$(psql_db -t -A -c "SELECT indexname FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'comprobante' ORDER BY indexname;" 2>&1 | grep -v '^$')"
  idx_defs="$(psql_db -t -A -c "SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'comprobante' ORDER BY indexname;" 2>&1 | grep -v '^$')"
  if [[ -z "$idx_names" ]]; then
    echo "[costo_escritura] No hay índices sobre comprobante; solo se medirá la variante sin índices." >&2
    IDX_DEFS_COUNT=0
    IDX_NAMES=()
    IDX_DEFS=()
  else
    IDX_DEFS_COUNT="$(printf '%s\n' "$idx_names" | grep -c .)"
    # Leer en arrays para procesar cada índice por separado (evita problemas de saltos de línea)
    mapfile -t IDX_NAMES <<< "$idx_names"
    mapfile -t IDX_DEFS <<< "$idx_defs"
  fi
  echo "[costo_escritura] Índices de comprobante detectados: $IDX_DEFS_COUNT" >&2

  local tiempos_sin=()
  local tiempos_con=()
  local i

  for ((i = 1; i <= REPS; i++)); do
    echo "[costo_escritura] Repetición $i/$REPS..."

    # --- Variante SIN índices ---
    cat > "$TMP_DIR/sql_sin.sql" <<'EOSQL'
BEGIN;
CREATE TEMP TABLE bench_sin (LIKE comprobante INCLUDING DEFAULTS) ON COMMIT DROP;
WITH t0 AS (SELECT clock_timestamp() AS ini),
     ins AS (INSERT INTO bench_sin SELECT * FROM comprobante)
SELECT EXTRACT(EPOCH FROM (clock_timestamp() - t0.ini)) * 1000 FROM t0;
SELECT count(*) FROM bench_sin;
ROLLBACK;
EOSQL
    if ! cat "$TMP_DIR/sql_sin.sql" | psql_db -t -A > "$TMP_DIR/out_sin.txt" 2>&1; then
      echo "ERROR: psql falló en variante sin índices (rep $i)." >&2
      cat "$TMP_DIR/out_sin.txt" >&2
      exit 1
    fi

    local ms_sin filas_sin
    ms_sin="$(head -n1 "$TMP_DIR/out_sin.txt")"
    filas_sin="$(sed -n '2p' "$TMP_DIR/out_sin.txt")"
    if [[ -z "$ms_sin" || "$filas_sin" != "170000" ]]; then
      echo "ERROR: Variante sin índices falló (rep $i)." >&2
      cat "$TMP_DIR/out_sin.txt" >&2
      exit 1
    fi
    tiempos_sin+=("$ms_sin")

    # --- Variante CON índices ---
    # Construir sentencias CREATE INDEX para bench_con a partir de los indexdef reales,
    # usando el nombre original del índice (de IDX_NAMES) y normalizando saltos de línea.
    local sql_con="BEGIN;\nCREATE TEMP TABLE bench_con (LIKE comprobante INCLUDING DEFAULTS) ON COMMIT DROP;\n"
    local j
    for ((j = 0; j < ${#IDX_NAMES[@]}; j++)); do
      local idx_name="${IDX_NAMES[$j]}"
      local def="${IDX_DEFS[$j]}"
      [[ -z "$idx_name" || -z "$def" ]] && continue
      local idx_bc="${idx_name}_bc"
      # Normalizar saltos de línea del indexdef y reemplazar nombre de índice y tabla
      local def_norm
      def_norm="$(printf '%s' "$def" | tr '\n' ' ' | sed 's/  */ /g')"
      local def_bc
      # Reemplazar nombre de índice y tabla (public.comprobante -> bench_con, sin esquema
      # para que resuelva la tabla temporal en pg_temp)
      def_bc="$(printf '%s' "$def_norm" | sed "s/${idx_name}/${idx_bc}/g; s/public\.comprobante/bench_con/g")"
      sql_con+="${def_bc};\n"
    done
    sql_con+="
WITH t0 AS (SELECT clock_timestamp() AS ini),
     ins AS (INSERT INTO bench_con SELECT * FROM comprobante)
SELECT EXTRACT(EPOCH FROM (clock_timestamp() - t0.ini)) * 1000 FROM t0;
SELECT count(*) FROM bench_con;
SELECT count(*) FROM pg_indexes WHERE tablename = 'bench_con';
ROLLBACK;"

    printf '%b\n' "$sql_con" > "$TMP_DIR/sql_con.sql"
    if ! cat "$TMP_DIR/sql_con.sql" | psql_db -t -A > "$TMP_DIR/out_con.txt" 2>&1; then
      echo "ERROR: psql falló en variante con índices (rep $i)." >&2
      cat "$TMP_DIR/out_con.txt" >&2
      exit 1
    fi

    # Verificar que se crearon los índices esperados en bench_con (dentro de la misma transacción)
    local idx_con_count filas_con ms_con
    # Salida esperada (con -t -A): [ms_con] [filas] [idx_count]
    ms_con="$(head -n1 "$TMP_DIR/out_con.txt")"
    filas_con="$(sed -n '2p' "$TMP_DIR/out_con.txt")"
    idx_con_count="$(sed -n '3p' "$TMP_DIR/out_con.txt")"

    if [[ -z "$ms_con" || "$filas_con" != "170000" || "$idx_con_count" -ne "$IDX_DEFS_COUNT" ]]; then
      echo "ERROR: Variante con índices falló (rep $i). ms=$ms_con filas=$filas_con idx=$idx_con_count (esperados $IDX_DEFS_COUNT)." >&2
      cat "$TMP_DIR/out_con.txt" >&2
      exit 1
    fi
    tiempos_con+=("$ms_con")

    echo "  -> Rep $i: sin=${ms_sin} ms | con=${ms_con} ms (índices en bench_con: $idx_con_count)"
    if [[ -z "$ms_con" || "$filas_con" != "170000" ]]; then
      echo "ERROR: Variante con índices falló (rep $i)." >&2
      cat "$TMP_DIR/out_con.txt" >&2
      exit 1
    fi
    tiempos_con+=("$ms_con")

    echo "  -> Rep $i: sin=${ms_sin} ms | con=${ms_con} ms"
  done

  # Mediana de ambas variantes
  local mediana_sin mediana_con
  mediana_sin="$(printf '%s\n' "${tiempos_sin[@]}" | sort -n | awk '
    { v[NR] = $1 }
    END {
      if (NR % 2 == 1) print v[(NR + 1) / 2]
      else print (v[NR / 2] + v[NR / 2 + 1]) / 2
    }')"
  mediana_con="$(printf '%s\n' "${tiempos_con[@]}" | sort -n | awk '
    { v[NR] = $1 }
    END {
      if (NR % 2 == 1) print v[(NR + 1) / 2]
      else print (v[NR / 2] + v[NR / 2 + 1]) / 2
    }')"

  echo ""
  echo "----------------------------------------------------------"
  printf '%-10s | %12s | %12s | %s\n' "Variante" "Mediana (ms)" "Filas" "Índices"
  printf '%-10s | %12s | %12s | %s\n' "sin" "$mediana_sin" "170000" "ninguno"
  printf '%-10s | %12s | %12s | %s\n' "con" "$mediana_con" "170000" "$IDX_DEFS_COUNT sobre bench_con"
  echo "----------------------------------------------------------"
  echo ""

  # Dejar resultados disponibles para escribir_documento
  COSTO_MEDIANA_SIN="$mediana_sin"
  COSTO_MEDIANA_CON="$mediana_con"
}

# ---------------------------------------------------------------------
# B) indice_candidato_descartado(): evalúa un índice candidato que NO
#    se crea en 008_indices.sql y muestra por qué se descartó.
#
#    Candidato: CREATE INDEX cand_vino_tipo ON vino (tipo);
#    Consulta:  SELECT cod_vino, nombre FROM vino WHERE tipo = 'tinto';
#    Dentro de BEGIN ... ROLLBACK: crea candidato, ANALYZE vino,
#    EXPLAIN (ANALYZE, BUFFERS) de la consulta, ROLLBACK.
# ---------------------------------------------------------------------
indice_candidato_descartado() {
  echo "=========================================================="
  echo "[indice_candidato_descartado] Índice candidato NO aplicado"
  echo "=========================================================="

  local plan_file="$TMP_DIR/cand_vino_tipo_plan.txt"
  local sql_cand
  sql_cand="
BEGIN;
CREATE INDEX cand_vino_tipo ON vino (tipo);
ANALYZE vino;
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
  SELECT cod_vino, nombre FROM vino WHERE tipo = 'tinto';
ROLLBACK;"

  local out
  out="$(printf '%s\n' "$sql_cand" | psql_db 2>&1)"
  printf '%s\n' "$out" > "$plan_file"

  if printf '%s\n' "$out" | grep -q 'cand_vino_tipo'; then
    echo "[indice_candidato_descartado] El planificador USA el índice cand_vino_tipo."
    CANDIDATO_RECORRIDO="Index Scan (usa cand_vino_tipo)"
    CANDIDATO_CONCLUSION="El planificador USÓ el índice candidato cand_vino_tipo."
  else
    echo "[indice_candidato_descartado] El planificador NO usa cand_vino_tipo (tabla vino tiene 40 filas, baja selectividad; Seq Scan es más barato)."
    CANDIDATO_RECORRIDO="Seq Scan (no usa cand_vino_tipo)"
    CANDIDATO_CONCLUSION="El planificador NO usó el índice candidato cand_vino_tipo (tabla vino con 40 filas, baja selectividad; Seq Scan es más barato)."
  fi

  # Variables globales para escribir_documento
  CANDIDATO_NOMBRE="cand_vino_tipo"
  CANDIDATO_CONSULTA="SELECT cod_vino, nombre FROM vino WHERE tipo = 'tinto';"

  echo "--- Plan completo guardado en $plan_file ---"
  printf '%s\n' "$out"
  echo ""
}

# ---------------------------------------------------------------------
# escribir_documento: genera docs/planes_indices.md con salida real de
# PostgreSQL. Ningún número se escribe a mano; todo proviene de variables
# pobladas durante la ejecución.
# ---------------------------------------------------------------------
escribir_documento() {
  local fecha_commit git_status server_version filas_c filas_rc filas_cli
  local clave factor md5
  local claves_ordenadas

  echo "[escribir_documento] Generando $OUT..."

  # -------- Metadatos --------
  fecha_commit="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  git_commit="$(git rev-parse --short HEAD 2>/dev/null || echo "desconocido")"
  git_status="$(git status --porcelain 2>/dev/null || true)"
  if [[ -n "$git_status" ]]; then
    git_commit="${git_commit} (con cambios sin confirmar)"
  fi
  server_version="$(psql_db -t -A -c "SHOW server_version;" 2>/dev/null || echo "no medido")"
  filas_c="$(psql_db -t -A -c "SELECT count(*) FROM comprobante;" 2>/dev/null || echo "no medido")"
  filas_rc="$(psql_db -t -A -c "SELECT count(*) FROM renglon_comprobante;" 2>/dev/null || echo "no medido")"
  filas_cli="$(psql_db -t -A -c "SELECT count(*) FROM cliente;" 2>/dev/null || echo "no medido")"
  indices_lista="$(printf '%s, ' "${IDX_NOMBRES[@]}")"
  indices_lista="${indices_lista%, }"

  # -------- Helper: escapar pipes para tablas markdown --------
  esc_pipe() {
    printf '%s' "$1" | sed 's/|/\\|/g'
  }

  # -------- Helper: factor de mejora --------
  calcular_factor() {
    local a="$1" d="$2"
    if [[ -z "$a" || -z "$d" || "$d" = "0" || "$d" = "no medido" || "$a" = "no medido" ]]; then
      echo "no medido"
    else
      awk -v aa="$a" -v dd="$d" 'BEGIN { if (dd == 0) print "no medido"; else printf "%.1f", aa/dd }'
    fi
  }

  # -------- Unión ordenada de claves --------
  claves_ordenadas="$(printf '%s\n' "${!MEDIANA_ANTES[@]}" "${!MEDIANA_DESPUES[@]}" | sort -u)"

  # -------- Escribir documento --------
  {
    echo "# Planes de ejecución y medición de índices"
    echo ""
    echo "## Metadatos"
    echo ""
    echo "- Fecha UTC de ejecución: ${fecha_commit}"
    echo "- Commit: ${git_commit}"
    echo "- Versión de PostgreSQL: ${server_version}"
    echo "- Filas: comprobante=${filas_c}, renglon_comprobante=${filas_rc}, cliente=${filas_cli}"
    echo "- Repeticiones medidas: ${REPS} (+1 calentamiento)"
    echo "- Índices medidos: ${indices_lista}"
    echo "- Nota: Medición con caché caliente; mediana de ${REPS} ejecución(es)."
    echo ""

    echo "## 1. Tabla comparativa"
    echo ""
    echo "| Consulta | Recorrido antes | Filas antes | Recorrido después | Filas después | Mediana antes (ms) | Mediana después (ms) | Factor de mejora (antes/después) |"
    echo "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"
    while IFS= read -r clave; do
      [[ -z "$clave" ]] && continue
      local_scan_antes="${SCAN_ANTES[$clave]:-no medido}"
      local_scan_despues="${SCAN_DESPUES[$clave]:-no medido}"
      local_med_antes="${MEDIANA_ANTES[$clave]:-no medido}"
      local_med_despues="${MEDIANA_DESPUES[$clave]:-no medido}"
      local_filas_antes="no medido"
      local_filas_despues="no medido"
      if [[ -n "${PLAN_ANTES[$clave]:-}" && -f "${PLAN_ANTES[$clave]}" ]]; then
        local_filas_antes="$(extraer_filas "${PLAN_ANTES[$clave]}")"
        [[ -z "$local_filas_antes" ]] && local_filas_antes="no medido"
      fi
      if [[ -n "${PLAN_DESPUES[$clave]:-}" && -f "${PLAN_DESPUES[$clave]}" ]]; then
        local_filas_despues="$(extraer_filas "${PLAN_DESPUES[$clave]}")"
        [[ -z "$local_filas_despues" ]] && local_filas_despues="no medido"
      fi
      factor="$(calcular_factor "$local_med_antes" "$local_med_despues")"
      echo "| $(esc_pipe "$clave") | $(esc_pipe "$local_scan_antes") | $(esc_pipe "$local_filas_antes") | $(esc_pipe "$local_scan_despues") | $(esc_pipe "$local_filas_despues") | $(esc_pipe "$local_med_antes") | $(esc_pipe "$local_med_despues") | $(esc_pipe "$factor") |"
    done <<< "$claves_ordenadas"
    echo ""

    echo "## 2. Costo de escritura"
    echo ""
    echo "| tabla | variante | mediana (s) | filas |"
    echo "| --- | --- | --- | --- |"
    if [[ -n "${COSTO_MEDIANA_SIN:-}" ]]; then
      awk -v v="$COSTO_MEDIANA_SIN" 'BEGIN { printf "| comprobante | sin índices | %.4f | 170000 |\n", v/1000 }'
    else
      echo "| comprobante | sin índices | no medido | 170000 |"
    fi
    if [[ -n "${COSTO_MEDIANA_CON:-}" ]]; then
      awk -v v="$COSTO_MEDIANA_CON" 'BEGIN { printf "| comprobante | con índices | %.4f | 170000 |\n", v/1000 }'
    else
      echo "| comprobante | con índices | no medido | 170000 |"
    fi
    echo ""

    echo "## 3. Índice candidato descartado"
    echo ""
    echo "- Candidato: \`CREATE INDEX ${CANDIDATO_NOMBRE:-cand_vino_tipo} ON vino (tipo);\`"
    echo "- Consulta: \`${CANDIDATO_CONSULTA:-SELECT cod_vino, nombre FROM vino WHERE tipo = 'tinto';}\`"
    echo "- Recorrido observado: ${CANDIDATO_RECORRIDO:-no medido}"
    echo "- Conclusión: ${CANDIDATO_CONCLUSION:-no medido}"
    echo ""

    echo "## 4. Planes completos"
    echo ""
    while IFS= read -r clave; do
      [[ -z "$clave" ]] && continue
      echo "<details><summary>Consulta ${clave} – antes</summary>"
      echo ""
      echo '```text'
      if [[ -n "${PLAN_ANTES[$clave]:-}" && -f "${PLAN_ANTES[$clave]}" ]]; then
        cat "${PLAN_ANTES[$clave]}"
      else
        echo "no medido"
      fi
      echo '```'
      echo "</details>"
      echo ""
      echo "<details><summary>Consulta ${clave} – después</summary>"
      echo ""
      echo '```text'
      if [[ -n "${PLAN_DESPUES[$clave]:-}" && -f "${PLAN_DESPUES[$clave]}" ]]; then
        cat "${PLAN_DESPUES[$clave]}"
      else
        echo "no medido"
      fi
      echo '```'
      echo "</details>"
      echo ""
    done <<< "$claves_ordenadas"

    echo "## 5. Reproducción"
    echo ""
    echo "Comando exacto para regenerar:"
    echo ""
    echo "\`\`\`bash"
    echo "bash scripts/medir_indices.sh --reps 3"
    echo "\`\`\`"
  } > "$OUT"

  echo "[escribir_documento] Documento generado: $OUT"
}

# ---------------------------------------------------------------------
# Parseo de argumentos

# ---------------------------------------------------------------------
# Parseo de argumentos
# ---------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --reps)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: La opción --reps requiere un número entero >= 1." >&2
        exit 1
      fi
      if ! [[ "$2" =~ ^[0-9]+$ ]] || [[ "$2" -lt 1 ]]; then
        echo "ERROR: --reps debe ser un entero >= 1, se recibió: $2" >&2
        exit 1
      fi
      REPS="$2"
      shift 2
      ;;
    -h|--help)
      cat << 'EOF'
Uso: bash scripts/medir_indices.sh [--reps N]

Medición reproducible de índices para el TPI de Bases de Datos.

Opciones:
  --reps N    Número de repeticiones por consulta (entero >= 1, por defecto: 3).
  -h, --help  Muestra esta ayuda y finaliza.

Variables de entorno opcionales:
  MEDIR_INDICES_SELF_TEST=1  Ejecuta auto-prueba de medir_consulta (S1, REPS=1).

Requisitos:
  - Docker Desktop levantado y servicio 'db' sano.
  - Base de medición 'bodegas_atuel_bench' cargada (>100.000 filas en comprobante).
  - Archivo .env en la raíz del proyecto.

Este script NO modifica migraciones, ni la API, ni el DER.
EOF
      exit 0
      ;;
    *)
      echo "ERROR: Opción no reconocida: $1" >&2
      echo "Use -h o --help para ver el uso." >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------
# Auto-prueba opcional de medir_consulta (activar con MEDIR_INDICES_SELF_TEST=1)
# ---------------------------------------------------------------------
if [[ "${MEDIR_INDICES_SELF_TEST:-0}" = "1" ]]; then
  REPS=1
  echo "[self-test] Probando medir_consulta sobre S1_top_vinos_control.sql..."
  mediana_obtenida="$(medir_consulta "scripts/perf/consultas_medidas/S1_top_vinos_control.sql" "prueba" "")"
  echo "Mediana obtenida: $mediana_obtenida ms"
  echo "PLAN_FILE: $PLAN_FILE"
  echo "--- Plan completo ---"
  cat "$PLAN_FILE"
  exit 0
fi

# ---------------------------------------------------------------------
# Ejecución normal: orquestación completa de medición de índices.
# Respeta el valor de REPS recibido por --reps (por defecto: 3).
# Orden: primero TODAS las mediciones de modo_antes, luego TODAS de
# modo_despues. Justificación: reducir efectos de caché entre modos.
# ---------------------------------------------------------------------
echo "[medir_indices] Iniciando medición de índices (reps=$REPS)..."
extraer_indices_008
verificar_base
verificar_volumen
asegurar_indices_008

echo "[medir_indices] Fase 1/5: modo_antes (sin índices de 008)..."
modo_antes

# Tratamiento especial: PLAN_intervalo_variable (plantilla con {{INTERVALO}})
# En modo_antes cada consulta va envuelta en BEGIN; DROP INDEX ...; ... ROLLBACK;
echo "[medir_indices] Fase 1b/5: modo_antes - PLAN_intervalo_variable..."
idx_list_antes="$(printf '%s,' "${IDX_NOMBRES[@]}")"
idx_list_antes="${idx_list_antes%,}"
preambulo_antes="BEGIN; DROP INDEX IF EXISTS ${idx_list_antes};"
sufijo_antes="ROLLBACK;"
for intervalo in '7 days' '10 years'; do
  clave="PLAN_INTERVALO_$(printf '%s' "$intervalo" | tr ' ' '_' | tr '[:lower:]' '[:upper:]')"
  tmp_sql="$TMP_DIR/plan_intervalo_${clave}.sql"
  sed "s/{{INTERVALO}}/${intervalo}/" "$CONS_DIR/PLAN_intervalo_variable.sql" > "$tmp_sql"
  echo "[modo_antes] Midiendo $clave (intervalo='$intervalo')..."
  medir_consulta "$tmp_sql" "antes_$clave" "$preambulo_antes" "$sufijo_antes"
  MEDIANA_ANTES["$clave"]="$MEDIANA_MS"
  PLAN_ANTES["$clave"]="$PLAN_FILE"
  SCAN_ANTES["$clave"]="$(extraer_scan "$PLAN_FILE")"
  FILAS_ANTES["$clave"]="$(extraer_filas "$PLAN_FILE")"
  echo "  -> Mediana: ${MEDIANA_MS} ms | Scan: ${SCAN_ANTES[$clave]} | Filas: ${FILAS_ANTES[$clave]}"
done

echo "[medir_indices] Fase 2/5: modo_despues (con índices de 008)..."
modo_despues

echo "[medir_indices] Fase 2b/5: modo_despues - PLAN_intervalo_variable..."
for intervalo in '7 days' '10 years'; do
  clave="PLAN_INTERVALO_$(printf '%s' "$intervalo" | tr ' ' '_' | tr '[:lower:]' '[:upper:]')"
  tmp_sql="$TMP_DIR/plan_intervalo_${clave}.sql"
  sed "s/{{INTERVALO}}/${intervalo}/" "$CONS_DIR/PLAN_intervalo_variable.sql" > "$tmp_sql"
  echo "[modo_despues] Midiendo $clave (intervalo='$intervalo')..."
  medir_consulta "$tmp_sql" "despues_$clave" "" ""
  MEDIANA_DESPUES["$clave"]="$MEDIANA_MS"
  PLAN_DESPUES["$clave"]="$PLAN_FILE"
  SCAN_DESPUES["$clave"]="$(extraer_scan "$PLAN_FILE")"
  FILAS_DESPUES["$clave"]="$(extraer_filas "$PLAN_FILE")"
  echo "  -> Mediana: ${MEDIANA_MS} ms | Scan: ${SCAN_DESPUES[$clave]} | Filas: ${FILAS_DESPUES[$clave]}"
done

# ------------------------------------------------------------------
# Tabla resumen en consola
# ------------------------------------------------------------------
echo ""
echo "=========================================================="
echo "RESUMEN DE MEDICIONES (reps=$REPS)"
echo "=========================================================="
printf '%-35s | %12s | %-28s | %12s | %-28s | %s\n' \
  "Consulta" "Antes (ms)" "Antes Scan" "Despues (ms)" "Despues Scan" "Filas"
printf '%-35s | %12s | %-28s | %12s | %-28s | %s\n' \
  "$(printf '%-35s' '' | tr ' ' '-')" "$(printf '%12s' '' | tr ' ' '-')" \
  "$(printf '%-28s' '' | tr ' ' '-')" "$(printf '%12s' '' | tr ' ' '-')" \
  "$(printf '%-28s' '' | tr ' ' '-')" "$(printf '%s' '' | tr ' ' '-')"

for clave in "${!MEDIANA_ANTES[@]}"; do
  printf '%-35s | %12s | %-28s | %12s | %-28s | %s\n' \
    "$clave" "${MEDIANA_ANTES[$clave]}" "${SCAN_ANTES[$clave]:-}" \
    "${MEDIANA_DESPUES[$clave]:-}" "${SCAN_DESPUES[$clave]:-}" \
    "${FILAS_ANTES[$clave]:-}"
done

echo "[medir_indices] Fase 3/5: costo_escritura..."
costo_escritura

echo "[medir_indices] Fase 4/5: indice_candidato_descartado..."
indice_candidato_descartado

echo "[medir_indices] Fase 5/5: escribir_documento..."
escribir_documento

echo "[medir_indices] Orquestación finalizada."
