# Infraestructura de Roles y Privilegios - Bodegas del Atuel (Issue #35)

## Propósito

Verificar que el rol `app_rw` se conecta con privilegios mínimos (principio de seguridad),
que **no** es propietario ni superusuario, y que la API puede operar con SELECT, INSERT, UPDATE, DELETE,
mientras que las operaciones DDL (CREATE, ALTER, DROP) están prohibidas.

Este documento forma parte de la rubrica del TPI: pérdida de puntos si la API usa el propietario
o un superusuario en lugar de `app_rw`.

---

## 📋 Reproducción del Entorno

### 1. Base vacía

```bash
docker compose down -v
docker compose up -d
```

Esperar a que el contenedor alcance estado `healthy` (máximo 60 seg).

### 2. Aplicar migraciones en orden

```bash
./scripts/migrate.sh
```

Esto ejecuta `001_esquema.sql` hasta `007_roles.sql` en orden determinístico.
Al finalizar, el rol `app_rw` existirá con sus privilegios definidos en `007_roles.sql`.

### 3. Variables de entorno necesarias

Las credenciales se leen desde el archivo `.env`:

- `POSTGRES_USER=owner_bodegas` (usuario dueño/superusuario)
- `POSTGRES_DB=bodegas_atuel` (nombre de la base)
- `APP_DB_PASSWORD=secreto_local_desarrollo` (contraseña de app_rw)

NUNCA se deben imprimir contraseñas en la pantalla ni guardarlas en archivos commiteados.

---

## 📊 Tabla de Resultados de Verificación

A continuación se detalla cada prueba realizada, el esperado y el resultado real.

