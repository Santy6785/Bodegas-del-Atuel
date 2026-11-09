-- =====================================================================
-- test_sp_crear_comprobante.sql
-- Bodegas del Atuel - Pruebas de sp_crear_comprobante (004_procedimientos.sql).
--
-- Cubre:
--   Venta valida de uno y dos renglones: crea cabecera y renglones,
--   precio_unitario y descuento_pct no nulos, total coincide con la suma
--   de subtotales, el stock de sala baja en la cantidad vendida.
--   Venta con stock insuficiente en un renglón: falla con P0001 y mensaje
--   que contiene RN-09; no queda comprobante ni renglones (atomicidad).
--   Arreglos de distinta longitud: falla con P0001.
--   Arreglos vacíos o NULL: falla con P0001.
--   Venta de un vino inexistente: falla con 23503 (FK).
--
-- Crea sus propios datos (localidad, CUIT, bodega, sala, cepa, vinos,
-- stock de sala, cliente) y TODO se descarta al final con ROLLBACK.
-- Si alguna prueba falla, el script se detiene con un error FALLO.
--
-- Requisitos: base migrada (001 a 007). sp_crear_comprobante definido en 004.
-- Triggers de 005 requeridos (trg_renglon_comprobante_antes/despues).
--
-- Uso (desde la raiz del proyecto):
--   Git Bash / Linux / Mac:
--     docker compose exec -T db psql -U <POSTGRES_USER> -d <POSTGRES_DB> < db/test/test_sp_crear_comprobante.sql
--   PowerShell:
--     Get-Content db/test/test_sp_crear_comprobante.sql | docker compose exec -T db psql -U <POSTGRES_USER> -d <POSTGRES_DB>
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    v_cuit_bodega cuit_dom := '99999999991';
    v_sala        INTEGER;
    v_vino1       INTEGER;
    v_vino2       INTEGER;
    v_cliente     INTEGER;
    v_nro         INTEGER;      -- parametro INOUT de sp_crear_comprobante
    v_ok          BOOLEAN;
    v_msg         TEXT;
    v_n           INTEGER;
    v_total       NUMERIC;
    v_stock_ini   INTEGER;
    v_stock_fin   INTEGER;
