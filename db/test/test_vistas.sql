-- =====================================================================
-- test_vistas.sql
-- Bodegas del Atuel - Pruebas de las vistas de 006_vistas.sql.
--
-- Verifica:
--   1. Existencia de las 3 vistas en los catálogos (2 estándar y 1 materializada).
--   2. vw_stock_total_vino:
--      * Suma correcta de depósito central + salas.
--      * Manejo de ceros con COALESCE cuando no hay stock registrado.
--   3. vw_documentos_pendientes:
--      * Muestra ingresos y transferencias en confección o terminados.
--      * Excluye documentos con estado 'procesado'.
--      * Suma correcta de botellas y variedades.
--   4. vw_ventas_mensuales_sala (materializada):
--      * Agrupación por sala y mes (período YYYY-MM).
--      * Totales facturados y conteo de botellas vendidas.
--      * Funcionamiento del comando REFRESH MATERIALIZED VIEW.
--
-- Todo se ejecuta dentro de una transacción y se descarta con ROLLBACK.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    v_cb      cuit_dom := '99999999981';
    v_ct      cuit_dom := '99999999982';
    v_sala1   INTEGER;
    v_sala2   INTEGER;
    v_vino1   INTEGER;
    v_vino2   INTEGER;
    v_transp  INTEGER;
    v_ing1    INTEGER;
    v_ing2    INTEGER;
    v_tr1     INTEGER;
    v_cli     INTEGER;
    v_comp    INTEGER;
    v_dep     INTEGER;
    v_salas   BIGINT;
    v_tot     BIGINT;
    v_cant    INTEGER;
    v_fact    NUMERIC(14,2);
    v_bot     BIGINT;
