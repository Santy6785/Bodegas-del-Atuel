-- =====================================================================
-- 007_roles.sql
-- Bodegas del Atuel - Roles y Privilegios del Sistema (Etapa 2)
--
-- Exigencia del TPI (Secciones 2, 6, 7 y Anexo A.7):
--   1. Revocación de privilegios públicos:
--      REVOKE ALL ON SCHEMA public FROM PUBLIC
--      y sobre todas las tablas, secuencias y rutinas.
--
--   2. Tres roles con privilegios mínimos (principio de seguridad):
--      * Propietario (owner_bodegas / CURRENT_USER):
--        Dueño de la base y del esquema. Aplica DDL, migraciones y carga masiva.
--
--      * Lectura y Escritura (app_rw):
--        Utilizado EXCLUSIVAMENTE por la API REST (NUNCA el propietario).
--        Tiene permisos de SELECT, INSERT, UPDATE, DELETE sobre tablas,
--        USAGE sobre secuencias y EXECUTE sobre rutinas/funciones.
--        Sin permisos de modificación de esquema (DDL) ni superusuario.
--
--      * Solo Lectura (reportes_ro):
--        Destinado a reportes, dashboards de solo lectura y auditoría.
--        Tiene permisos de SELECT sobre tablas y vistas (incluyendo
--        materializadas) y EXECUTE sobre funciones de cálculo.
--        No puede modificar datos ni avanzar secuencias.
--
-- Las contraseñas se inyectan mediante variables psql (-v app_password=...
-- y -v ro_password=...), definidas en .env y pasadas desde scripts/migrate.sh.
-- =====================================================================

-- Las contraseñas se inyectan mediante variables psql (-v app_password=...
-- y -v ro_password=...), definidas en .env (APP_DB_PASSWORD / APP_RO_PASSWORD)
-- y pasadas desde scripts/migrate.sh. Este archivo no contiene valores por
-- defecto: los secretos se eliminaron del repositorio y deben proveerse por
-- entorno; si faltan, psql fallará al evaluar :'app_password' / :'ro_password'.

BEGIN;

-- =====================================================================
-- 1. Creación de Roles de Aplicación (idempotente)
-- =====================================================================

DO $roles$
BEGIN
    -- Rol de lectura y escritura para la API
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_rw') THEN
        CREATE ROLE app_rw WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
    ELSE
        ALTER ROLE app_rw WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
    END IF;

    -- Rol de solo lectura para reportes y dashboards
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'reportes_ro') THEN
        CREATE ROLE reportes_ro WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
    ELSE
        ALTER ROLE reportes_ro WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
    END IF;
END
$roles$;

-- Asignación de contraseñas parametrizadas
\getenv app_password APP_DB_PASSWORD
\getenv ro_password APP_RO_PASSWORD
ALTER ROLE app_rw WITH PASSWORD :'app_password';
ALTER ROLE reportes_ro WITH PASSWORD :'ro_password';

-- =====================================================================
-- 2. Revocación de privilegios de PUBLIC (aislamiento de seguridad)
-- =====================================================================

-- Quitar permisos públicos sobre el esquema public
REVOKE ALL ON SCHEMA public FROM PUBLIC;

-- Quitar permisos públicos sobre todos los objetos existentes
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM PUBLIC;


-- =====================================================================
-- 3. Privilegios para el Propietario (CURRENT_USER)
-- =====================================================================

GRANT ALL PRIVILEGES ON SCHEMA public TO CURRENT_USER;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO CURRENT_USER;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO CURRENT_USER;
GRANT ALL PRIVILEGES ON ALL ROUTINES IN SCHEMA public TO CURRENT_USER;


-- =====================================================================
-- 4. Privilegios para la API REST (app_rw) - Mínimo Privilegio
-- =====================================================================
-- Puede consultar y manipular datos, avanzar secuencias para IDs y
-- ejecutar funciones y procedimientos. No puede alterar estructura (DDL).
-- No tiene escritura directa en tablas de venta y stock (comprobante,
-- renglon_comprobante, stock_sala, stock_deposito, auditoria_precio):
-- esa escritura la hacen procedimientos y triggers SECURITY DEFINER
-- (ver 004_procedimientos.sql y 005_triggers.sql).

GRANT USAGE ON SCHEMA public TO app_rw;

-- Revocar todo privilegio previo sobre tablas (el GRANT ON ALL TABLES
-- anterior concedía escritura directa en tablas restringidas).
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM app_rw;

-- Tablas que la API administra directamente por CRUD: escritura permitida.
-- Incluye catálogos, maestros y movimientos que la API lee y escribe
-- a través de los endpoints REST.
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
    vino, vino_cepa, vino_maridaje,
    cliente, cliente_distribuidor, cliente_exportador, permiso_exportacion,
    ingreso, renglon_ingreso,
    transferencia, renglon_transferencia,
    departamento, finca, parcela, lote_uva, analisis_calidad,
    bodega, cepa, maridaje, transportista, transportista_localidad,
    sala_venta, localidad, empleado
TO app_rw;

-- Tablas escritas solo por procedimientos o triggers SECURITY DEFINER.
-- app_rw solo puede leerlas: nunca escribir directamente.
-- comprobante y renglon_comprobante: escritos por sp_crear_comprobante.
-- stock_sala y stock_deposito: escritos por sp_procesar_* y triggers.
-- auditoria_precio: escrito por trg_vino_auditoria_precio.
GRANT SELECT ON TABLE
    comprobante, renglon_comprobante,
    stock_sala, stock_deposito,
    auditoria_precio, vino_lote
TO app_rw;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_rw;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO app_rw;


-- Vistas materializadas no quedan cubiertas por ON ALL TABLES.
GRANT SELECT ON vw_ventas_mensuales_sala TO app_rw;
GRANT SELECT ON vw_stock_total_vino TO app_rw;


-- =====================================================================
-- 5. Privilegios para Reportes (reportes_ro) - Solo Lectura
-- =====================================================================
-- Solo puede consultar tablas, vistas y vistas materializadas, y ejecutar
-- funciones de cálculo. No puede insertar, actualizar ni borrar.

GRANT USAGE ON SCHEMA public TO reportes_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO reportes_ro;
GRANT SELECT ON vw_ventas_mensuales_sala TO reportes_ro;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO reportes_ro;


-- =====================================================================
-- 6. Privilegios por defecto (ALTER DEFAULT PRIVILEGES)
-- =====================================================================
-- Asegura que futuros objetos (tablas, secuencias, funciones) creados por
-- el propietario hereden automáticamente estos mismos privilegios mínimos.

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO app_rw;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO app_rw;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT EXECUTE ON ROUTINES TO app_rw;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO reportes_ro;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT EXECUTE ON ROUTINES TO reportes_ro;

COMMIT;
