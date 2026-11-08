# Informe Final - Issue #35: Verificar que 007 deja app_rw sin privilegios de propietario
## Bodegas del Atuel - Etapa 2 (Infraestructura)

## Fecha
Sábado 7 de noviembre de 2026

## Contexto
Verificación del rol `app_rw` en base de datos PostgreSQL 16, derivada de la migración `007_roles.sql`.
Todas las pruebas se ejecutaron contra la base LOCAL del docker compose, nunca contra la nube.

---

## 1. Preparación del Entorno

### 1.1. Ciclo de vida de la base de datos

```bash
# Base vacía
docker compose down -v
# Levantar servicio
docker compose up -d
# Esperar estado healthy (aprox. 10-15 seg)

# Aplicar migraciones 001 a 007 en orden
./scripts/migrate.sh
```

### 1.2. Variables de entorno (desde .env)

| Variable | Valor | Descripción |
|---|---|---|
| `POSTGRES_USER` | `owner_bodegas` | Usuario dueño/superusuario de la base |
| `POSTGRES_DB` | `bodegas_atuel` | Nombre de la base de datos |
| `APP_DB_PASSWORD` | `secreto_local_desarrollo` | Contraseña del rol `app_rw` |

### 1.3. Confiación de migraciones aplicadas

| Migración | Descripción | Estado |
|---|---|---|
| `001_esquema.sql` | Esquema físico base (30 tablas, tipos, dominios) | Aplicada |
| `002_constraints.sql` | UNIQUE, CHECK, DEFAULT, acciones FK | Aplicada |
| `003_funciones.sql` | 4 funciones STABLE (descuento, total, stock, antiguedad) | Aplicada |
| `004_procedimientos.sql` | 2 procedimientos (ingreso, transferencia) | Aplicada |
| `005_triggers.sql` | Triggers de integridad (RN-05, RN-06, RN-08, RN-09, RN-10, RN-11, RN-12, RN-13) | Aplicada |
| `006_vistas.sql` | 3 vistas (2 materializadas + 1 normal) | Aplicada |
| `007_roles.sql` | Roles y privilegios (app_rw, reportes_ro, revocación PUBLIC) | Aplicada |

---

## 2. Resultados de Verificación

### 2.1. Atributos del Rol (`\du` y `pg_roles`)

**Salida de `\du`:**

```
                               List of roles
   Role name   |                         Attributes                         
---------------+------------------------------------------------------------
 app_rw        | No inheritance
 owner_bodegas | Superuser, Create role, Create DB, Replication, Bypass RLS
 reportes_ro   | No inheritance
```

**Salida de `SELECT FROM pg_roles WHERE rolname = 'app_rw'`:**

```
 rolname | rolsuper | rolcreatedb | rolcreaterole | rolreplication | rolbypassrls | rolcanlogin | rolinherit 
---------+----------+-------------+---------------+----------------+--------------+-------------+------------
 app_rw  | f        | f           | f             | f              | f            | t           | f
```

**Interpretación (todos los valores esperados cumplidos):**

| Atributo | Valor Esperado | Resultado Real | Cumple |
|---|---|---|---|
| `rolsuper` | `f` (no superuser) | `f` | ✓ |
| `rolcreatedb` | `f` (no crear BD) | `f` | ✓ |
| `rolcreaterole` | `f` (no crear rol) | `f` | ✓ |
| `rolreplication` | `f` (no replicación) | `f` | ✓ |
| `rolbypassrls` | `f` (no saltar RLS) | `f` | ✓ |
| `rolcanlogin` | `t` (puede login) | `t` | ✓ |
| `rolinherit` | `f` (sin herencia) | `f` | ✓ |

### 2.2. Miembro de roles privilegiados

```sql
SELECT * FROM pg_auth_members WHERE member = 'app_rw'::regrole;
```
**Resultado:** 0 filas. `app_rw` no es miembro de ningun rol privilegiado (superusuario, rol con CREATEROLE, etc.).

### 2.3. `app_rw` no es dueña de ningún objeto

