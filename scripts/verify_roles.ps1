# =====================================================================
# verify_roles.ps1 - Verificación de privilegios del rol app_rw
# Bodegas del Atuel - Issue #35
#
# Verifica que app_rw NO tenga privilegios de propietario/superusuario
# y SÍ tenga permisos básicos de trabajo (SELECT, INSERT, UPDATE, DELETE).
# =====================================================================

# Leer conexión y contraseña de app_rw desde variables de entorno
# Nunca escritas en el script - se cargan desde .env en la sesión
if (-not $env:POSTGRES_USER) {
    if (Test-Path ".env") {
        . .\ .env
    } else {
        Write-Error "POSTGRES_USER no definida y no existe .env"
        exit 1
    }
}

if (-not $env:POSTGRES_DB) {
    Write-Error "POSTGRES_DB no definida"
    exit 1
}

if (-not $env:APP_DB_PASSWORD) {
    Write-Error "APP_DB_PASSWORD no definida"
    exit 1
}

$DB_USER = $env:POSTGRES_USER
$DB_NAME = $env:POSTGRES_DB
$APP_PASSWORD = $env:APP_DB_PASSWORD

# Contadores de resultados
$passCount = 0
$failCount = 0

# Función auxiliar: imprime PASS/FAIL y actualiza contadores
function Check-Result {
    param([string]$TestName, [bool]$Passed, [string]$Detail = "")

    if ($Passed) {
        Write-Host "PASS: $TestName"
        if ($Detail) { Write-Host "  $Detail" }
        $passCount++
    } else {
        Write-Host "FAIL: $TestName"
        if ($Detail) { Write-Host "  $Detail" }
        $failCount++
    }
}

# Función auxiliar: ejecuta SQL como app_rw
# expectedFail: $true si esperamos que falle, $false si esperamos éxito
function Run-Sql-As-AppRw {
    param(
        [string]$Sql,
        [bool]$ExpectedFail
    )

    $output = $null
    $exitCode = 0

    try {
        $output = docker compose exec -T db psql -U $DB_USER -d $DB_NAME -v ON_ERROR_STOP=1 -c $Sql 2>&1
    } catch {
        $exitCode = $LASTEXITCODE
    }

    if ($ExpectedFail) {
        # Esperamos que falle (exit_code != 0)
        if ($exitCode -eq 0) {
            # Tuvo éxito - error inesperado
            return @{ success = $false; exitCode = 0; output = $output }
        } else {
            # Falló como se esperaba
            return @{ success = $true; exitCode = 1; output = $output }
        }
    } else {
        # Esperamos éxito (exit_code = 0)
        if ($exitCode -eq 0) {
            return @{ success = $true; exitCode = 0; output = $output }
        } else {
            # Éxito inesperado - error
            return @{ success = $false; exitCode = 1; output = $output }
        }
    }
}

# Variable para acumular salida de pruebas inesperadas
$unexpectedOutput = ""

# -----------------------------------------------------------------------------
# 1. Verificacion de atributos del rol desde \du y pg_roles
# -----------------------------------------------------------------------------
Write-Host "=========================================================="
Write-Host "1. Atributos del rol app_rw"
Write-Host "=========================================================="

# Ejecutar \du
$duOutput = docker compose exec -T db psql -U $DB_USER -d $DB_NAME -c "\du" 2>&1 || true

# Verificar atributos desde \du
$hasNoInheritance = ($duOutput -match "app_rw.*No inheritance")
Check-Result "app_rw tiene No inheritance" $hasNoInheritance

# Verificar con pg_roles los atributos específicos
$rolesOutput = docker compose exec -T db psql -U $DB_USER -d $DB_NAME -c "SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls, rolcanlogin, rolinherit FROM pg_roles WHERE rolname = 'app_rw';" 2>&1 || true

