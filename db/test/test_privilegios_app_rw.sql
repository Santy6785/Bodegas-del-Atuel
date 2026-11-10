-- =====================================================================
-- test_privilegios_app_rw.sql
-- Bodegas del Atuel - Pruebas de privilegios del rol app_rw (007_roles.sql).
--
-- Verifica que app_rw NO pueda escribir directamente en tablas de venta y
-- stock (comprobante, renglon_comprobante, stock_sala, stock_deposito,
-- auditoria_precio), pero SÍ pueda:
--   a) leer esas mismas tablas (SELECT),
--   b) ejecutar sp_crear_comprobante (SECURITY DEFINER) para registrar ventas.
--
-- Todo se ejecuta dentro de BEGIN; ... ROLLBACK; para no dejar datos.
--
-- Requisitos: base migrada (001 a 007), rol app_rw existente.
-- El script se ejecuta como owner_bodegas y usa SET ROLE app_rw para las
-- pruebas de privilegio.
--
-- Uso (desde la raiz del proyecto):
--   docker compose exec -T db psql -U <POSTGRES_USER> -d <POSTGRES_DB> -v ON_ERROR_STOP=1 -f db/test/test_privilegios_app_rw.sql
--   Get-Content db/test/test_privilegios_app_rw.sql | docker compose exec -T db psql -U <POSTGRES_USER> -d <POSTGRES_DB>
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- ---------------- Datos de prueba (como owner_bodegas) ----------------
INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
VALUES ('TSTPRIV', 'Localidad Priv', 'Mendoza', 'Enc')
ON CONFLICT DO NOTHING;

INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('99999999990', 'Bodega Priv', 'Dir')
ON CONFLICT DO NOTHING;

INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal)
VALUES ('Calle Priv', '1', 'lunes', 'TSTPRIV')
ON CONFLICT DO NOTHING;

INSERT INTO cepa (nombre, tipo) VALUES ('Cepa Priv', 'tinta') ON CONFLICT DO NOTHING;

INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
VALUES ('Vino Priv', 'tinto', 2021, 750, 14.0, 10000.00, '99999999990')
ON CONFLICT DO NOTHING;

INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
SELECT v.cod_vino, c.id_cepa, 100
  FROM vino v, cepa c
 WHERE v.nombre = 'Vino Priv' AND c.nombre = 'Cepa Priv'
ON CONFLICT DO NOTHING;

INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento,
                     nro_documento, direccion, codigo_postal,
                     fecha_alta, tipo_cliente)
VALUES ('Cliente Priv', 'C', 'CUIT', '99999999990', 'Dir', 'TSTPRIV', CURRENT_DATE, 'socio')
ON CONFLICT DO NOTHING;

INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
SELECT s.id_sala, v.cod_vino, 100
  FROM sala_venta s, vino v
 WHERE s.calle = 'Calle Priv' AND v.nombre = 'Vino Priv'
ON CONFLICT (id_sala, cod_vino) DO UPDATE SET cantidad = 100;

-- ---------------- Cambiar a rol app_rw para las pruebas de privilegio ----------------
SET ROLE app_rw;

-- ---------------- Prueba 1: app_rw NO puede INSERT en comprobante ----------------
DO $$
BEGIN
    INSERT INTO comprobante (id_cliente, id_sala)
    VALUES (
        (SELECT id_cliente FROM cliente WHERE nro_documento = '99999999990'),
        (SELECT id_sala FROM sala_venta WHERE calle = 'Calle Priv')
    );
    RAISE EXCEPTION 'FALLO 1: app_rw pudo INSERT en comprobante (deberia denegarse)';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK 1: app_rw no puede INSERT en comprobante';
END $$;

-- ---------------- Prueba 2: app_rw NO puede UPDATE stock_sala ----------------
DO $$
BEGIN
    UPDATE stock_sala SET cantidad = 999 WHERE id_sala = 1;
    RAISE EXCEPTION 'FALLO 2: app_rw pudo UPDATE en stock_sala (deberia denegarse)';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK 2: app_rw no puede UPDATE en stock_sala';