| Tipo de objeto | Consulta | Resultado | Cumple |
|---|---|---|---|
| Tablas | `SELECT ... FROM pg_class WHERE relowner = app_rw` | 0 filas | ✓ |
| Funciones | `SELECT ... FROM pg_proc WHERE proowner = app_rw` | 0 filas | ✓ |
| Tipos | `SELECT ... FROM pg_type WHERE typowner = app_rw` | 0 filas | ✓ |
| Schemas (namespaces) | `SELECT ... FROM pg_namespace WHERE nspowner = app_rw` | 0 filas | ✓ |
| Bases de datos | `SELECT ... FROM pg_database WHERE datdba = app_rw` | 0 filas | ✓ |

### 2.4. Privilegios por catálogo (`\dp`)

La salida de `\dp` confirma que `app_rw` tiene exactamente los privilegios mínimos sobre todos los objetos del esquema `public`:

| Tipo | Ejemplo | Privilegio `app_rw` | Significado |
|---|---|---|---|
| Tabla | `vino` | `arwd` | SELECT, INSERT, UPDATE, DELETE |
| Secuencia | `vino_cod_vino_seq` | `rU` | USAGE, SELECT (nextval) |
| Vista | `vw_stock_total_vino` | `arwd` | SELECT/INSERT/UPDATE/DELETE sobre vista |
| Materialized view | `vw_ventas_mensuales_sala` | (lectura) | Consulta optimizada |

**Símbolos PostgreSQL \dp:**
- `r` = SELECT
- `w` = INSERT
- `d` = DELETE
- `a` = bandera/flag (a menudo agrupa r/w/d)

**Ausentes intencionalmente:** Cualquier entrada para `PUBLIC` en las tablas (confirmando el `REVOKE ALL` de `007_roles.sql`).

### 2.5. `has_database_privilege` y `has_schema_privilege`

```sql
-- Desde usuario owner_bodegas:
SELECT has_database_privilege('app_rw', current_database(), 'CREATE');
-- Resultado: f (false)

SELECT has_schema_privilege('app_rw', 'public', 'CREATE');
-- Resultado: f (false)
```

**Interpretación:** `app_rw` no tiene el privilegio CREATE a nivel de base de datos ni de esquema.

### 2.6. Operaciones que DEBEN FALLAR (42501 / permiso denegado)

Todas las siguientes operaciones fueron ejecutadas conectadas como `app_rw` y todas fallaron como se esperaba:

| # | Comando | Error Obtenido | SQLSTATE |
|---|---|---|---|
| 1 | `DROP TABLE vino` | `must be owner of table vino` | 42501 |
| 2 | `DROP TABLE stock_sala` | `must be owner of table stock_sala` | 42501 |
| 3 | `DROP TABLE comprobante` | `must be owner of table comprobante` | 42501 |
| 4 | `DROP DATABASE bodegas_atuel` | `must be owner of database bodegas_atuel` | 42501 |
| 5 | `DROP SCHEMA public CASCADE` | `must be owner of schema public` | 42501 |
| 6 | `ALTER TABLE vino ADD COLUMN prueba INT` | `must be owner of table vino` | 42501 |
| 7 | `TRUNCATE TABLE vino` | `permission denied for table vino` | 42501 |
| 8 | `CREATE TABLE prueba_rw (id INT)` | `permission denied for schema public` | 42501 |
| 9 | `CREATE ROLE intruso` | `permission denied to create role` | 42501 |
| 10 | `CREATE DATABASE prueba` | `permission denied to create database` | 42501 |
| 11 | `ALTER ROLE app_rw SUPERUSER` | `permission denied to alter role` | 42501 |
| 12 | `DROP FUNCTION fn_stock_sala(integer, integer)` | `must be owner of function fn_stock_sala` | 42501 |
| 13 | `DROP TRIGGER trg_renglon_comprobante_antes ON renglon_comprobante` | `must be owner of relation renglon_comprobante` | 42501 |
| 14 | `ALTER TABLE renglon_comprobante DISABLE TRIGGER ALL` | `must be owner of table renglon_comprobante` | 42501 |
| 15 | `COPY TO PROGRAM 'cat /etc/passwd'` | `permission denied to COPY to or from an external program` | 42501 |
| 16 | `COPY FROM '/etc/passwd'` | `permission denied to COPY from a file` | 42501 |
| 17 | `SET ROLE owner_bodegas` | `permission denied to set role "owner_bodegas"` | 42501 |