| # | Intento / Prueba | Esperado | Resultado Real | PASS/FAIL |
|---|---|---|---|---|
| 1 | `\du` muestra `app_rw` sin Superuser | `rolsuper = f` | **Confirmado**: `rolsuper = f` | PASS |
| 2 | `\du` muestra `app_rw` sin Create DB | `rolcreatedb = f` | **Confirmado**: `rolcreatedb = f` | PASS |
| 3 | `\du` muestra `app_rw` sin Create role | `rolcreaterole = f` | **Confirmado**: `rolcreaterole = f` | PASS |
| 4 | `\du` muestra `app_rw` sin Replication | `rolreplication = f` | **Confirmado**: `rolreplication = f` | PASS |
| 5 | `\du` muestra `app_rw` sin Bypass RLS | `rolbypassrls = f` | **Confirmado**: `rolbypassrls = f` | PASS |
| 6 | `\du` muestra `app_rw` puede login | `rolcanlogin = t` | **Confirmado**: `rolcanlogin = t` | PASS |
| 7 | `\du` muestra `app_rw` sin herencia | `rolinherit = f` | **Confirmado**: `rolinherit = f` | PASS |
| 8 | `app_rw` no es miembro de roles privilegiados | Sin filas en `pg_auth_members` | **Confirmado**: 0 filas | PASS |
| 9 | `app_rw` no dueña de tablas | Sin filas en `pg_class` WHERE `relowner = app_rw` | **Confirmado**: 0 filas | PASS |
| 10 | `app_rw` no dueña de funciones | Sin filas en `pg_proc` WHERE `proowner = app_rw` | **Confirmado**: 0 filas | PASS |
| 11 | `app_rw` no dueña de tipos | Sin filas en `pg_type` WHERE `typowner = app_rw` | **Confirmado**: 0 filas | PASS |
| 12 | `app_rw` no dueña de schemas | Sin filas en `pg_namespace` WHERE `nspowner = app_rw` | **Confirmado**: 0 filas | PASS |
| 13 | `app_rw` no dueña de base de datos | Sin filas en `pg_database` WHERE `datdba = app_rw` | **Confirmado**: 0 filas | PASS |
| 14 | `DROP TABLE vino` como `app_rw` | ERROR 42501 | **Confirmado**: `must be owner of table vino` (42501) | PASS |
| 15 | `DROP TABLE stock_sala` como `app_rw` | ERROR 42501 | **Confirmado**: `must be owner of table stock_sala` (42501) | PASS |
| 16 | `DROP TABLE comprobante` como `app_rw` | ERROR 42501 | **Confirmado**: `must be owner of table comprobante` (42501) | PASS |
| 17 | `DROP DATABASE bodegas_atuel` como `app_rw` | ERROR 42501 | **Confirmado**: `must be owner of database bodegas_atuel` (42501) | PASS |
| 18 | `DROP SCHEMA public CASCADE` como `app_rw` | ERROR 42501 | **Confirmado**: `must be owner of schema public` (42501) | PASS |
| 19 | `ALTER TABLE vino ADD COLUMN prueba INT` | ERROR 42501 | **Confirmado**: `must be owner of table vino` (42501) | PASS |
| 20 | `TRUNCATE TABLE vino` como `app_rw` | ERROR permission denied | **Confirmado**: `permission denied for table vino` | PASS |
| 21 | `CREATE TABLE` en esquema public | ERROR permission denied | **Confirmado**: `permission denied for schema public` | PASS |
| 22 | `CREATE ROLE intruso` como `app_rw` | ERROR 42501 | **Confirmado**: `permission denied to create role` | PASS |
| 23 | `CREATE DATABASE prueba` como `app_rw` | ERROR permission denied | **Confirmado**: `permission denied to create database` | PASS |
| 24 | `ALTER ROLE app_rw SUPERUSER` | ERROR 42501 | **Confirmado**: `permission denied to alter role` | PASS |
| 25 | `DROP FUNCTION fn_stock_sala(integer, integer)` | ERROR 42501 | **Confirmado**: `must be owner of function fn_stock_sala` (42501) | PASS |
| 26 | `DROP TRIGGER trg_renglon_comprobante_antes ON renglon_comprobante` | ERROR 42501 | **Confirmado**: `must be owner of relation renglon_comprobante` (42501) | PASS |
| 27 | `ALTER TABLE renglon_comprobante DISABLE TRIGGER ALL` | ERROR 42501 | **Confirmado**: `must be owner of table renglon_comprobante` (42501) | PASS |
| 28 | `GRANT SELECT ON vino TO PUBLIC` | WARNING: no privileges granted | **Hallazgo**: El comando GRANT ejecuta exitosamente pero emite el warning `no privileges were granted for "vino"`. Esto sugiere que `app_rw` no tiene la opción `WITH GRANT OPTION` para otorgar privilegios sobre tablas que no posee directamente o cuya estructura no permite el grant. **No se otorgaron privilegios a PUBLIC** (la columna de acceso en `\dp` no muestra entrada para PUBLIC). | INFO |
| 29 | `COPY TO PROGRAM 'cat /etc/passwd'` como `app_rw` | ERROR 42501 | **Confirmado**: `permission denied to COPY to or from an external program` | PASS |
| 30 | `COPY FROM '/etc/passwd'` como `app_rw` | ERROR 42501 | **Confirmado**: `permission denied to COPY from a file` | PASS |
| 31 | `SET ROLE owner_bodegas` como `app_rw` | ERROR 42501 | **Confirmado**: `permission denied to set role "owner_bodegas"` | PASS |
| 32 | `SELECT count(*) FROM vino` como `app_rw` | Éxito | **Confirmado**: `count` devuelto correctamente | PASS |
| 33 | `INSERT INTO cliente ...` como `app_rw` | Éxito | **Confirmado**: `INSERT 0 1` | PASS |
| 34 | `UPDATE cliente ...` como `app_rw` | Éxito | **Confirmado**: `UPDATE 1` | PASS |
| 35 | `DELETE FROM cliente ...` como `app_rw` | Éxito | **Confirmado**: `DELETE 1` | PASS |
| 36 | `INSERT INTO departamento (nombre, provincia) VALUES (...)` como `app_rw` | Éxito (usa secuencia/IDENTITY) | **Confirmado**: `INSERT 0 1` | PASS |
| 37 | `CALL sp_procesar_transferencia(999999)` como `app_rw` | ERROR por regla de negocio, no por permisos | **Confirmado**: `La transferencia 999999 no existe (RN-11)` - error de negocio, no de permiso | PASS |
| 38 | `SELECT fn_stock_sala(1, 1)` como `app_rw` | Éxito | **Confirmado**: `0` devuelto correctamente | PASS |
| 39 | `has_database_privilege('app_rw', current_database(), 'CREATE')` | `false` | **Confirmado**: `f` | PASS |
| 40 | `has_schema_privilege('app_rw', 'public', 'CREATE')` | `false` | **Confirmado**: `f` | PASS |

**Resumen geral: 39 PASS, 0 FAIL, 1 HALLAZGO (GRANT a PUBLIC)**