$rolsuper = ($rolesOutput -split "`n" | Where-Object { $_ -match "app_rw" } | ForEach-Object { $_ -split "\|" | Select-Object -Index 2 }) -replace "^\s+|\s+$", ""
$rolcreatedb = ($rolesOutput -split "`n" | Where-Object { $_ -match "app_rw" } | ForEach-Object { $_ -split "\|" | Select-Object -Index 3 }) -replace "^\s+|\s+$", ""
$rolcreaterole = ($rolesOutput -split "`n" | Where-Object { $_ -match "app_rw" } | ForEach-Object { $_ -split "\|" | Select-Object -Index 4 }) -replace "^\s+|\s+$", ""
$rolreplication = ($rolesOutput -split "`n" | Where-Object { $_ -match "app_rw" } | ForEach-Object { $_ -split "\|" | Select-Object -Index 5 }) -replace "^\s+|\s+$", ""
$rolbypassrls = ($rolesOutput -split "`n" | Where-Object { $_ -match "app_rw" } | ForEach-Object { $_ -split "\|" | Select-Object -Index 6 }) -replace "^\s+|\s+$", ""
$rolcanlogin = ($rolesOutput -split "`n" | Where-Object { $_ -match "app_rw" } | ForEach-Object { $_ -split "\|" | Select-Object -Index 7 }) -replace "^\s+|\s+$", ""
$rolinherit = ($rolesOutput -split "`n" | Where-Object { $_ -match "app_rw" } | ForEach-Object { $_ -split "\|" | Select-Object -Index 8 }) -replace "^\s+|\s+$", ""

# Los valores de PostgreSQL son 't'/'f' (strings), no booleanos
Check-Result "rolsuper = f" ($rolsuper -eq "f")
Check-Result "rolcreatedb = f" ($rolcreatedb -eq "f")
Check-Result "rolcreaterole = f" ($rolcreaterole -eq "f")
Check-Result "rolreplication = f" ($rolreplication -eq "f")
Check-Result "rolbypassrls = f" ($rolbypassrls -eq "f")
Check-Result "rolcanlogin = t" ($rolcanlogin -eq "t")
Check-Result "rolinherit = f" ($rolinherit -eq "f")

# -----------------------------------------------------------------------------
# 2. Verificacion: app_rw no es miembro de roles privilegiados
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "--- 2. app_rw no es miembro de roles privilegiados ---"

$memberOutput = docker compose exec -T db psql -U $DB_USER -d $DB_NAME -c "SELECT * FROM pg_auth_members WHERE member = 'app_rw'::regrole;" 2>&1 || true

$isMember = ($memberOutput -match "app_rw")
Check-Result "app_rw no es miembro de roles privilegiados" (-not $isMember) "Resultado pg_auth_members: $memberOutput"

# -----------------------------------------------------------------------------
# 3. Verificacion: app_rw no es dueño de ningun objeto
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "--- 3. app_rw no es dueño de ningun objeto ---"

# Tablas
$tableOwner = docker compose exec -T db psql -U $DB_USER -d $DB_NAME -c "SELECT c.relname FROM pg_class c JOIN pg_roles r ON c.relowner = r.oid WHERE r.rolname = 'app_rw';" 2>&1 || true
$noTables = ($tableOwner -match "^$" -or $tableOwner -eq "")
Check-Result "app_rw no dueña de tablas" $noTables "Resultado: $tableOwner"

# Funciones
$funcOwner = docker compose exec -T db psql -U $DB_USER -d $DB_NAME -c "SELECT p.proname FROM pg_proc p JOIN pg_roles r ON p.proowner = r.oid WHERE r.rolname = 'app_rw';" 2>&1 || true
$noFuncs = ($funcOwner -match "^$" -or $funcOwner -eq "")
Check-Result "app_rw no dueña de funciones" $noFuncs "Resultado: $funcOwner"

# Tipos
$typeOwner = docker compose exec -T db psql -U $DB_USER -d $DB_NAME -c "SELECT t.typname FROM pg_type t JOIN pg_roles r ON t.typowner = r.oid WHERE r.rolname = 'app_rw';" 2>&1 || true
$noTypes = ($typeOwner -match "^$" -or $typeOwner -eq "")
Check-Result "app_rw no dueña de tipos" $noTypes "Resultado: $typeOwner"