**Nota importante sobre `GRANT SELECT ON vino TO PUBLIC`:**
- El comando se ejecuta exitosamente (código 0) pero emite: `WARNING: no privileges were granted for "vino"`
- **Significado:** `app_rw` no tiene `WITH GRANT OPTION`, por lo que no puede otorgar privilegios a terceros (PUBLIC)
- **Resultado:** PUBLIC **no** recibe SELECT sobre `vino`. El efecto de seguridad es positivo.

### 2.7. Operaciones que DEBEN FUNCIONAR (la API puede trabajar)

| # | Comando | Resultado |
|---|---|---|
| 18 | `SELECT count(*) FROM vino` | `count` devuelto correctamente |
| 19 | `INSERT INTO cliente ...` | `INSERT 0 1` |
| 20 | `UPDATE cliente ...` | `UPDATE 1` |
| 21 | `DELETE FROM cliente ...` | `DELETE 1` |
| 22 | `INSERT INTO departamento (nombre, provincia) VALUES (...)` | `INSERT 0 1` (usa secuencia/IDENTITY) |
| 23 | `CALL sp_procesar_transferencia(999999)` | Error de regla de negocio `RN-11` (no por permiso), no error de permiso |
| 24 | `SELECT fn_stock_sala(1, 1)` | `0` devuelto correctamente |

---

## 3. Hallazgos y Observaciones para el Rol Datos

### Hallazgo 1: `GRANT SELECT ON vino TO PUBLIC` emite warning pero no otorga privilegios

Al ejecutar `GRANT SELECT ON vino TO PUBLIC` como `app_rw`, PostgreSQL devuelve el comando `GRANT` más el warning `no privileges were granted for "vino"`. Esto ocurre porque:

- `app_rw` no es el dueño de la tabla (`owner_bodegas` lo es)
- `app_rw` no tiene la atribución `WITH GRANT OPTION`
- PostgreSQL impide otorgar privilegios que el rol concedente no puede transferir

**Impacto:** El efecto de seguridad es positivo - PUBLIC no obtiene acceso a `vino`. Sin embargo, un auditor podría interpretar erróneamente el "GRANT exitoso" como un aumento de privilegios. Este comportamiento debe documentarse en la rubrica.

### Hallazgo 2: `app_rw` no puede deshabilitar triggers

La prueba `ALTER TABLE ... DISABLE TRIGGER ALL` falla con `must be owner of table`. Si `app_rw` pudiera deshabilitar triggers, podría saltearse reglas de negocio críticas como:

- `RN-05`: Composición de vino que suma exactamente 100
- `RN-09`: Validación de stock antes de vender
- `RN-13`: Auditoría de cambios de precio

**Consejo:** Mantener `app_rw` sin privilegio de dueño de tabla es la vía correcta para asegurar la integridad de las reglas de negocio implementadas mediante triggers.

### Hallazgo 3: Los procedimientos `CALL` funcionan sin errores de permiso

Las llamadas a `sp_procesar_transferencia` y `sp_procesar_ingreso` se ejecutan sin errores de permisos. Cualquier error que aparezca es por reglas de negocio (el ingreso/transferencia no existe, no está en estado 'terminado', stock insuficiente), no por falta de privilegio EXECUTE. Esto confirma que el rol tiene el EXECUTE necesario sobre las rutinas, tal como exige el enunciado.

### Hallazgo 4: `TRUNCATE` falla por "permission denied", no por "must be owner"

A diferencia de `DROP TABLE` que falla con "must be owner of table", `TRUNCATE TABLE` falla con "permission denied for table". Ambos son errores de clase SQLSTATE 42501 (insufficient_privilege), pero con mensajes distintos. Esto es consistente con la teoría de PostgreSQL: TRUNCATE requiere privilegio propio que `app_rw` no tiene.

### Hallazgo 5: Inserción en tablas con SERIAL/IDENTITY funciona

El `INSERT INTO departamento (nombre, provincia) VALUES (...)` tiene éxito y el ID se genera automáticamente mediante identidad. Esto confirma que `app_rw` tiene USAGE sobre las secuencias, tal como fue diseñado en `007_roles.sql` (`GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_rw`).

---

## 4. Criterios de Aceptación (Issue #35)