BEGIN
    -- -----------------------------------------------------------------
    -- 1. Verificación de existencia en catálogo
    -- -----------------------------------------------------------------
    IF NOT EXISTS (SELECT 1 FROM pg_views WHERE schemaname = 'public' AND viewname = 'vw_stock_total_vino') THEN
        RAISE EXCEPTION 'FALLO: no existe la vista vw_stock_total_vino';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_views WHERE schemaname = 'public' AND viewname = 'vw_documentos_pendientes') THEN
        RAISE EXCEPTION 'FALLO: no existe la vista vw_documentos_pendientes';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_matviews WHERE schemaname = 'public' AND matviewname = 'vw_ventas_mensuales_sala') THEN
        RAISE EXCEPTION 'FALLO: no existe la vista materializada vw_ventas_mensuales_sala';
    END IF;

    RAISE NOTICE 'OK 1: Las 3 vistas existen en los catalogos del sistema';

    -- -----------------------------------------------------------------
    -- 2. Datos de prueba
    -- -----------------------------------------------------------------
    INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
    VALUES ('VIST0001', 'Localidad Vistas', 'Mendoza', 'Encargado Vistas');

    INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal)
    VALUES ('Calle Vistas', '100', 'lunes', 'VIST0001')
    RETURNING id_sala INTO v_sala1;

    INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal)
    VALUES ('Calle Vistas', '200', 'martes', 'VIST0001')
    RETURNING id_sala INTO v_sala2;

    INSERT INTO bodega (cuit, razon_social, domicilio)
    VALUES (v_cb, 'Bodega Vistas Test', 'Domicilio Vistas');

    INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio)
    VALUES ('Transporte Vistas', v_ct, 'transporte@vistas.test', '111111', 'Domicilio Transp')
    RETURNING cod_transportista INTO v_transp;

    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Malbec Vistas 1', 'tinto', 2021, 750, 14.00, 2500, v_cb)
    RETURNING cod_vino INTO v_vino1;

    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Chardonnay Vistas 2', 'blanco', 2022, 750, 12.50, 1800, v_cb)
    RETURNING cod_vino INTO v_vino2;

    -- Composición obligatoria por trigger RN-05
    INSERT INTO cepa (nombre, tipo) VALUES ('Cepa Vistas 1', 'tinta') RETURNING id_cepa INTO v_cant;
    INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje) VALUES (v_vino1, v_cant, 100);
    INSERT INTO cepa (nombre, tipo) VALUES ('Cepa Vistas 2', 'blanca') RETURNING id_cepa INTO v_cant;
    INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje) VALUES (v_vino2, v_cant, 100);

    -- -----------------------------------------------------------------
    -- 3. Prueba de vw_stock_total_vino
    -- -----------------------------------------------------------------
    -- Vino 1: 50 en depósito + 20 en sala 1 + 15 en sala 2 = 85 total
    INSERT INTO stock_deposito (cod_vino, cantidad) VALUES (v_vino1, 50);
    INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (v_sala1, v_vino1, 20);
    INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (v_sala2, v_vino1, 15);

    -- Vino 2: sin stock (debe dar 0 en todo gracias a COALESCE)
    SELECT stock_deposito, stock_salas, stock_total
      INTO v_dep, v_salas, v_tot
      FROM vw_stock_total_vino
     WHERE cod_vino = v_vino1;

    IF v_dep <> 50 OR v_salas <> 35 OR v_tot <> 85 THEN
        RAISE EXCEPTION 'FALLO vw_stock_total_vino para vino 1: esperado (50, 35, 85), obtenido (%, %, %)',
            v_dep, v_salas, v_tot;
    END IF;

    SELECT stock_deposito, stock_salas, stock_total
      INTO v_dep, v_salas, v_tot
      FROM vw_stock_total_vino
     WHERE cod_vino = v_vino2;

    IF v_dep <> 0 OR v_salas <> 0 OR v_tot <> 0 THEN
        RAISE EXCEPTION 'FALLO vw_stock_total_vino para vino 2: esperado (0, 0, 0), obtenido (%, %, %)',
            v_dep, v_salas, v_tot;
    END IF;

    RAISE NOTICE 'OK 2: vw_stock_total_vino calcula correctamente depositos, salas y ceros (COALESCE)';

    -- -----------------------------------------------------------------
    -- 4. Prueba de vw_documentos_pendientes
    -- -----------------------------------------------------------------
    -- Ingreso 1: en confección (debe aparecer) con 2 renglones (100 botellas)
    INSERT INTO ingreso (fecha, estado, cod_transportista, cuit_bodega)
    VALUES (CURRENT_DATE, 'en_confeccion', v_transp, v_cb)
    RETURNING cod_ingreso INTO v_ing1;

    INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad) VALUES (v_ing1, v_vino1, 60);
    INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad) VALUES (v_ing1, v_vino2, 40);

    -- Transferencia 1: terminada (debe aparecer) con 1 renglón (30 botellas)
    INSERT INTO transferencia (id_sala, estado)
    VALUES (v_sala1, 'en_confeccion')
    RETURNING nro_transferencia INTO v_tr1;

    INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
    VALUES (v_tr1, v_vino1, 30);

    UPDATE transferencia SET estado = 'terminado' WHERE nro_transferencia = v_tr1;

    -- Ingreso 2: procesado (NO debe aparecer)
    INSERT INTO ingreso (fecha, estado, cod_transportista, cuit_bodega)
    VALUES (CURRENT_DATE, 'en_confeccion', v_transp, v_cb)
    RETURNING cod_ingreso INTO v_ing2;
    UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = v_ing2;
    UPDATE ingreso SET estado = 'procesado' WHERE cod_ingreso = v_ing2;

    -- Verificamos que sólo aparezcan los 2 pendientes
    SELECT COUNT(*) INTO v_cant
      FROM vw_documentos_pendientes
     WHERE nro_documento IN (v_ing1, v_ing2, v_tr1);

    IF v_cant <> 2 THEN
        RAISE EXCEPTION 'FALLO vw_documentos_pendientes: se esperaban 2 documentos pendientes y hay %', v_cant;
    END IF;

    -- Verificamos totales del ingreso pendiente
    SELECT total_botellas, total_variedades
      INTO v_bot, v_cant
      FROM vw_documentos_pendientes
     WHERE tipo_documento = 'ingreso' AND nro_documento = v_ing1;

    IF v_bot <> 100 OR v_cant <> 2 THEN
        RAISE EXCEPTION 'FALLO vw_documentos_pendientes: ingreso esperado (100 botellas, 2 variedades), obtenido (%, %)',
            v_bot, v_cant;
    END IF;

    RAISE NOTICE 'OK 3: vw_documentos_pendientes filtra procesados y totaliza botellas y variedades';

    -- -----------------------------------------------------------------
    -- 5. Prueba de vw_ventas_mensuales_sala (VISTA MATERIALIZADA)
    -- -----------------------------------------------------------------
    -- Cliente socio (10% descuento según RN-06)
    INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento, nro_documento, direccion, codigo_postal, fecha_alta, tipo_cliente)
    VALUES ('Perez', 'Juan', 'DNI', '99887766', 'Calle Test 123', 'VIST0001', CURRENT_DATE, 'socio')
    RETURNING id_cliente INTO v_cli;

    -- Comprobante con 2 botellas de Vino 1 en Sala 1
    -- Vino 1: precio $2500, 10% desc = $2250 c/u -> Subtotal $5000, Total $4500
    INSERT INTO comprobante (fecha, id_cliente, id_sala, subtotal, descuento, total)
    VALUES (CURRENT_DATE, v_cli, v_sala1, 0, 0, 0)
    RETURNING nro_comprobante INTO v_comp;

    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento_pct, subtotal)
    VALUES (v_comp, v_vino1, 2, 0, 0, 0);

    -- Refrescamos la vista materializada para que absorba los nuevos datos
    REFRESH MATERIALIZED VIEW vw_ventas_mensuales_sala;

    SELECT cantidad_comprobantes, total_facturado, total_botellas_vendidas
      INTO v_cant, v_fact, v_bot
      FROM vw_ventas_mensuales_sala
     WHERE id_sala = v_sala1 AND periodo = TO_CHAR(CURRENT_DATE, 'YYYY-MM');

    IF v_cant < 1 OR v_fact <> 4500.00 OR v_bot <> 2 THEN
        RAISE EXCEPTION 'FALLO vw_ventas_mensuales_sala: esperado (1 comp, $4500.00, 2 botellas), obtenido (%, %, %)',
            v_cant, v_fact, v_bot;
    END IF;

    RAISE NOTICE 'OK 4: vw_ventas_mensuales_sala materializa y totaliza facturacion por sala y periodo';
END
$$;

ROLLBACK;

\echo '=== Pruebas de vistas terminadas sin errores (datos descartados) ==='
