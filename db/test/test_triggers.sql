-- =====================================================================
-- test_triggers.sql
-- Bodegas del Atuel - Pruebas de los triggers de 005_triggers.sql.
--
-- Cubre un caso que debe funcionar y uno que debe fallar para:
--   RN-05  suma de porcentajes de corte = 100 (constraint trigger diferido)
--   RN-06  descuento segun el tipo de cliente (snapshot en el renglon)
--   RN-08  subtotal del renglon y total del comprobante
--   RN-09  stock insuficiente en la venta y descuento de stock
--   RN-10  estados de ingreso (sin saltos ni retrocesos)
--   RN-11  estados de transferencia y fecha de confeccion inmodificable
--   RN-12  renglones bloqueados fuera de confeccion
--   RN-13  auditoria de cambios de precio
--   Trazabilidad: el lote debe ser de la bodega del vino
--   Jerarquia de clientes: tipo_cliente coherente con el subtipo
--
-- Crea sus propios datos (localidad TEST0001, CUIT 9999999999x, "Vino Test")
-- y TODO se descarta al final con ROLLBACK.
-- Si alguna prueba falla, el script se detiene con un error FALLO.
--
-- Requisitos: base migrada (001 a 007) con 005_triggers.sql aplicado.
--
-- Uso (desde la raiz del proyecto):
--   Git Bash / Linux / Mac:
--     docker compose exec -T db psql -U <POSTGRES_USER> -d <POSTGRES_DB> < db/test/test_triggers.sql
--   PowerShell:
--     Get-Content db/test/test_triggers.sql | docker compose exec -T db psql -U <POSTGRES_USER> -d <POSTGRES_DB>
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- Ayuda: ejecuta una o varias sentencias y exige que fallen con un mensaje
-- que cumpla el patron LIKE. Si no fallan, o fallan por otra causa, aborta.
-- Todo lo que hizo la sentencia fallida se revierte (subtransaccion).
CREATE FUNCTION pg_temp.esperar_error(p_sql TEXT, p_patron TEXT)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM NOT LIKE p_patron THEN
            RAISE EXCEPTION 'FALLO: error inesperado: % (se esperaba algo como %)', SQLERRM, p_patron;
        END IF;
        RAISE NOTICE 'OK: rechazado -> %', SQLERRM;
        RETURN;
    END;
    RAISE EXCEPTION 'FALLO: la sentencia no fallo: %', p_sql;
END;
$$;

DO $$
DECLARE
    v_cb1    cuit_dom := '99999999991';   -- bodega del vino
    v_cb2    cuit_dom := '99999999993';   -- otra bodega
    v_ct     cuit_dom := '99999999992';   -- transportista
    v_sala   INTEGER;
    v_transp INTEGER;
    v_cepa   INTEGER;
    v_vino1  INTEGER;
    v_cli    INTEGER;
    v_c1     INTEGER;
    v_c2     INTEGER;
    v_tr     INTEGER;
    v_ing    INTEGER;
    v_dep    INTEGER;
    v_finca  INTEGER;
    v_lote1  INTEGER;
    v_lote2  INTEGER;
    v_n      NUMERIC;
    v_a      NUMERIC;
    v_b      NUMERIC;
    v_fecha  DATE;