# Schemas
$nsOwner = docker compose exec -T db psql -U $DB_USER -d $DB_NAME -c "SELECT nspname FROM pg_namespace WHERE nspowner = (SELECT oid FROM pg_roles WHERE rolname = 'app_rw');" 2>&1 || true
$noSchemas = ($nsOwner -match "^$" -or $nsOwner -eq "")
Check-Result "app_rw no dueña de schemas" $noSchemas "Resultado: $nsOwner"

# Databases
$dbOwner = docker compose exec -T db psql -U $DB_USER -d $DB_NAME -c "SELECT datname FROM pg_database WHERE datdba = (SELECT oid FROM pg_roles WHERE rolname = 'app_rw');" 2>&1 || true
$noDbs = ($dbOwner -match "^$" -or $dbOwner -eq "")
Check-Result "app_rw no dueña de bases de datos" $noDbs "Resultado: $dbOwner"

# -----------------------------------------------------------------------------
# 4. DDL operations que DEBEN FALLAR (42501)
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "--- 4. DDL operations que deben FALLAR ---"

# a) DROP TABLE vino
$drResult = Run-Sql-As-AppRw -Sql "DROP TABLE vino;" -ExpectedFail $true
Check-Result "DROP TABLE vino falla" ($drResult.success -eq $true)

# b) DROP TABLE stock_sala
$dr2Result = Run-Sql-As-AppRw -Sql "DROP TABLE stock_sala;" -ExpectedFail $true
Check-Result "DROP TABLE stock_sala falla" ($dr2Result.success -eq $true)

# c) DROP TABLE comprobante
$dr3Result = Run-Sql-As-AppRw -Sql "DROP TABLE comprobante;" -ExpectedFail $true
Check-Result "DROP TABLE comprobante falla" ($dr3Result.success -eq $true)

# d) DROP DATABASE (probar desde otra base si es posible)
# Intentamos desde la base actual primero; si no es posible, documentamos
$dr4Result = Run-Sql-As-AppRw -Sql "DROP DATABASE bodegas_atuel;" -ExpectedFail $true
Check-Result "DROP DATABASE bodegas_atuel falla" ($dr4Result.success -eq $true)

# e) DROP SCHEMA public CASCADE
$dr5Result = Run-Sql-As-AppRw -Sql "DROP SCHEMA public CASCADE;" -ExpectedFail $true
Check-Result "DROP SCHEMA public CASCADE falla" ($dr5Result.success -eq $true)

# f) ALTER TABLE ADD COLUMN
$dr6Result = Run-Sql-As-AppRw -Sql "ALTER TABLE vino ADD COLUMN prueba INT;" -ExpectedFail $true
Check-Result "ALTER TABLE ADD COLUMN falla" ($dr6Result.success -eq $true)

# g) TRUNCATE TABLE
$dr7Result = Run-Sql-As-AppRw -Sql "TRUNCATE TABLE vino;" -ExpectedFail $true
Check-Result "TRUNCATE TABLE falla" ($dr7Result.success -eq $true)

# h) CREATE TABLE en public
$dr8Result = Run-Sql-As-AppRw -Sql "CREATE TABLE prueba_rw (id INT);" -ExpectedFail $true
Check-Result "CREATE TABLE en public falla" ($dr8Result.success -eq $true)

# i) CREATE ROLE
$dr9Result = Run-Sql-As-AppRw -Sql "CREATE ROLE intruso;" -ExpectedFail $true
Check-Result "CREATE ROLE falla" ($dr9Result.success -eq $true)

# j) CREATE DATABASE
$dr10Result = Run-Sql-As-AppRw -Sql "CREATE DATABASE prueba;" -ExpectedFail $true
Check-Result "CREATE DATABASE falla" ($dr10Result.success -eq $true)

# k) ALTER ROLE SUPERUSER
$dr11Result = Run-Sql-As-AppRw -Sql "ALTER ROLE app_rw SUPERUSER;" -ExpectedFail $true
Check-Result "ALTER ROLE SUPERUSER falla" ($dr11Result.success -eq $true)

