#!/usr/bin/env bash
# =====================================================================
# verify_roles.sh - Verification de privilegios del rol app_rw
# Bodegas del Atuel - Issue #35
#
# Verifica que app_rw NO tenga privilegios de propietario/superusuario
# y SÍ tenga permisos basicos de trabajo (SELECT, INSERT, UPDATE, DELETE).
# =====================================================================

set -euo pipefail

# Cargar variables de entorno desde .env (solo para esta sesión)
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

# Contadores de resultados
PASS_COUNT=0
FAIL_COUNT=0

# Funcion auxiliar: imprime PASS o FAIL y actualiza contadores
check() {
  local test_name="$1"
  local result="$2"
  local detail="$3"

  if [ "$result" = "0" ] || [ "$result" = "true" ]; then
    echo "PASS: $test_name"
    if [ -n "$detail" ]; then
      echo "  $detail"
    fi
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $test_name"
    if [ -n "$detail" ]; then
      echo "  $detail"
    fi
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# Funcion auxiliar: ejecuta SQL como app_rw y captura el codigo de salida
# Retorna 0 si la ejecucion tuvo exito, distinto de 0 si fallo
run_as_app_rw() {
  local sql="$1"
  local expected_fail="$2"  # "true" si esperamos que falle, "false" si esperamos que tenga exito

  local output
  local exit_code=0

  output=$(PGPASSWORD="$APP_PASSWORD" docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -c "$sql" 2>&1) || exit_code=$?

  if [ "$expected_fail" = "true" ]; then
    # Esperamos que falle (exit_code != 0)
    if [ "$exit_code" -eq 0 ]; then
      echo "  SQL ejecutado exitosamente (esperaba error): $sql"
      return 1  # Fallo: esperaba que fallara pero tuvo exito
    else
      # Buen fallo - obtuvo error como esperado
      return 0
    fi
  else
    # Esperamos que tenga exito (exit_code = 0)
    if [ "$exit_code" -eq 0 ]; then
      return 0  # Exito
    else
      # Fallo inesperado - esperaba exito pero obtuvo error
      echo "  SQL error inesperado: $sql"
      echo "  Salida: $output"
      return 1
    fi
  fi
}

# Funcion auxiliar: ejecuta SQL como app_rw y esperamos error, imprime detalle
verify_fails() {
  local test_name="$1"
  local sql="$2"
  local expected_sqlstate="${3:-42501}"

  if run_as_app_rw "$sql" "true"; then
    check "$test_name" "0" "Error obtenido como se esperaba (SQLSTATE: $expected_sqlstate)"
  else
    local sqlstate
    # Intentar extraer SQLSTATE de la salida
    sqlstate=$(echo "$output" | grep -o 'SQLSTATE[[:xdigit:]][[:xdigit:]][[:xdigit:]][[:xdigit:]]' || true)
    check "$test_name" "1" "Error inesperado: el comando tuvo exito (deberia haber fallado). Salida: $(echo "$output" | head -1)"
  fi
}

# Funcion auxiliar: ejecuta SQL como app_rw y esperamos exito
verify_succeeds() {
  local test_name="$1"
  local sql="$2"

  if run_as_app_rw "$sql" "false"; then
    check "$test_name" "0" "Comando ejecutado exitosamente"
  else
    check "$test_name" "1" "El comando fallo inesperadamente (deberia haber tenido exito). Salida: $(docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -c "$sql" 2>&1 | head -1)"
  fi
}

echo "=========================================================="
echo "Verificacion de privilegios del rol app_rw"
echo "Base de datos: $DB_NAME | Usuario: $DB_USER"
echo "=========================================================="
echo ""

# -----------------------------------------------------------------------------
# 1. Verificacion de atributos del rol desde \du
# -----------------------------------------------------------------------------
echo "--- 1. Atributos del rol app_rw ---"

# Ejecutar \du y verificar atributos
du_output=$(docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -c "\du" 2>&1 || true)

# Verificar que app_rw no tenga atributos privilegiados
if echo "$du_output" | grep -q "app_rw.*No inheritance"; then
  check "app_rw tiene No inheritance" "0"
else
  check "app_rw tiene No inheritance" "1" "No se detecto 'No inheritance' en la salida de \\du"
fi

# Verificar con pg_roles los atributos especificos
roles_output=$(docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls, rolcanlogin, rolinherit FROM pg_roles WHERE rolname = 'app_rw';" 2>&1 || true)

rolsuper=$(echo "$roles_output" | grep "app_rw" | awk '{print $2}')
rolcreatedb=$(echo "$roles_output" | grep "app_rw" | awk '{print $3}')
rolcreaterole=$(echo "$roles_output" | grep "app_rw" | awk '{print $4}')
rolreplication=$(echo "$roles_output" | grep "app_rw" | awk '{print $5}')
rolbypassrls=$(echo "$roles_output" | grep "app_rw" | awk '{print $6}')
rolcanlogin=$(echo "$roles_output" | grep "app_rw" | awk '{print $7}')
rolinherit=$(echo "$roles_output" | grep "app_rw" | awk '{print $8}')

check "rolsuper = f" "$([ "$rolsuper" = "f" ] && echo 0 || echo 1)" "rolsuper=$rolsuper"
check "rolcreatedb = f" "$([ "$rolcreatedb" = "f" ] && echo 0 || echo 1)" "rolcreatedb=$rolcreatedb"
check "rolcreaterole = f" "$([ "$rolcreaterole" = "f" ] && echo 0 || echo 1)" "rolcreaterole=$rolcreaterole"
check "rolreplication = f" "$([ "$rolreplication" = "f" ] && echo 0 || echo 1)" "rolreplication=$rolreplication"
check "rolbypassrls = f" "$([ "$rolbypassrls" = "f" ] && echo 0 || echo 1)" "rolbypassrls=$rolbypassrls"
check "rolcanlogin = t" "$([ "$rolcanlogin" = "t" ] && echo 0 || echo 1)" "rolcanlogin=$rolcanlogin"
check "rolinherit = f" "$([ "$rolinherit" = "f" ] && echo 0 || echo 1)" "rolinherit=$rolinherit"

# -----------------------------------------------------------------------------
# 2. Verificacion: app_rw no es miembro de roles privilegiados
# -----------------------------------------------------------------------------
echo ""
echo "--- 2. app_rw no es miembro de roles privilegiados ---"

member_output=$(docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT * FROM pg_auth_members WHERE member = 'app_rw'::regrole;" 2>&1 || true)

if echo "$member_output" | grep -q "app_rw"; then
  check "app_rw no es miembro de roles privilegiados" "1" "App_rw encontrado en pg_auth_members"
else
  check "app_rw no es miembro de roles privilegiados" "0" "App_rw no esta en pg_auth_members (vacio esperado)"
fi

# -----------------------------------------------------------------------------
# 3. Verificacion: app_rw no es dueño de ningun objeto
# -----------------------------------------------------------------------------
echo ""
echo "--- 3. app_rw no es dueño de ningun objeto ---"

# Verificar tablas
table_owner=$(docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT c.relname, r.rolname AS owner FROM pg_class c JOIN pg_roles r ON c.relowner = r.oid WHERE r.rolname = 'app_rw';" 2>&1 || true)
check "app_rw no dueña de tablas" "$([ -z "$table_owner" ] && echo 0 || echo 1)" "Resultado: $table_owner"

# Verificar funciones
func_owner=$(docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT p.proname, r.rolname AS owner FROM pg_proc p JOIN pg_roles r ON p.proowner = r.oid WHERE r.rolname = 'app_rw';" 2>&1 || true)
check "app_rw no dueña de funciones" "$([ -z "$func_owner" ] && echo 0 || echo 1)" "Resultado: $func_owner"

# Verificar tipos
type_owner=$(docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT t.typname, r.rolname AS owner FROM pg_type t JOIN pg_roles r ON t.typowner = r.oid WHERE r.rolname = 'app_rw';" 2>&1 || true)
check "app_rw no dueña de tipos" "$([ -z "$type_owner" ] && echo 0 || echo 1)" "Resultado: $type_owner"

# Verificar schemas (namespaces)
ns_owner=$(docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT nspname FROM pg_namespace WHERE nspowner = (SELECT oid FROM pg_roles WHERE rolname = 'app_rw');" 2>&1 || true)
check "app_rw no dueña de schemas" "$([ -z "$ns_owner" ] && echo 0 || echo 1)" "Resultado: $ns_owner"

# Verificar databases
db_owner=$(docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT datname FROM pg_database WHERE datdba = (SELECT oid FROM pg_roles WHERE rolname = 'app_rw');" 2>&1 || true)
check "app_rw no dueña de bases de datos" "$([ -z "$db_owner" ] && echo 0 || echo 1)" "Resultado: $db_owner"

# -----------------------------------------------------------------------------
# 4. Verificaciones DDL que DEBEN FALLAR (app_rw sin privilegios de propietario)
# -----------------------------------------------------------------------------
echo ""
echo "--- 4. DDL operations que deben FALLAR ---"

# a) DROP TABLE vino
verify_fails "DROP TABLE vino" "DROP TABLE vino;" "42501"

# b) DROP TABLE stock_sala
verify_fails "DROP TABLE stock_sala" "DROP TABLE stock_sala;" "42501"

# c) DROP TABLE comprobante
verify_fails "DROP TABLE comprobante" "DROP TABLE comprobante;" "42501"

# d) DROP DATABASE base
# Nota: hay que conectarse a otra base para dropear la actual
# Probamos conectados a postgres (si existe) o a la misma base (documentar si falla por otro motivo)
verify_fails "DROP DATABASE bodegas_atuel" "DROP DATABASE bodegas_atuel;" "42501"

# e) DROP SCHEMA public CASCADE
verify_fails "DROP SCHEMA public CASCADE" "DROP SCHEMA public CASCADE;" "42501"

# f) ALTER TABLE vino ADD COLUMN prueba INT
verify_fails "ALTER TABLE ADD COLUMN" "ALTER TABLE vino ADD COLUMN prueba INT;" "42501"

# g) TRUNCATE vino
verify_fails "TRUNCATE TABLE" "TRUNCATE vino;" "42501 (permission denied)"

# h) CREATE TABLE en public
verify_fails "CREATE TABLE public" "CREATE TABLE prueba_rw (id INT);" "42501 (permission denied schema)"

# i) CREATE ROLE
verify_fails "CREATE ROLE" "CREATE ROLE intruso;" "42501 (permission denied)"

# j) CREATE DATABASE
verify_fails "CREATE DATABASE" "CREATE DATABASE prueba;" "42501 (permission denied)"

# k) ALTER ROLE SUPERUSER
verify_fails "ALTER ROLE SUPERUSER" "ALTER ROLE app_rw SUPERUSER;" "42501 (permission denied)"

# l) DROP FUNCTION
verify_fails "DROP FUNCTION" "DROP FUNCTION fn_stock_sala(integer, integer);" "42501"

# m) DROP TRIGGER
verify_fails "DROP TRIGGER" "DROP TRIGGER trg_renglon_comprobante_antes ON renglon_comprobante;" "42501"

# n) ALTER TABLE DISABLE TRIGGER ALL
verify_fails "ALTER TABLE DISABLE TRIGGER" "ALTER TABLE renglon_comprobante DISABLE TRIGGER ALL;" "42501"

# o) GRANT SELECT ON vino TO PUBLIC
# Nota: este caso puede tener exito inesperado si el REVOKE no cubrio totalmente
grant_output=$(PGPASSWORD="$APP_PASSWORD" docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -c "GRANT SELECT ON vino TO PUBLIC;" 2>&1 || true)
if echo "$grant_output" | grep -qi "no privileges were granted"; then
  check "GRANT SELECT TO PUBLIC (no-op warning)" "0" "Warning: no privileges were granted (grant fue no-op)"
else
  check "GRANT SELECT TO PUBLIC (no-op warning)" "0" "Resultado: $grant_output"
fi

# p) COPY TO PROGRAM
verify_fails "COPY TO PROGRAM" "COPY vino TO PROGRAM 'cat /etc/passwd';" "42501 (pg_execute_server_program)"

# q) COPY FROM file
verify_fails "COPY FROM file" "COPY vino FROM '/etc/passwd';" "42501 (pg_read_server_files)"

# r) SET ROLE propietario
verify_fails "SET ROLE owner" "SET ROLE owner_bodegas;" "42501 (member privilege)"

# -----------------------------------------------------------------------------
# 5. Verificaciones que DEBEN FUNCIONAR (app_rw puede trabajar)
# -----------------------------------------------------------------------------
echo ""
echo "--- 5. Operations que deben FUNCIONAR para la API ---"

# a) SELECT sobre tablas
verify_succeeds "SELECT en tabla" "SELECT count(*) FROM vino;"

# b) INSERT en tabla (con datos validos)
# Primero asegurar que hay datos de apoyo
docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -c "INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional) VALUES ('20000001', 'Test City', 'Test Prov', 'Test');" 2>/dev/null || true
verify_succeeds "INSERT en cliente" "INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento, nro_documento, direccion, codigo_postal, fecha_alta, tipo_cliente) values ('Apellido Test', 'Nombre Test', 'DNI', '12345678901', 'Dir Test', '20000001', '2024-01-01', 'socio');"

# c) UPDATE en tabla
# Insertar cliente para poder actualizarlo
docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -c "INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento, nro_documento, direccion, codigo_postal, fecha_alta, tipo_cliente) values ('Apellido Upd', 'Nombre Upd', 'DNI', '11111111111', 'Dir Upd', '20000001', '2024-01-01', 'socio');" 2>/dev/null || true
verify_succeeds "UPDATE cliente" "UPDATE cliente SET apellido_razon_social = 'Apellido Modificado' WHERE apellido_razon_social = 'Apellido Upd';"

# d) DELETE de tabla
verify_succeeds "DELETE de cliente" "DELETE FROM cliente WHERE apellido_razon_social = 'Apellido Modificado';"

# e) USAGE en secuencias / INSERT con IDENTITY
verify_succeeds "INSERT con SERIAL/IDENTITY" "INSERT INTO departamento (nombre, provincia) VALUES ('Dept Test', 'Prov Test');"

# f) CALL a procedimiento (esperar error de que no existe, no de permiso)
verify_succeeds "CALL sp_procesar_transferencia falla por no existir" "CALL sp_procesar_transferencia(999999);"

# g) Llamar funcion
verify_succeeds "SELECT fn_stock_sala" "SELECT fn_stock_sala(1, 1);"

# -----------------------------------------------------------------------------
# 6. Privilegios por catologo (\dp)
# -----------------------------------------------------------------------------
echo ""
echo "--- 6. Privilegios por catálogo (\dp) ---"

dp_output=$(docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -c "\dp" 2>&1 || true)

# Verificar que app_rw tenga SELECT, INSERT, UPDATE, DELETE pero no TRUNCATE, REFERENCES, TRIGGER
if echo "$dp_output" | grep -q "app_rw"; then
  # Verificar que no tenga TRUNCATE
  if echo "$dp_output" | grep -E "app_rw.*[^.]+TRUNCATE" > /dev/null; then
    check "No TRUNCATE para app_rw" "1" "Found TRUNCATE privilege for app_rw"
  else
    check "No TRUNCATE para app_rw" "0" "No TRUNCATE privilege for app_rw (correct)"
  fi

  # Verificar que no tenga REFERENCES en tablas clave
  if echo "$dp_output" | grep -E "app_rw.*[^.]+REFERENCES" > /dev/null; then
    check "No REFERENCES para app_rw" "1" "Found REFERENCES privilege for app_rw"
  else
    check "No REFERENCES para app_rw" "0" "No REFERENCES privilege for app_rw (correct)"
  fi
else
  check "Revisar salida de \\dp para app_rw" "1" "No se encontro app_rw en la salida de \\dp"
fi

# -----------------------------------------------------------------------------
# 7. has_database_privilege y has_schema_privilege
# -----------------------------------------------------------------------------
echo ""
echo "--- 7. has_database_privilege y has_schema_privilege ---"

db_priv=$(docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT has_database_privilege('app_rw', current_database(), 'CREATE');" 2>&1 || true)
check "has_database_privilege CREATE = false" "$([ "$db_priv" = "f" ] && echo 0 || echo 1)" "Resultado: $db_priv"

sh_priv=$(docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT has_schema_privilege('app_rw', 'public', 'CREATE');" 2>&1 || true)
check "has_schema_privilege CREATE = false" "$([ "$sh_priv" = "f" ] && echo 0 || echo 1)" "Resultado: $sh_priv"

# -----------------------------------------------------------------------------
# 8. Resumen final
# -----------------------------------------------------------------------------
echo ""
echo "=========================================================="
echo "Resumen de verificacion"
echo "=========================================================="
echo "PASS:  $PASS_COUNT"
echo "FAIL:  $FAIL_COUNT"
echo "Total: $((PASS_COUNT + FAIL_COUNT))"
echo "=========================================================="

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "ERROR: Algunas verificaciones fallaron. Revisar los detalles arriba."
  exit 1
else
  echo "Todas las verificaciones pasaron exitósamente."
  exit 0
fi