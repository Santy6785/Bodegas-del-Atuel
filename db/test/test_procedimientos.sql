-- =====================================================================
-- test_procedimientos.sql
-- Bodegas del Atuel - Pruebas de sp_procesar_ingreso y
-- sp_procesar_transferencia (004_procedimientos.sql).
--
-- Cubre:
--   RN-10  un ingreso solo se procesa si esta terminado.
--   RN-11  una transferencia solo se procesa si esta terminada.
--   RN-09  no se procesa con stock insuficiente en el deposito, incluido
--          un vino SIN FILA en stock_deposito (problema del Anexo A.6).
--   Todo o nada: un procesamiento rechazado no deja cambios a medias.
--
-- Crea sus propios datos (localidad TEST0001, CUIT 9999999999x, vinos
-- "Vino Test SP") y TODO se descarta al final con ROLLBACK.
-- Si alguna prueba falla, el script se detiene con un error FALLO.
--
-- Requisitos: base migrada (001 a 007). Funciona con o sin los triggers de 005.
--
-- Uso (desde la raiz del proyecto):
--   Git Bash / Linux / Mac:
--     docker compose exec -T db psql -U <POSTGRES_USER> -d <POSTGRES_DB> < db/test/test_procedimientos.sql
--   PowerShell:
--     Get-Content db/test/test_procedimientos.sql | docker compose exec -T db psql -U <POSTGRES_USER> -d <POSTGRES_DB>
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    v_cuit_bodega cuit_dom := '99999999991';
    v_cuit_transp cuit_dom := '99999999992';
    v_sala        INTEGER;
    v_transp      INTEGER;
    v_vino1       INTEGER;
    v_vino2       INTEGER;
    v_ing         INTEGER;
    v_t1          INTEGER;
    v_t2          INTEGER;
    v_t3          INTEGER;
    v_ok          BOOLEAN;
    v_msg         TEXT;
    v_n           INTEGER;
    v_estado      estado_documento;