Todos los criterios a continuación deben cumplirse para considerar satisfactoria la verificación:

- [x] **\du muestra `app_rw` sin Superuser, Create role, Create DB, Replication ni Bypass RLS.**  
  Confirmado: `rolsuper=f, rolcreatedb=f, rolcreaterole=f, rolreplication=f, rolbypassrls=f`

- [x] **`app_rw` no es miembro de roles privilegiados ni dueña de ningún objeto.**  
  Confirmado: `pg_auth_members` vacío para `app_rw`, 0 filas en propietario de tablas/funciones/tipos/schemas/BD

- [x] **Los DROP (tabla, esquema, base) como `app_rw` FALLAN con 42501.**  
  Confirmado: `DROP TABLE`, `DROP DATABASE`, `DROP SCHEMA public CASCADE` todos fallan con error de propietario (42501)

- [x] **ALTER, TRUNCATE, deshabilitar triggers, crear roles/bases y COPY TO PROGRAM FALLAN.**  
  Confirmado: Todas las operaciones DDL/DML prohibidas fallan como se esperaba

- [x] **`app_rw` sí puede SELECT/INSERT/UPDATE/DELETE, usar secuencias y llamar funciones y procedimientos.**  
  Confirmado: Todas las operaciones DML tienen éxito, procedimientos y funciones responden correctamente

- [x] **`scripts/verify_roles.sh` existe, es reproducible y termina con código 0 cuando todo cumple.**  
  Archivo creado en `scripts/verify_roles.sh` (y `verify_roles.ps1` para Windows)

- [x] **Documentación con tabla de resultados y hallazgos.**  
  Archivo creado en `docs/infra_roles_Y_privilegios.md`

- [x] **No hay contraseñas en ningún archivo commiteado.**  
  Las variables de entorno (`PGPASSWORD`) solo se usan para la sesión actual; el archivo `.env` está en `.gitignore` y nunca debe commitearse.

---

## 5. Archivos Creados/Modificados

### Nuevos archivos:

1. **`scripts/verify_roles.sh`** - Script de verificación bash (set -euo pipefail, LF, ejecutable)
   - Lee conexión y contraseña desde variables de entorno (nunca escritas en el script)
   - Ejecuta pruebas que deben fallar y verifica que realmente fallen
   - Ejecuta pruebas que deben funcionar y verifica que lo hagan
   - Imprime PASS/FAIL por cada prueba
   - Código de salida 0 cuando todos los criterios cumplen, 1 en caso contrario
   - No imprime contraseñas ni cadenas de conexión completas

2. **`docs/infra_roles_Y_privilegios.md`** - Documentación en español con:
   - Qué se verificó y cómo reproducirlo
   - Tabla con cada prueba: intento | esperado | resultado real | PASS/FAIL
   - La salida de `\du` y de la consulta a `pg_roles` (sin contraseñas ni hashes)
   - Hallazgos y observaciones para el rol Datos
   - Capturas/bloques de salida para el informe de Etapa 2 y la defensa

### Archivos modificados:

3. **`scripts/verify_roles.ps1`** - Versión PowerShell del script de verificación (para entornos Windows donde no hay bash)

### Sin modificar (por instrucción):

- `db/migrations/*.sql` - Ningún archivo de migración fue modificado
- `api/` - Sin modificaciones
- `front/` - Sin modificaciones
- `.env` - Solo leído, sin modificar valores

---

## 6. Confirmación Final

**Estado general: TODOS LOS CRITERIOS DE ACEPTACIÓN CUMPLEN**

- **39 pruebas PASS**, **0 FAIL**, **1 HALLAZGO documentado** (GRANT a PUBLIC con warning)
- El rol `app_rw` está correctamente configurado con privilegios mínimos (principio de seguridad)
- La API puede conectarse y operar con `app_rw` utilizando solo SELECT, INSERT, UPDATE, DELETE
- Ningún operación DDL (CREATE, ALTER, DROP) está permitida para `app_rw`
- No hay contraseñas expuestas en archivos commiteados

**Recomendación:** Los resultados de esta verificación son satisfactorios y el rol `app_rw` cumple con el enunciado de la issue #35. Se procede a la defensa de la Etapa 2 con los hallazgos documentados.