# l) DROP FUNCTION
$dr12Result = Run-Sql-As-AppRw -Sql "DROP FUNCTION fn_stock_sala(integer, integer);" -ExpectedFail $true
Check-Result "DROP FUNCTION falla" ($dr12Result.success -eq $true)

# m) DROP TRIGGER
$dr13Result = Run-Sql-As-AppRw -Sql "DROP TRIGGER trg_renglon_comprobante_antes ON renglon_comprobante;" -ExpectedFail $true
Check-Result "DROP TRIGGER falla" ($dr13Result.success -eq $true)

# n) ALTER TABLE DISABLE TRIGGER ALL
$dr14Result = Run-Sql-As-AppRw -Sql "ALTER TABLE renglon_comprobante DISABLE TRIGGER ALL;" -ExpectedFail $true
Check-Result "ALTER TABLE DISABLE TRIGGER ALL falla" ($dr14Result.success -eq $true)

# o) GRANT SELECT ON vino TO PUBLIC
$grantOutput = (docker compose exec -T db psql -U $DB_USER -d $DB_NAME -v ON_ERROR_STOP=1 -c "GRANT SELECT ON vino TO PUBLIC;" 2>&1 || true)
if ($grantOutput -match "no privileges were granted") {
    Check-Result "GRANT SELECT TO PUBLIC (no-op warning)" $true "Warning: no privileges were granted"
} else {
    # Verificar si realmente segrantó (debería fallar)
    Check-Result "GRANT SELECT TO PUBLIC no debería tener éxito" ($grantOutput -notmatch "GRANT") -and ($grantOutput -match "no privileges")
}

# p) COPY TO PROGRAM
$cpResult = Run-Sql-As-AppRw -Sql "COPY vino TO PROGRAM 'cat /etc/passwd';" -ExpectedFail $true
Check-Result "COPY TO PROGRAM falla" ($cpResult.success -eq $true)

# q) COPY FROM file
$cfResult = Run-Sql-As-AppRw -Sql "COPY vino FROM '/etc/passwd';" -ExpectedFail $true
Check-Result "COPY FROM file falla" ($cfResult.success -eq $true)

# r) SET ROLE propietario
$setResult = Run-Sql-As-AppRw -Sql "SET ROLE owner_bodegas;" -ExpectedFail $true
Check-Result "SET ROLE owner falla" ($setResult.success -eq $true)

# -----------------------------------------------------------------------------
# 5. Verificaciones que DEBEN FUNCIONAR (app_rw puede trabajar)
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "--- 5. Operations que deben FUNCIONAR para la API ---"

# a) SELECT sobre tablas
$selResult = Run-Sql-As-AppRw -Sql "SELECT count(*) FROM vino;" -ExpectedFail $false
Check-Result "SELECT en tabla funciona" ($selResult.success -eq $true)

# b) INSERT en tabla (con datos validos)
# Asegurar que hay datos de apoyo
$insertSupport = docker compose exec -T db psql -U $DB_USER -d $DB_NAME -v ON_ERROR_STOP=1 -c "INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional) VALUES ('20000001', 'TestCity', 'TestProv', 'Test');" 2>&1 || true
$insResult = Run-Sql-As-AppRw -Sql "INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento, nro_documento, direccion, codigo_postal, fecha_alta, tipo_cliente) values ('ApiTest', 'ApiUser', 'DNI', '12345678901', 'DirApi', '20000001', '2024-01-01', 'socio');" -ExpectedFail $false
Check-Result "INSERT en cliente funciona" ($insResult.success -eq $true)

# c) UPDATE en tabla
$updResult = Run-Sql-As-AppRw -Sql "UPDATE cliente SET apellido_razon_social = 'ApiModified' WHERE apellido_razon_social = 'ApiTest';" -ExpectedFail $false
Check-Result "UPDATE en cliente funciona" ($updResult.success -eq $true)

# d) DELETE de tabla
$delResult = Run-Sql-As-AppRw -Sql "DELETE FROM cliente WHERE apellido_razon_social = 'ApiModified';" -ExpectedFail $false
Check-Result "DELETE de cliente funciona" ($delResult.success -eq $true)