END $$;

-- ---------------- Prueba 3: app_rw NO puede UPDATE stock_deposito ----------------
DO $$
BEGIN
    UPDATE stock_deposito SET cantidad = 999 WHERE cod_vino = 1;
    RAISE EXCEPTION 'FALLO 3: app_rw pudo UPDATE en stock_deposito (deberia denegarse)';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK 3: app_rw no puede UPDATE en stock_deposito';
END $$;

-- ---------------- Prueba 4: app_rw NO puede INSERT en auditoria_precio ----------------
DO $$
BEGIN
    INSERT INTO auditoria_precio (cod_vino, precio_anterior, precio_nuevo)
    VALUES (1, 100, 200);
    RAISE EXCEPTION 'FALLO 4: app_rw pudo INSERT en auditoria_precio (deberia denegarse)';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK 4: app_rw no puede INSERT en auditoria_precio';
END $$;

-- ---------------- Prueba 5: app_rw NO puede DELETE de auditoria_precio ----------------
DO $$
BEGIN
    DELETE FROM auditoria_precio WHERE cod_vino = 1;
    RAISE EXCEPTION 'FALLO 5: app_rw pudo DELETE en auditoria_precio (deberia denegarse)';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK 5: app_rw no puede DELETE en auditoria_precio';
END $$;

-- ---------------- Prueba 6: app_rw SÍ puede SELECT en tablas restringidas ----------------
DO $$
DECLARE
    v_n INTEGER;
BEGIN
    SELECT count(*) INTO v_n FROM comprobante;
    RAISE NOTICE 'OK 6: app_rw puede SELECT en comprobante (%)', v_n;
    SELECT count(*) INTO v_n FROM stock_sala;
    RAISE NOTICE 'OK 6b: app_rw puede SELECT en stock_sala (%)', v_n;
    SELECT count(*) INTO v_n FROM auditoria_precio;
    RAISE NOTICE 'OK 6c: app_rw puede SELECT en auditoria_precio (%)', v_n;
END $$;

-- ---------------- Prueba 7: app_rw SÍ puede llamar sp_crear_comprobante (SECURITY DEFINER) ----------------
DO $$
DECLARE
    v_id_cliente INTEGER;
    v_id_sala INTEGER;
    v_cod_vino INTEGER;
    v_nro_comprobante INTEGER;
BEGIN
    SELECT id_cliente INTO v_id_cliente FROM cliente WHERE nro_documento = '99999999990';
    SELECT id_sala INTO v_id_sala FROM sala_venta WHERE calle = 'Calle Priv';
    SELECT cod_vino INTO v_cod_vino FROM vino WHERE nombre = 'Vino Priv';
    CALL sp_crear_comprobante(v_id_cliente, v_id_sala, ARRAY[v_cod_vino], ARRAY[5], v_nro_comprobante);
    IF v_nro_comprobante IS NULL THEN
        RAISE EXCEPTION 'FALLO 7: sp_crear_comprobante no devolvio nro_comprobante';
    END IF;
    RAISE NOTICE 'OK 7: app_rw puedo llamar sp_crear_comprobante, comprobante %', v_nro_comprobante;
END $$;

-- ---------------- Prueba 8: app_rw SÍ puede SELECT en vw_ventas_mensuales_sala ----------------
DO $$
DECLARE
    v_n INTEGER;
BEGIN
    SELECT count(*) INTO v_n FROM vw_ventas_mensuales_sala;
    RAISE NOTICE 'OK 8: app_rw puede SELECT en vw_ventas_mensuales_sala (%)', v_n;
END $$;

-- ---------------- Volver a rol owner ----------------
RESET ROLE;

SELECT '=== Todas las pruebas de privilegios app_rw pasaron ===' AS resultado;

-- ---------------- Descartar todos los datos de prueba ----------------
ROLLBACK;

\echo '=== Pruebas de privilegios app_rw terminadas sin errores (datos descartados) ==='