BEGIN
    -- ---------------- Datos de prueba ----------------
    INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
    VALUES ('TESTCC01', 'Localidad Test CC', 'Mendoza', 'Encargado Test');

    INSERT INTO bodega (cuit, razon_social, domicilio)
    VALUES (v_cuit_bodega, 'Bodega Test CC', 'Domicilio Test');

    INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal)
    VALUES ('Calle Test CC', '1', 'lunes', 'TESTCC01')
    RETURNING id_sala INTO v_sala;

    INSERT INTO cepa (nombre, tipo) VALUES ('Cepa Test CC', 'tinta');

    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Vino Test CC 1', 'tinto', 2021, 750, 14.0, 10000.00, v_cuit_bodega)
    RETURNING cod_vino INTO v_vino1;

    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Vino Test CC 2', 'tinto', 2021, 750, 14.0, 10000.00, v_cuit_bodega)
    RETURNING cod_vino INTO v_vino2;

    INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
    SELECT v_vino1, id_cepa, 100 FROM cepa WHERE nombre = 'Cepa Test CC';
    INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
    SELECT v_vino2, id_cepa, 100 FROM cepa WHERE nombre = 'Cepa Test CC';

    INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento,
                         nro_documento, direccion, codigo_postal,
                         fecha_alta, tipo_cliente)
    VALUES ('Cliente Test CC', 'Cliente', 'CUIT', '99999999991', 'Dir Test',
            'TESTCC01', CURRENT_DATE, 'socio')
    RETURNING id_cliente INTO v_cliente;

    -- Stock de sala: 10 botellas de vino 1, 2 de vino 2.
    INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
    VALUES (v_sala, v_vino1, 10);
    INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
    VALUES (v_sala, v_vino2, 2);

    -- ============ PRUEBA 1: venta valida de un renglon ============
    CALL sp_crear_comprobante(v_cliente, v_sala, ARRAY[v_vino1], ARRAY[3], v_nro);
    IF v_nro IS NULL THEN
        RAISE EXCEPTION 'FALLO 1: sp_crear_comprobante no devolvio nro_comprobante';
    END IF;

    SELECT cantidad INTO v_stock_fin FROM stock_sala WHERE id_sala = v_sala AND cod_vino = v_vino1;
    IF v_stock_fin IS DISTINCT FROM 7 THEN
        RAISE EXCEPTION 'FALLO 1: stock de sala del vino 1 deveria ser 7 (10-3) y es %', v_stock_fin;
    END IF;

    SELECT count(*) INTO v_n FROM renglon_comprobante WHERE nro_comprobante = v_nro;
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'FALLO 1: deberia haber 1 renglon y hay %', v_n;
    END IF;

    SELECT precio_unitario INTO v_n FROM renglon_comprobante WHERE nro_comprobante = v_nro;
    IF v_n IS NULL THEN
        RAISE EXCEPTION 'FALLO 1: precio_unitario no nulo esperado (trigger lo completa)';
    END IF;

    SELECT descuento_pct INTO v_n FROM renglon_comprobante WHERE nro_comprobante = v_nro;
    IF v_n IS NULL THEN
        RAISE EXCEPTION 'FALLO 1: descuento_pct no nulo esperado (trigger lo completa)';
    END IF;

    SELECT subtotal INTO v_total FROM renglon_comprobante WHERE nro_comprobante = v_nro;
    IF v_total IS NULL OR v_total = 0 THEN
        RAISE EXCEPTION 'FALLO 1: subtotal no nulo ni cero esperado (trigger lo calcula)';
    END IF;

    SELECT total INTO v_total FROM comprobante WHERE nro_comprobante = v_nro;
    IF v_total IS NULL OR v_total = 0 THEN
        RAISE EXCEPTION 'FALLO 1: total del comprobante no nulo ni cero esperado';
    END IF;

    RAISE NOTICE 'OK 1: venta valida de un renglon, comprobante %, stock sala = 7', v_nro;

    -- ============ PRUEBA 2: venta valida de dos renglones ============
    CALL sp_crear_comprobante(v_cliente, v_sala, ARRAY[v_vino1, v_vino2], ARRAY[2, 1], v_nro);

    SELECT count(*) INTO v_n FROM renglon_comprobante WHERE nro_comprobante = v_nro;
    IF v_n <> 2 THEN
        RAISE EXCEPTION 'FALLO 2: deberia haber 2 renglones y hay %', v_n;
    END IF;

    SELECT cantidad INTO v_stock_fin FROM stock_sala WHERE id_sala = v_sala AND cod_vino = v_vino1;
    IF v_stock_fin IS DISTINCT FROM 5 THEN
        RAISE EXCEPTION 'FALLO 2: stock de sala del vino 1 deveria ser 5 (7-2) y es %', v_stock_fin;
    END IF;

    SELECT cantidad INTO v_stock_fin FROM stock_sala WHERE id_sala = v_sala AND cod_vino = v_vino2;
    IF v_stock_fin IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'FALLO 2: stock de sala del vino 2 deveria ser 1 (2-1) y es %', v_stock_fin;
    END IF;

    RAISE NOTICE 'OK 2: venta valida de dos renglones, comprobante %', v_nro;

    -- ============ PRUEBA 3: stock insuficiente en un renglon -> P0001 RN-09, atomicidad ============
    -- stock de sala vino 2 = 1, pedimos 5: debe fallar.
    v_ok := false;
    BEGIN
        CALL sp_crear_comprobante(v_cliente, v_sala, ARRAY[v_vino1, v_vino2], ARRAY[1, 5], v_nro);
        v_ok := true;
    EXCEPTION WHEN raise_exception THEN
        v_msg := SQLERRM;
    END;
    IF v_ok THEN
        RAISE EXCEPTION 'FALLO 3: se proceso una venta con stock insuficiente en sala';
    END IF;
    IF v_msg NOT LIKE '%RN-09%' THEN
        RAISE EXCEPTION 'FALLO 3: el mensaje no contiene RN-09: %', v_msg;
    END IF;

    -- Atomicidad: no quedo comprobante ni renglones para este intento.
    SELECT count(*) INTO v_n FROM comprobante WHERE nro_comprobante > v_nro;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'FALLO 3: queda un comprobante despues de una venta rechazada (no hay atomicidad)';
    END IF;

    SELECT count(*) INTO v_n FROM renglon_comprobante rc
    JOIN comprobante c ON c.nro_comprobante = rc.nro_comprobante
    WHERE c.nro_comprobante > v_nro;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'FALLO 3: quedan renglones huérfanos despues de una venta rechazada';
    END IF;

    RAISE NOTICE 'OK 3: stock insuficiente rechazado con P0001/RN-09 y atomicidad -> %', v_msg;

    -- ============ PRUEBA 4: arreglos de distinta longitud -> P0001 ============
    v_ok := false;
    BEGIN
        CALL sp_crear_comprobante(v_cliente, v_sala, ARRAY[v_vino1], ARRAY[1, 2], v_nro);
        v_ok := true;
    EXCEPTION WHEN raise_exception THEN
        v_msg := SQLERRM;
    END;
    IF v_ok THEN
        RAISE EXCEPTION 'FALLO 4: se proceso una venta con arreglos de distinta longitud';
    END IF;
    RAISE NOTICE 'OK 4: arreglos de distinta longitud rechazados -> %', v_msg;

    -- ============ PRUEBA 5: arreglos vacios o NULL -> P0001 ============
    v_ok := false;
    BEGIN
        CALL sp_crear_comprobante(v_cliente, v_sala, ARRAY[]::INTEGER[], ARRAY[]::INTEGER[], v_nro);
        v_ok := true;
    EXCEPTION WHEN raise_exception THEN
        v_msg := SQLERRM;
    END;
    IF v_ok THEN
        RAISE EXCEPTION 'FALLO 5a: se proceso una venta con arreglos vacios';
    END IF;
    RAISE NOTICE 'OK 5a: arreglos vacios rechazados -> %', v_msg;

    v_ok := false;
    BEGIN
        CALL sp_crear_comprobante(v_cliente, v_sala, NULL, ARRAY[1], v_nro);
        v_ok := true;
    EXCEPTION WHEN raise_exception THEN
        v_msg := SQLERRM;
    END;
    IF v_ok THEN
        RAISE EXCEPTION 'FALLO 5b: se proceso una venta con arreglo de vinos NULL';
    END IF;
    RAISE NOTICE 'OK 5b: arreglo de vinos NULL rechazado -> %', v_msg;

    -- ============ PRUEBA 6: vino inexistente -> 23503 ============
    v_ok := false;
    BEGIN
        CALL sp_crear_comprobante(v_cliente, v_sala, ARRAY[999999], ARRAY[1], v_nro);
        v_ok := true;
    EXCEPTION WHEN foreign_key_violation THEN
        v_msg := SQLERRM;
    END;
    IF v_ok THEN
        RAISE EXCEPTION 'FALLO 6: se esperaba 23503 para vino inexistente pero no se obtuvo error';
    END IF;
    RAISE NOTICE 'OK 6: vino inexistente rechazado con 23503 -> %', v_msg;

    RAISE NOTICE '=== Todas las pruebas de sp_crear_comprobante pasaron ===';
END
$$;

-- Descartar todos los datos de prueba.
ROLLBACK;

\echo '=== Pruebas de sp_crear_comprobante terminadas sin errores (datos descartados) ==='