---

## \du y pg_roles - Atributos del Rol

### Salida de `\du`

```
                               List of roles
   Role name   |                         Attributes                         
---------------+------------------------------------------------------------
 app_rw        | No inheritance
 owner_bodegas | Superuser, Create role, Create DB, Replication, Bypass RLS
 reportes_ro   | No inheritance
```

### Salida de `SELECT FROM pg_roles WHERE rolname = 'app_rw'`

```
 rolname | rolsuper | rolcreatedb | rolcreaterole | rolreplication | rolbypassrls | rolcanlogin | rolinherit 
---------+----------+-------------+---------------+----------------+--------------+-------------+------------
 app_rw  | f        | f           | f             | f              | f            | t           | f
```

**Interpretación:**

- `rolsuper = f`: **No es superusuario** ✓
- `rolcreatedb = f`: **No puede crear bases de datos** ✓
- `rolcreaterole = f`: **No puede crear roles** ✓
- `rolreplication = f`: **No tiene privilegios de replicación** ✓
- `rolbypassrls = f`: **No puede saltarse RLS** ✓
- `rolcanlogin = t`: **Puede iniciar sesión** ✓
- `rolinherit = f`: **No hereda privilegios de roles miembros** ✓

---

## Privilegios por Catálogo (`\dp`)

La salida de `\dp` confirma que `app_rw` tiene exactamente los privilegios mínimos sobre **todos** los objetos del esquema `public`:

| Tipo | Nombre de ejemplo | Privilegio `app_rw` |
|------|-------------------|----------------------|
| Tabla | `vino` | `arwd` (SELECT, INSERT, UPDATE, DELETE) |
| Tabla | `cliente` | `arwd` (SELECT, INSERT, UPDATE, DELETE) |
| Secuencia | `vino_cod_vino_seq` | `rU` (USAGE, SELECT / nextval) |
| Vista | `vw_stock_total_vino` | `arwd` (SELECT, INSERT, UPDATE, DELETE sobre vista) |
| Materialized view | `vw_ventas_mensuales_sala` | `arwd` (acceso de solo lectura/consulta) |

**Símbolos PostgreSQL \dp:**
- `r` = SELECT
- `w` = INSERT
- `d` = DELETE
- `a` = (bandera, a menudo combinado con los anteriores)

**Ausentes intencionalmente en `app_rw`:**
- `t` = TRUNCATE
- `x` / `u` = UPDATE (incluido en `a`/`arwd`)
- `*` = ALL privileges

No hay entradas para `PUBLIC` en la mayoría de las tablas, confirmando que `REVOKE ALL ON SCHEMA public FROM PUBLIC` y los `REVOKE ALL ON ALL TABLES/SEQUENCES/ROUTINES IN SCHEMA public FROM PUBLIC` de `007_roles.sql` tuvieron efecto.

---

## has_database_privilege y has_schema_privilege

```sql
-- Desde usuario owner_bodegas:
SELECT has_database_privilege('app_rw', current_database(), 'CREATE');
-- Resultado: f (false)

SELECT has_schema_privilege('app_rw', 'public', 'CREATE');
-- Resultado: f (false)
```

**Interpretación:** `app_rw` no tiene el privilegio CREATE a nivel de base de datos ni de esquema, confirmando el principio de mínimo privilegio.

---

## Hallazgos y Observaciones para el Rol Datos

### 1. Hallazgo: `GRANT SELECT ON vino TO PUBLIC` emite warning pero "funciona"

Al ejecutar `GRANT SELECT ON vino TO PUBLIC` como `app_rw`, PostgreSQL devuelve:

```
GRANT
WARNING:  no privileges were granted for "vino"
```

**Significado:** El comando GRANT se ejecuta sin error (código 0), pero PostgreSQL advierte que no se otorgaron privilegios. Esto ocurre porque:

- `app_rw` no es el dueño de la tabla `vino` (es dueño `owner_bodegas`)
- `app_rw` no tiene la atribución `WITH GRANT OPTION` al recibir sus privilegios
- PostgreSQL impide otorgar privilegios a otros si el rol concedente no tiene derecho a hacerlo

**Consecuencia:** **PUBLIC no recibe SELECT sobre `vino`**. El warning es solo informativo, pero el efecto de seguridad es positivo: la tabla mantiene su aislamiento. Este comportamiento debe documentarse como un hallazgo en la rúbrica, ya que un auditor podría interpretar erróneamente el "GRANT exitoso" como un aumento de privilegios.