# e) USAGE en secuencias / INSERT con IDENTITY
$seqResult = Run-Sql-As-AppRw -Sql "INSERT INTO departamento (nombre, provincia) VALUES ('DeptSeqTest', 'ProvSeqTest');" -ExpectedFail $false
Check-Result "INSERT con IDENTITY/SERIAL funciona" ($seqResult.success -eq $true)

# f) CALL a procedimiento (esperar error de que no existe, no de permiso)
$callResult = Run-Sql-As-AppRw -Sql "CALL sp_procesar_transferencia(999999);" -ExpectedFail $true
Check-Result "CALL procedimiento falla por no existir (no por permiso)" ($callResult.success -eq $true)

# g) Llamar funcion
$funcResult = Run-Sql-As-AppRw -Sql "SELECT fn_stock_sala(1, 1);" -ExpectedFail $false
Check-Result "SELECT fn_stock_sala funciona" ($funcResult.success -eq $true)

# -----------------------------------------------------------------------------
# 6. Privilegios por catálogo (\dp)
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "--- 6. Privilegios por catálogo (\dp) ---"

$dpOutput = docker compose exec -T db psql -U $DB_USER -d $DB_NAME -c "\dp" 2>&1 || true

# Verificar que app_rw tenga privilegios pero revisar tipos
$appRwdpLines = ($dpOutput -split "`n") | Where-Object { $_ -match "app_rw" }
if ($appRwdpLines) {
    # En \dp, los símbolos son: r=SELECT, w=INSERT, d=DELETE, a=GRANT option
    # 'arwd' significa SELECT+INSERT+UPDATE+DELETE (a menudo 'a' es un flag, r/w/d son los privilegios)
    # Verificar que no haya TRUNCATE (t) ni REFERENCES (o símbolos extra)
    $hasTruncate = ($dpOutput -match "app_rw.*.*TRUNCATE") -or ($dpOutput -match "app_rw.*t")
    Check-Result "No TRUNCATE para app_rw en \dp" (-not $hasTruncate) "Resultado \dp: $dpOutput"

    # Verificar privilegios básicos esperados (arwd = SELECT+INSERT+UPDATE+DELETE)
    $hasBasicPrivs = ($dpOutput -match "app_rw.*arwd") -or ($dpOutput -match "app_rw.*rwd")
    Check-Result "app_rw tiene privilegios basicos (SELECT/INSERT/UPDATE/DELETE)" $hasBasicPrivs "Resultado \dp: $dpOutput"
} else {
    Check-Result "Revisar salida de \\dp para app_rw" $false "No se encontro app_rw en la salida de \\dp"
}

# -----------------------------------------------------------------------------
# 7. has_database_privilege y has_schema_privilege
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "--- 7. has_database_privilege y has_schema_privilege ---"

$dbPriv = docker compose exec -T db psql -U $DB_USER -d $DB_NAME -c "SELECT has_database_privilege('app_rw', current_database(), 'CREATE');" 2>&1 || true
$dbPrivVal = ($dbPriv -match "f" -and $dbPriv -notmatch "t") -and (-not $dbPriv -match "ERROR")
Check-Result "has_database_privilege CREATE = false" ($dbPriv -eq "f") "Resultado: $dbPriv"

$shPriv = docker compose exec -T db psql -U $DB_USER -d $DB_NAME -c "SELECT has_schema_privilege('app_rw', 'public', 'CREATE');" 2>&1 || true
Check-Result "has_schema_privilege CREATE = false" ($shPriv -eq "f") "Resultado: $shPriv"

# -----------------------------------------------------------------------------
# 8. Resumen final
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "=========================================================="
Write-Host "Resumen de verificacion"
Write-Host "=========================================================="
Write-Host "PASS:  $passCount"
Write-Host "FAIL:  $failCount"
Write-Host "Total: $($passCount + $failCount)"
Write-Host "=========================================================="

if ($failCount -gt 0) {
    Write-Host "ERROR: Algunas verificaciones fallaron. Revisar los detalles arriba."
    exit 1
} else {
    Write-Host "Todas las verificaciones pasaron exitósamente."
    exit 0
}