BEGIN
    -- ---------------- Datos de prueba ----------------
    INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
    VALUES ('TEST0001', 'Localidad Test', 'Mendoza', 'Encargado Test');

    INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal)
    VALUES ('Calle Test', '1', 'lunes', 'TEST0001')
    RETURNING id_sala INTO v_sala;

    INSERT INTO bodega (cuit, razon_social, domicilio)
    VALUES (v_cuit_bodega, 'Bodega Test', 'Domicilio Test');

    INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio)
    VALUES ('Transporte Test', v_cuit_transp, 'test@test.com', '000', 'Domicilio Test')
    RETURNING cod_transportista INTO v_transp;

    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Vino Test SP 1', 'tinto', 2020, 750, 13.50, 1000, v_cuit_bodega)
    RETURNING cod_vino INTO v_vino1;

    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Vino Test SP 2', 'tinto', 2020, 750, 13.50, 1000, v_cuit_bodega)
    RETURNING cod_vino INTO v_vino2;

    -- ============ INGRESO ============
    INSERT INTO ingreso (fecha, cod_transportista, cuit_bodega)
    VALUES (CURRENT_DATE, v_transp, v_cuit_bodega)
    RETURNING cod_ingreso INTO v_ing;

    INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
    VALUES (v_ing, v_vino1, 100);

    -- 1. Procesar un ingreso en confeccion se rechaza (RN-10).
    v_ok := false;
    BEGIN
        CALL sp_procesar_ingreso(v_ing);
        v_ok := true;
    EXCEPTION WHEN raise_exception THEN
        v_msg := SQLERRM;
    END;
    IF v_ok THEN
        RAISE EXCEPTION 'FALLO 1: se proceso un ingreso en confeccion';
    END IF;
    RAISE NOTICE 'OK 1: ingreso en confeccion rechazado -> %', v_msg;

    -- 2. Ingreso terminado: se procesa. El vino no tenia fila en
    --    stock_deposito: el procedimiento la crea con 100.
    UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = v_ing;
    CALL sp_procesar_ingreso(v_ing);

    SELECT cantidad INTO v_n FROM stock_deposito WHERE cod_vino = v_vino1;
    IF v_n IS DISTINCT FROM 100 THEN
        RAISE EXCEPTION 'FALLO 2: stock_deposito del vino 1 deberia ser 100 y es %', v_n;
    END IF;
    SELECT estado INTO v_estado FROM ingreso WHERE cod_ingreso = v_ing;
    IF v_estado <> 'procesado' THEN
        RAISE EXCEPTION 'FALLO 2: el ingreso deberia estar procesado y esta %', v_estado;
    END IF;
    RAISE NOTICE 'OK 2: ingreso procesado, deposito = 100, estado = procesado';

    -- 3. Reprocesar el mismo ingreso se rechaza.
    v_ok := false;
    BEGIN
        CALL sp_procesar_ingreso(v_ing);
        v_ok := true;
    EXCEPTION WHEN raise_exception THEN
        v_msg := SQLERRM;
    END;
    IF v_ok THEN
        RAISE EXCEPTION 'FALLO 3: se reproceso un ingreso ya procesado';
    END IF;
    RAISE NOTICE 'OK 3: ingreso ya procesado rechazado -> %', v_msg;

    -- ============ TRANSFERENCIA ============
    -- 4. Transferencia valida: 30 botellas del vino 1 (deposito tiene 100).
    INSERT INTO transferencia (id_sala) VALUES (v_sala)
    RETURNING nro_transferencia INTO v_t1;

    INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
    VALUES (v_t1, v_vino1, 30);

    -- 4a. Sin terminar se rechaza (RN-11).
    v_ok := false;
    BEGIN
        CALL sp_procesar_transferencia(v_t1);
        v_ok := true;
    EXCEPTION WHEN raise_exception THEN
        v_msg := SQLERRM;
    END;
    IF v_ok THEN
        RAISE EXCEPTION 'FALLO 4a: se proceso una transferencia en confeccion';
    END IF;
    RAISE NOTICE 'OK 4a: transferencia en confeccion rechazada -> %', v_msg;

    -- 4b. Terminada se procesa: deposito 100 -> 70, sala 0 -> 30.
    UPDATE transferencia SET estado = 'terminado' WHERE nro_transferencia = v_t1;
    CALL sp_procesar_transferencia(v_t1);

    SELECT cantidad INTO v_n FROM stock_deposito WHERE cod_vino = v_vino1;
    IF v_n IS DISTINCT FROM 70 THEN
        RAISE EXCEPTION 'FALLO 4b: deposito deberia ser 70 y es %', v_n;
    END IF;
    SELECT cantidad INTO v_n FROM stock_sala WHERE id_sala = v_sala AND cod_vino = v_vino1;
    IF v_n IS DISTINCT FROM 30 THEN
        RAISE EXCEPTION 'FALLO 4b: stock de la sala deberia ser 30 y es %', v_n;
    END IF;
    SELECT estado INTO v_estado FROM transferencia WHERE nro_transferencia = v_t1;
    IF v_estado <> 'procesado' THEN
        RAISE EXCEPTION 'FALLO 4b: la transferencia deberia estar procesada y esta %', v_estado;
    END IF;
    RAISE NOTICE 'OK 4b: transferencia procesada, deposito = 70, sala = 30';

    -- 5. Vino SIN FILA en stock_deposito (problema del Anexo A.6): debe fallar.
    INSERT INTO transferencia (id_sala) VALUES (v_sala)
    RETURNING nro_transferencia INTO v_t2;

    INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
    VALUES (v_t2, v_vino2, 5);
    UPDATE transferencia SET estado = 'terminado' WHERE nro_transferencia = v_t2;

    v_ok := false;
    BEGIN
        CALL sp_procesar_transferencia(v_t2);
        v_ok := true;
    EXCEPTION WHEN raise_exception THEN
        v_msg := SQLERRM;
    END;
    IF v_ok THEN
        RAISE EXCEPTION 'FALLO 5: se proceso una transferencia de un vino sin fila en stock_deposito';
    END IF;
    IF v_msg NOT LIKE 'Stock insuficiente%' THEN
        RAISE EXCEPTION 'FALLO 5: el mensaje no es de stock insuficiente: %', v_msg;
    END IF;
    SELECT estado INTO v_estado FROM transferencia WHERE nro_transferencia = v_t2;
    IF v_estado <> 'terminado' THEN
        RAISE EXCEPTION 'FALLO 5: la transferencia rechazada cambio de estado a %', v_estado;
    END IF;
    SELECT count(*) INTO v_n FROM stock_sala WHERE id_sala = v_sala AND cod_vino = v_vino2;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'FALLO 5: la sala recibio botellas que el deposito no tenia';
    END IF;
    RAISE NOTICE 'OK 5: vino sin fila en deposito rechazado -> %', v_msg;

    -- 6. Todo o nada: un renglon valido (vino 1, 10 botellas) y otro invalido
    --    (vino 2, sin stock). Se rechaza y el renglon valido NO se descuenta.
    INSERT INTO transferencia (id_sala) VALUES (v_sala)
    RETURNING nro_transferencia INTO v_t3;

    INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
    VALUES (v_t3, v_vino1, 10), (v_t3, v_vino2, 5);
    UPDATE transferencia SET estado = 'terminado' WHERE nro_transferencia = v_t3;

    v_ok := false;
    BEGIN
        CALL sp_procesar_transferencia(v_t3);
        v_ok := true;
    EXCEPTION WHEN raise_exception THEN
        v_msg := SQLERRM;
    END;
    IF v_ok THEN
        RAISE EXCEPTION 'FALLO 6: se proceso una transferencia con un renglon sin stock';
    END IF;

    SELECT cantidad INTO v_n FROM stock_deposito WHERE cod_vino = v_vino1;
    IF v_n IS DISTINCT FROM 70 THEN
        RAISE EXCEPTION 'FALLO 6: el deposito deberia seguir en 70 y esta en %', v_n;
    END IF;
    SELECT cantidad INTO v_n FROM stock_sala WHERE id_sala = v_sala AND cod_vino = v_vino1;
    IF v_n IS DISTINCT FROM 30 THEN
        RAISE EXCEPTION 'FALLO 6: la sala deberia seguir en 30 y esta en %', v_n;
    END IF;
    RAISE NOTICE 'OK 6: rechazo sin cambios a medias (deposito = 70, sala = 30) -> %', v_msg;

    -- 7. Reprocesar una transferencia ya procesada se rechaza.
    v_ok := false;
    BEGIN
        CALL sp_procesar_transferencia(v_t1);
        v_ok := true;
    EXCEPTION WHEN raise_exception THEN
        v_msg := SQLERRM;
    END;
    IF v_ok THEN
        RAISE EXCEPTION 'FALLO 7: se reproceso una transferencia ya procesada';
    END IF;
    RAISE NOTICE 'OK 7: transferencia ya procesada rechazada -> %', v_msg;
END
$$;

-- Descartar todos los datos de prueba.
ROLLBACK;

\echo '=== Pruebas de procedimientos terminadas sin errores (datos descartados) ==='