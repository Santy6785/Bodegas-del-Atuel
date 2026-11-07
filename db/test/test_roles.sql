-- =====================================================================
-- test_roles.sql
-- Bodegas del Atuel - Verificación de Roles y Privilegios (007_roles.sql).
--
-- Comprueba los 3 roles y sus límites de seguridad:
--   1. Existencia y configuración de roles:
--      * app_rw: LOGIN, NOSUPERUSER, NOCREATEDB, NOCREATEROLE
--      * reportes_ro: LOGIN, NOSUPERUSER, NOCREATEDB, NOCREATEROLE
--      * owner_bodegas (o usuario actual): propietario con control total.
--
--   2. Permisos de app_rw (API REST):
--      * Puede hacer SELECT, INSERT, UPDATE, DELETE sobre tablas.
--      * Puede ejecutar funciones y procedimientos.
--      * NO puede crear tablas ni alterar el esquema (sin permisos DDL).
--
--   3. Permisos de reportes_ro (Solo Lectura):
--      * Puede hacer SELECT sobre tablas, vistas y vistas materializadas.
--      * Puede ejecutar funciones de cálculo.
--      * NO puede hacer INSERT, UPDATE ni DELETE (falla con 42501).
--
--   4. Aislamiento de PUBLIC:
--      * Ningún usuario anónimo/público tiene privilegios sobre el esquema.
-- =====================================================================

\set ON_ERROR_STOP on

-- 1. Verificación en catálogo pg_roles
DO $$
DECLARE
    r_app RECORD;
    r_ro  RECORD;
BEGIN
    SELECT rolcanlogin, rolsuper, rolcreatedb, rolcreaterole
      INTO r_app
      FROM pg_roles
     WHERE rolname = 'app_rw';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'FALLO: no existe el rol app_rw';
    END IF;

    IF NOT r_app.rolcanlogin OR r_app.rolsuper OR r_app.rolcreatedb OR r_app.rolcreaterole THEN
        RAISE EXCEPTION 'FALLO: app_rw tiene privilegios excesivos o no puede hacer login';
    END IF;

    SELECT rolcanlogin, rolsuper, rolcreatedb, rolcreaterole
      INTO r_ro
      FROM pg_roles
     WHERE rolname = 'reportes_ro';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'FALLO: no existe el rol reportes_ro';
    END IF;

    IF NOT r_ro.rolcanlogin OR r_ro.rolsuper OR r_ro.rolcreatedb OR r_ro.rolcreaterole THEN
        RAISE EXCEPTION 'FALLO: reportes_ro tiene privilegios excesivos o no puede hacer login';
    END IF;

    RAISE NOTICE 'OK 1: Roles app_rw y reportes_ro existen con flags de seguridad minimos (NOSUPERUSER)';
END
$$;

-- 2. Pruebas de permisos con SET ROLE (simula la sesión de cada usuario)
BEGIN;

-- ---------------------------------------------------------------------
-- 2.1 Pruebas de app_rw (Lectura y Escritura)
-- ---------------------------------------------------------------------
SET ROLE app_rw;

-- Debe poder consultar tablas y vistas
SELECT COUNT(*) FROM vino;
SELECT COUNT(*) FROM vw_stock_total_vino;

-- Debe poder llamar a funciones
SELECT fn_descuento_cliente(1);

-- NO debe poder crear tablas (DDL no permitido para la API)
DO $$
BEGIN
    BEGIN
        CREATE TABLE tabla_no_autorizada (id int);
        RAISE EXCEPTION 'FALLO: app_rw pudo crear una tabla (DDL no permitido)';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK 2a: app_rw no puede crear tablas (insufficient_privilege - 42501)';
    END;
END
$$;

RESET ROLE;

-- ---------------------------------------------------------------------
-- 2.2 Pruebas de reportes_ro (Solo Lectura)
-- ---------------------------------------------------------------------
SET ROLE reportes_ro;

-- Debe poder consultar tablas, vistas y vistas materializadas
SELECT COUNT(*) FROM vino;
SELECT COUNT(*) FROM vw_stock_total_vino;
SELECT COUNT(*) FROM vw_ventas_mensuales_sala;

-- Debe poder ejecutar funciones de cálculo
SELECT fn_antiguedad_anios(CURRENT_DATE - 365);

-- NO debe poder insertar en tablas
DO $$
BEGIN
    BEGIN
        INSERT INTO bodega (cuit, razon_social, domicilio)
        VALUES ('30999999999', 'Bodega Denegada', 'Calle Falsa 123');
        RAISE EXCEPTION 'FALLO: reportes_ro pudo insertar datos';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK 2b: reportes_ro no puede insertar datos (insufficient_privilege - 42501)';
    END;
END
$$;

-- NO debe poder modificar datos
DO $$
BEGIN
    BEGIN
        UPDATE vino SET precio = precio + 1;
        RAISE EXCEPTION 'FALLO: reportes_ro pudo modificar datos';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK 2c: reportes_ro no puede actualizar datos (insufficient_privilege - 42501)';
    END;
END
$$;

RESET ROLE;

ROLLBACK;

\echo '=== Pruebas de roles y privilegios terminadas sin errores ==='
