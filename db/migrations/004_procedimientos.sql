-- =====================================================================
-- 004_procedimientos.sql
-- Bodegas del Atuel - Procedimientos transaccionales
--
-- Contiene 2 procedimientos:
--   sp_procesar_ingreso(cod_ingreso)     RN-10, RN-12
--   sp_procesar_transferencia(nro)       RN-09, RN-11, RN-12
--
-- Ambos hacen lo mismo, en este orden:
--   1. Bloquean la cabecera con SELECT ... FOR UPDATE (nadie mas puede
--      procesarla ni modificarla mientras dura la transaccion).
--   2. Validan que exista y que su estado sea 'terminado'.
--   3. Validan que tenga renglones.
--   4. (solo transferencia) Bloquean y VERIFICAN el stock del deposito
--      antes de tocar nada.
--   5. Modifican los stocks.
--   6. Pasan el documento a 'procesado'.
--
-- TRANSACCION: un procedimiento corre dentro de la transaccion del que lo
-- llama (psql, API). NO llevan COMMIT ni ROLLBACK propios: si cualquier
-- paso falla, el RAISE EXCEPTION revierte TODO lo hecho y no queda nada a
-- medias. La API debe llamarlos con CALL dentro de su transaccion.
--
-- ERRORES: las reglas rechazadas usan RAISE EXCEPTION (SQLSTATE P0001),
-- que la API traduce a 409 Conflict con el mensaje tal cual.
--
-- ORDEN DE BLOQUEOS: siempre cabecera, luego stock_deposito y luego
-- stock_sala, y dentro de cada tabla ordenado por cod_vino. Un orden fijo
-- evita deadlocks entre dos procesos concurrentes.
--
-- Se ejecuta despues de 001, 002 y 003. Es idempotente (CREATE OR REPLACE).
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- sp_procesar_ingreso
--
-- Proposito : impactar un ingreso terminado en el stock del deposito
--             central (RN-10) y marcarlo como procesado.
-- Parametros: p_cod_ingreso  INTEGER  codigo del ingreso (cod_ingreso).
-- Efectos   : suma al stock_deposito cada renglon. Si el vino todavia no
--             tiene fila en stock_deposito (primer ingreso de ese vino),
--             la crea. El ingreso pasa a 'procesado'.
-- Errores   : P0001 si el ingreso no existe, no esta 'terminado' o no
--             tiene renglones.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_procesar_ingreso(p_cod_ingreso INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado estado_documento;
BEGIN
    -- 1. Bloquear la cabecera y leer su estado.
    SELECT i.estado INTO v_estado
      FROM ingreso i
     WHERE i.cod_ingreso = p_cod_ingreso
       FOR UPDATE;

    -- 2. Validar existencia y estado (RN-10).
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El ingreso % no existe (RN-10)', p_cod_ingreso;
    END IF;

    IF v_estado <> 'terminado' THEN
        RAISE EXCEPTION 'El ingreso % no esta terminado (estado actual: %). Solo un ingreso terminado puede procesarse (RN-10)',
            p_cod_ingreso, v_estado;
    END IF;

    -- 3. Un ingreso sin renglones no tiene nada que procesar.
    IF NOT EXISTS (SELECT 1 FROM renglon_ingreso r WHERE r.cod_ingreso = p_cod_ingreso) THEN
        RAISE EXCEPTION 'El ingreso % no tiene renglones: no hay nada que procesar', p_cod_ingreso;
    END IF;

    -- 5. Sumar al deposito (crea la fila si el vino todavia no tenia stock).
    --    ORDER BY cod_vino: orden fijo de bloqueo, evita deadlocks.
    INSERT INTO stock_deposito (cod_vino, cantidad)
    SELECT r.cod_vino, r.cantidad
      FROM renglon_ingreso r
     WHERE r.cod_ingreso = p_cod_ingreso
     ORDER BY r.cod_vino
    ON CONFLICT (cod_vino)
    DO UPDATE SET cantidad = stock_deposito.cantidad + EXCLUDED.cantidad;

    -- 6. Marcar como procesado.
    UPDATE ingreso
       SET estado = 'procesado'
     WHERE cod_ingreso = p_cod_ingreso;
END;
$$;

COMMENT ON PROCEDURE sp_procesar_ingreso(INTEGER) IS
    'RN-10. Suma al stock del deposito los renglones de un ingreso terminado y lo pasa a procesado. Todo o nada.';

-- ---------------------------------------------------------------------
-- sp_procesar_transferencia
--
-- Proposito : impactar una transferencia terminada: descontar del deposito
--             central, sumar al stock de la sala solicitante (RN-11) y
--             marcarla como procesada. No se procesa si el deposito no
--             tiene stock suficiente (RN-09).
-- Parametros: p_nro  INTEGER  numero de la transferencia (nro_transferencia).
-- Efectos   : resta de stock_deposito y suma a stock_sala (crea la fila
--             de la sala si todavia no existia). Pasa a 'procesado'.
-- Errores   : P0001 si la transferencia no existe, no esta 'terminado', no
--             tiene renglones, o si algun vino no tiene stock suficiente
--             en el deposito (incluye el caso de un vino SIN FILA en
--             stock_deposito).
--
-- Por que se verifica el stock antes (Anexo A.6 del TP):
--   Un UPDATE ... FROM sobre stock_deposito solo toca las filas que
--   existen. Si un vino del renglon no tiene fila en stock_deposito, el
--   UPDATE no descuenta nada Y NO DA ERROR: el CHECK (cantidad >= 0) nunca
--   se dispara, la sala recibiria botellas que el deposito no tenia y la
--   transferencia quedaria procesada. Por eso se compara cada renglon
--   contra el stock del deposito con un LEFT JOIN (sin fila = 0 botellas)
--   y se rechaza antes de modificar nada. El CHECK queda como red de
--   seguridad.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_procesar_transferencia(p_nro INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado    estado_documento;
    v_sala      INTEGER;
    v_faltantes TEXT;
BEGIN
    -- 1. Bloquear la cabecera y leer estado y sala solicitante.
    SELECT t.estado, t.id_sala INTO v_estado, v_sala
      FROM transferencia t
     WHERE t.nro_transferencia = p_nro
       FOR UPDATE;

    -- 2. Validar existencia y estado (RN-11).
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La transferencia % no existe (RN-11)', p_nro;
    END IF;

    IF v_estado <> 'terminado' THEN
        RAISE EXCEPTION 'La transferencia % no esta terminada (estado actual: %). Solo una transferencia terminada puede procesarse (RN-11)',
            p_nro, v_estado;
    END IF;

    -- 3. Una transferencia sin renglones no tiene nada que procesar.
    IF NOT EXISTS (SELECT 1 FROM renglon_transferencia r WHERE r.nro_transferencia = p_nro) THEN
        RAISE EXCEPTION 'La transferencia % no tiene renglones: no hay nada que procesar', p_nro;
    END IF;

    -- 4a. Bloquear las filas del deposito que se van a descontar, en orden
    --     de cod_vino. Otra transferencia o ingreso que toque los mismos
    --     vinos espera aca hasta que esta transaccion termine.
    PERFORM 1
       FROM stock_deposito d
      WHERE d.cod_vino IN (SELECT r.cod_vino
                             FROM renglon_transferencia r
                            WHERE r.nro_transferencia = p_nro)
      ORDER BY d.cod_vino
        FOR UPDATE;

    -- 4b. Verificar stock: cada renglon contra el deposito. LEFT JOIN y
    --     COALESCE: un vino sin fila en stock_deposito cuenta como 0.
    SELECT string_agg(
               format('vino %s (pedido %s, disponible %s)',
                      r.cod_vino, r.cantidad, COALESCE(d.cantidad, 0)),
               '; ' ORDER BY r.cod_vino)
      INTO v_faltantes
      FROM renglon_transferencia r
      LEFT JOIN stock_deposito d ON d.cod_vino = r.cod_vino
     WHERE r.nro_transferencia = p_nro
       AND COALESCE(d.cantidad, 0) < r.cantidad;

    IF v_faltantes IS NOT NULL THEN
        RAISE EXCEPTION 'Stock insuficiente en el deposito central para la transferencia %: % (RN-09)',
            p_nro, v_faltantes;
    END IF;

    -- 5a. Descontar del deposito. Todas las filas existen y alcanzan.
    UPDATE stock_deposito d
       SET cantidad = d.cantidad - r.cantidad
      FROM renglon_transferencia r
     WHERE r.nro_transferencia = p_nro
       AND d.cod_vino = r.cod_vino;

    -- 5b. Sumar al stock de la sala (crea la fila si todavia no existia).
    INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
    SELECT v_sala, r.cod_vino, r.cantidad
      FROM renglon_transferencia r
     WHERE r.nro_transferencia = p_nro
     ORDER BY r.cod_vino
    ON CONFLICT (id_sala, cod_vino)
    DO UPDATE SET cantidad = stock_sala.cantidad + EXCLUDED.cantidad;

    -- 6. Marcar como procesada.
    UPDATE transferencia
       SET estado = 'procesado'
     WHERE nro_transferencia = p_nro;
END;
$$;

COMMENT ON PROCEDURE sp_procesar_transferencia(INTEGER) IS
    'RN-09, RN-11. Verifica stock del deposito, lo descuenta, suma a la sala y pasa la transferencia a procesado. Todo o nada.';

COMMIT;

-- =====================================================================
-- Verificacion rapida (ejecutar a mano despues de aplicar la migracion)
--
-- Los procedimientos existen (prokind = 'p'):
--   SELECT proname, prokind
--     FROM pg_proc
--    WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'sp\_%'
--    ORDER BY proname;
--   -- Esperado: sp_procesar_ingreso p, sp_procesar_transferencia p
--
-- Uso:
--   CALL sp_procesar_ingreso(1);
--   CALL sp_procesar_transferencia(1);
--
-- Pruebas completas (con datos de prueba que no quedan en la base):
--   db/test/test_procedimientos.sql
-- =====================================================================