BEGIN
    -- ---------------- Datos de prueba ----------------
    INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
    VALUES ('TEST0001', 'Localidad Test', 'Mendoza', 'Encargado Test');

    INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal)
    VALUES ('Calle Test', '1', 'lunes', 'TEST0001')
    RETURNING id_sala INTO v_sala;

    INSERT INTO bodega (cuit, razon_social, domicilio) VALUES
        (v_cb1, 'Bodega Test 1', 'Domicilio Test'),
        (v_cb2, 'Bodega Test 2', 'Domicilio Test');

    INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio)
    VALUES ('Transporte Test', v_ct, 'test@test.com', '000', 'Domicilio Test')
    RETURNING cod_transportista INTO v_transp;

    INSERT INTO cepa (nombre, tipo) VALUES ('Cepa Test 005', 'tinta')
    RETURNING id_cepa INTO v_cepa;

    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Vino Test T1', 'tinto', 2020, 750, 13.50, 1000, v_cb1)
    RETURNING cod_vino INTO v_vino1;

    INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje) VALUES (v_vino1, v_cepa, 100);

    -- Cliente distribuidor (20 % de descuento) con su subtipo.
    INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento, nro_documento,
                         direccion, codigo_postal, tipo_cliente)
    VALUES ('Test', 'Distribuidor', 'CUIT', '99000001', 'Dir Test', 'TEST0001', 'distribuidor')
    RETURNING id_cliente INTO v_cli;

    INSERT INTO cliente_distribuidor (id_cliente, zona_cobertura, nro_habilitacion)
    VALUES (v_cli, 'Zona Test', 'HAB-TEST-1');

    INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (v_sala, v_vino1, 10);

    -- Los triggers diferidos se evaluan aca: la composicion del vino (100 %)
    -- y el cliente con su subtipo son validos.
    SET CONSTRAINTS ALL IMMEDIATE;
    SET CONSTRAINTS ALL DEFERRED;
    RAISE NOTICE 'OK RN-05: vino con composicion 100 y cliente distribuidor coherente aceptados';

    -- ============ RN-05: suma de porcentajes ============
    PERFORM pg_temp.esperar_error(
        format($q$
            WITH v AS (
                INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
                VALUES ('Vino Test T2', 'tinto', 2020, 750, 13.50, 1000, %L)
                RETURNING cod_vino)
            INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
            SELECT cod_vino, %s, 60 FROM v;
            SET CONSTRAINTS ALL IMMEDIATE
        $q$, v_cb1, v_cepa),
        '%RN-05%');
    SET CONSTRAINTS ALL DEFERRED;

    -- ============ RN-06, RN-08, RN-09: venta ============
    INSERT INTO comprobante (id_cliente, id_sala) VALUES (v_cli, v_sala)
    RETURNING nro_comprobante INTO v_c1;

    -- La API solo envia (comprobante, vino, cantidad): precio, descuento y
    -- subtotal los pone el trigger.
    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
    VALUES (v_c1, v_vino1, 4);

    SELECT r.precio_unitario, r.descuento_pct, r.subtotal INTO v_n, v_a, v_b
      FROM renglon_comprobante r
     WHERE r.nro_comprobante = v_c1 AND r.cod_vino = v_vino1;
    IF v_n IS DISTINCT FROM 1000 OR v_a IS DISTINCT FROM 20 OR v_b IS DISTINCT FROM 3200 THEN
        RAISE EXCEPTION 'FALLO RN-06/RN-08: renglon con precio %, descuento %, subtotal % (esperado 1000, 20, 3200)', v_n, v_a, v_b;
    END IF;
    RAISE NOTICE 'OK RN-06/RN-08: renglon con precio 1000, descuento 20, subtotal 3200';

    SELECT c.subtotal, c.descuento, c.total INTO v_n, v_a, v_b
      FROM comprobante c WHERE c.nro_comprobante = v_c1;
    IF v_n IS DISTINCT FROM 4000 OR v_a IS DISTINCT FROM 800 OR v_b IS DISTINCT FROM 3200 THEN
        RAISE EXCEPTION 'FALLO RN-08: cabecera con subtotal %, descuento %, total % (esperado 4000, 800, 3200)', v_n, v_a, v_b;
    END IF;
    RAISE NOTICE 'OK RN-08: cabecera recalculada (subtotal 4000, descuento 800, total 3200)';

    SELECT s.cantidad INTO v_n FROM stock_sala s WHERE s.id_sala = v_sala AND s.cod_vino = v_vino1;
    IF v_n IS DISTINCT FROM 6 THEN
        RAISE EXCEPTION 'FALLO RN-09: el stock de la sala deberia ser 6 y es %', v_n;
    END IF;
    RAISE NOTICE 'OK RN-09: stock de la sala descontado (10 -> 6)';

    -- Venta con stock insuficiente: 7 > 6.
    INSERT INTO comprobante (id_cliente, id_sala) VALUES (v_cli, v_sala)
    RETURNING nro_comprobante INTO v_c2;

    PERFORM pg_temp.esperar_error(
        format('INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (%s, %s, 7)',
               v_c2, v_vino1),
        'Stock insuficiente%RN-09%');

    SELECT s.cantidad INTO v_n FROM stock_sala s WHERE s.id_sala = v_sala AND s.cod_vino = v_vino1;
    IF v_n IS DISTINCT FROM 6 THEN
        RAISE EXCEPTION 'FALLO RN-09: la venta rechazada cambio el stock a %', v_n;
    END IF;

    -- ============ RN-11: transferencia ============
    -- La fecha se fuerza a la actual aunque se envie otra.
    INSERT INTO transferencia (id_sala, fecha_confeccion) VALUES (v_sala, DATE '2000-01-01')
    RETURNING nro_transferencia INTO v_tr;

    SELECT t.fecha_confeccion INTO v_fecha FROM transferencia t WHERE t.nro_transferencia = v_tr;
    IF v_fecha <> CURRENT_DATE THEN
        RAISE EXCEPTION 'FALLO RN-11: la fecha de confeccion es % y deberia ser la actual', v_fecha;
    END IF;
    RAISE NOTICE 'OK RN-11: fecha de confeccion forzada a la actual';

    -- Saltear un estado.
    PERFORM pg_temp.esperar_error(
        format('UPDATE transferencia SET estado = ''procesado'' WHERE nro_transferencia = %s', v_tr),
        '%RN-11%');

    UPDATE transferencia SET estado = 'terminado' WHERE nro_transferencia = v_tr;
    RAISE NOTICE 'OK RN-11: transicion en_confeccion -> terminado permitida';

    -- Retroceder.
    PERFORM pg_temp.esperar_error(
        format('UPDATE transferencia SET estado = ''en_confeccion'' WHERE nro_transferencia = %s', v_tr),
        '%RN-11%');

    -- Modificar la fecha.
    PERFORM pg_temp.esperar_error(
        format('UPDATE transferencia SET fecha_confeccion = DATE ''2001-01-01'' WHERE nro_transferencia = %s', v_tr),
        '%RN-11%');

    -- ============ RN-12: renglones fuera de confeccion ============
    PERFORM pg_temp.esperar_error(
        format('INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad) VALUES (%s, %s, 5)',
               v_tr, v_vino1),
        '%RN-12%');

    -- ============ RN-10 y RN-12: ingreso ============
    INSERT INTO ingreso (fecha, cod_transportista, cuit_bodega)
    VALUES (CURRENT_DATE, v_transp, v_cb1)
    RETURNING cod_ingreso INTO v_ing;

    PERFORM pg_temp.esperar_error(
        format('UPDATE ingreso SET estado = ''procesado'' WHERE cod_ingreso = %s', v_ing),
        '%RN-10%');

    UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = v_ing;
    RAISE NOTICE 'OK RN-10: transicion en_confeccion -> terminado permitida';

    PERFORM pg_temp.esperar_error(
        format('INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad) VALUES (%s, %s, 10)',
               v_ing, v_vino1),
        '%RN-12%');

    -- ============ RN-13: auditoria de precio ============
    UPDATE vino SET precio = 1500 WHERE cod_vino = v_vino1;
    UPDATE vino SET precio = 1500 WHERE cod_vino = v_vino1;   -- mismo precio: no audita

    SELECT count(*) INTO v_n FROM auditoria_precio a WHERE a.cod_vino = v_vino1;
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'FALLO RN-13: se esperaba 1 registro de auditoria y hay %', v_n;
    END IF;
    SELECT count(*) INTO v_n
      FROM auditoria_precio a
     WHERE a.cod_vino = v_vino1 AND a.precio_anterior = 1000 AND a.precio_nuevo = 1500
       AND a.usuario = current_user;
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'FALLO RN-13: el registro de auditoria no tiene precio anterior 1000, nuevo 1500 y el usuario actual';
    END IF;
    RAISE NOTICE 'OK RN-13: cambio de precio auditado (1000 -> 1500); un UPDATE sin cambio no audita';

    -- ============ Jerarquia de clientes ============
    PERFORM pg_temp.esperar_error(
        $q$
            INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento, nro_documento,
                                 direccion, codigo_postal, tipo_cliente)
            VALUES ('Test', 'Exportador', 'CUIT', '99000002', 'Dir Test', 'TEST0001', 'exportador');
            SET CONSTRAINTS ALL IMMEDIATE
        $q$,
        '%tipo de cliente%');
    SET CONSTRAINTS ALL DEFERRED;

    -- ============ Trazabilidad: lote y bodega ============
    INSERT INTO departamento (nombre, provincia) VALUES ('Depto Test', 'Prov Test')
    RETURNING id_departamento INTO v_dep;

    INSERT INTO finca (nombre, superficie_ha, id_departamento) VALUES ('Finca Test', 10, v_dep)
    RETURNING id_finca INTO v_finca;

    INSERT INTO parcela (id_finca, nro_parcela, superficie_ha, anio_plantacion, id_cepa)
    VALUES (v_finca, 1, 5, 2010, v_cepa);

    -- Lote entregado a OTRA bodega.
    INSERT INTO lote_uva (id_finca, nro_parcela, campania, nro_lote, fecha_cosecha, kilos, cuit_bodega)
    VALUES (v_finca, 1, 2023, 99000001, DATE '2023-03-01', 1000, v_cb2)
    RETURNING id_lote INTO v_lote1;

    -- Lote entregado a la bodega del vino.
    INSERT INTO lote_uva (id_finca, nro_parcela, campania, nro_lote, fecha_cosecha, kilos, cuit_bodega)
    VALUES (v_finca, 1, 2024, 99000002, DATE '2024-03-01', 1000, v_cb1)
    RETURNING id_lote INTO v_lote2;

    PERFORM pg_temp.esperar_error(
        format('INSERT INTO vino_lote (cod_vino, id_lote) VALUES (%s, %s)', v_vino1, v_lote1),
        '%bodega%');

    INSERT INTO vino_lote (cod_vino, id_lote) VALUES (v_vino1, v_lote2);
    RAISE NOTICE 'OK trazabilidad: lote de la misma bodega aceptado';

    -- Ultima verificacion: nada diferido quedo pendiente con error.
    SET CONSTRAINTS ALL IMMEDIATE;
    RAISE NOTICE 'OK: no quedaron restricciones diferidas pendientes con error';
END
$$;

-- Descartar todos los datos de prueba.
ROLLBACK;

\echo '=== Pruebas de triggers terminadas sin errores (datos descartados) ==='