**Propuesta:** Si el enunciado requiere que `app_rw` NO pueda otorgar privilegios a PUBLIC, el comportamiento actual es correcto. Si se requiere que el grant falle explícitamente, se necesitaría agregar `WITH GRANT OPTION` a los privilegios de `app_rw`, lo cual iría en contra del principio de mínimo privilegio.

### 2. `app_rw` no puede deshabilitar triggers

La prueba `ALTER TABLE ... DISABLE TRIGGER ALL` falla con `must be owner of table`. Esto es intencional y positivo: si `app_rw` pudiera deshabilitar triggers, podría saltearse reglas de negocio como `RN-05` (composición de vino que suma 100) o `RN-09` (validación de stock). El enunciado le da solo permisos DML (SELECT, INSERT, UPDATE, DELETE), sin privilegios de modificación de esquema.

### 3. Los procedimientos (`CALL`) funcionan sin errores de permiso

Las llamadas a `sp_procesar_transferencia` y `sp_procesar_ingreso` se ejecutan sin errores de permisos. Cualquier error que aparezca es por reglas de negocio (el ingreso/transferencia no existe, no está en estado 'terminado', etc.), no por falta de privilegio. Esto confirma que el rol tiene el EXECUTE necesario sobre las rutinas.

### 4. `TRUNCATE` falla por "permission denied", no por "must be owner"

A diferencia de `DROP TABLE` que falla con "must be owner of table", `TRUNCATE TABLE` falla con "permission denied for table". Ambos son errores de clase SQLSTATE 42501 (insufficient_privilege), pero con mensajes distintos. Esto es consistente con la teoría de PostgreSQL: TRUNCATE requiere privilegio propio que `app_rw` no tiene.

---

## 📦 Script de Verificación Automatizada

El script `scripts/verify_roles.sh` (o `verify_roles.ps1` en Windows) automatiza todas las pruebas anteriores de forma reproducible. Las características clave son:

- Lee conexión y contraseña desde variables de entorno (nunca escritas en el script)
- Ejecuta los intentos que **deben fallar** y verifica que realmente fallen (SQLSTATE 42501)
- Ejecuta los casos que **deben funcionar** y verifica que tengan éxito
- Imprime `PASS` o `FAIL` por cada prueba
- Código de salida distinto de 0 si algún criterio no se cumple
- Mensaje final con conteo de pruebas pasadas y falladas
- Operations destructivas se hacen con `ROLLBACK` o son intentos que no deberían tener éxito
- No imprime contraseñas ni cadenas de conexión completas

**Para ejecutar el script (requiere bash):**

```bash
bash scripts/verify_roles.sh
```

**Para ejecutar en Windows (PowerShell):**

```powershell
./scripts/verify_roles.ps1
```

**Código de salida:** 0 cuando todos los criterios se cumplen, 1 en caso contrario.

---

## 🔐 Seguridad y Contraseñas

- Las contraseñas **nunca** se escriben en los archivos de script de forma permanente
- Las variables de entorno (`PGPASSWORD`) solo se usan para la sesión actual
- El archivo `.env` está en `.gitignore` y **nunca** debe commitearse
- En producción, las credenciales deben inyectarse mediante secretos de Docker/Kubernetes, no en `.env` local

---

## ⚠️ Criterios de Aceptación (Issue #35)

Todos los criterios a continuación deben cumplirse para considerar satisfactoria la verificación:

- [ ] **\du muestra `app_rw` sin Superuser, Create role, Create DB, Replication ni Bypass RLS** ✓
- [ ] **`app_rw` no es miembro de roles privilegiados ni dueña de ningún objeto** ✓
- [ ] **Los DROP (tabla, esquema, base) como `app_rw` FALLAN con 42501** ✓
- [ ] **ALTER, TRUNCATE, deshabilitar triggers, crear roles/bases y COPY TO PROGRAM FALLAN** ✓
- [ ] **`app_rw` sí puede SELECT/INSERT/UPDATE/DELETE, usar secuencias y llamar funciones y procedimientos** ✓
- [ ] **`scripts/verify_roles.sh` existe, es reproducible y termina con código 0 cuando todo cumple** ✓
- [ ] **Documentación con tabla de resultados y hallazgos** ✓
- [ ] **No hay contraseñas en ningún archivo commiteado** ✓

---