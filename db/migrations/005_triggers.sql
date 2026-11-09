-- =====================================================================
-- 005_triggers.sql
-- Bodegas del Atuel - Triggers de integridad
--
-- Cada trigger lleva un comentario con la regla de negocio que protege.
--
--   Trigger                              Tipo                          Regla
--   -----------------------------------  ----------------------------  ------------
--   trg_renglon_comprobante_antes        BEFORE INSERT/UPDATE          RN-09, RN-06, RN-08
--   trg_renglon_comprobante_despues      AFTER INSERT/UPDATE/DELETE    RN-08, RN-09
--   trg_ingreso_estados                  BEFORE UPDATE                 RN-10
--   trg_transferencia_estados            BEFORE UPDATE                 RN-11
--   trg_transferencia_fecha              BEFORE INSERT/UPDATE          RN-11
--   trg_renglon_ingreso_confeccion       BEFORE INSERT/UPDATE/DELETE   RN-12
--   trg_renglon_transferencia_confeccion BEFORE INSERT/UPDATE/DELETE   RN-12
--   trg_vino_auditoria                   AFTER UPDATE OF precio        RN-13
--   ctg_vino_cepa_suma_100               CONSTRAINT TRIGGER diferido   RN-05
--   ctg_vino_composicion                 CONSTRAINT TRIGGER diferido   RN-05
--   trg_vino_lote_bodega                 BEFORE INSERT/UPDATE          trazabilidad
--   ctg_cliente_tipo (x3)                CONSTRAINT TRIGGER diferido   jerarquia de clientes
--
-- Convenciones:
--   * Las reglas rechazadas usan RAISE EXCEPTION (SQLSTATE P0001), que la
--     API traduce a 409 con el mensaje tal cual.
--   * Los constraint triggers diferidos se evaluan al COMMIT, no al INSERT.
--     La API debe capturar la excepcion tambien alrededor del commit.
--   * Los procedimientos de 004 (sp_procesar_*) cumplen estos triggers:
--     solo hacen terminado -> procesado.
--   * Carga masiva (etapa 3): se pueden deshabilitar con
--       ALTER TABLE <tabla> DISABLE TRIGGER USER;
--     y volver a habilitar despues, validando con consultas de control.
--     Los triggers de estado, de fecha de confeccion y de calculo de
--     comprobantes alteran los datos historicos si quedan activos.
--
-- Se ejecuta despues de 001 a 004. Es idempotente (DROP IF EXISTS + CREATE).
-- =====================================================================

BEGIN;

-- =====================================================================
-- VENTAS: renglon_comprobante
-- =====================================================================

-- ---------------------------------------------------------------------
-- trg_renglon_comprobante_antes  (BEFORE INSERT OR UPDATE)
--
-- Reglas: RN-09 (no se vende mas de lo que hay), RN-06 (descuento segun
--         el cliente) y RN-08 (subtotal del renglon).
--
-- En INSERT:
--   * Valida que el comprobante y el vino existan (si no, 23503).
--   * Bloquea la fila de stock de la sala (FOR UPDATE) y verifica que
--     alcance. El bloqueo evita que dos ventas simultaneas vendan la misma
--     ultima botella: la segunda espera y, al reintentar, ve el stock real.
--   * Copia el precio vigente del vino a precio_unitario (snapshot).
--   * Copia fn_descuento_cliente(cliente) a descuento_pct (snapshot).
-- En INSERT y UPDATE:
--   * Calcula subtotal = ROUND(cantidad * precio * (100 - desc) / 100, 2),
--     la misma formula de fn_total_comprobante.
-- La API no envia precio, descuento ni subtotal: los pone este trigger.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_renglon_comprobante_antes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_sala    INTEGER;
    v_cliente INTEGER;
    v_precio  NUMERIC;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT c.id_sala, c.id_cliente INTO v_sala, v_cliente
          FROM comprobante c
         WHERE c.nro_comprobante = NEW.nro_comprobante;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'El comprobante % no existe', NEW.nro_comprobante
                USING ERRCODE = 'foreign_key_violation';
        END IF;

        SELECT v.precio INTO v_precio
          FROM vino v
         WHERE v.cod_vino = NEW.cod_vino;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'El vino % no existe', NEW.cod_vino
                USING ERRCODE = 'foreign_key_violation';
        END IF;

        -- RN-09: bloquear la fila de stock y verificar.
        PERFORM 1
           FROM stock_sala s
          WHERE s.id_sala = v_sala AND s.cod_vino = NEW.cod_vino
            FOR UPDATE;

        IF fn_stock_sala(v_sala, NEW.cod_vino) < NEW.cantidad THEN
            RAISE EXCEPTION 'Stock insuficiente del vino % en la sala % (RN-09)',
                NEW.cod_vino, v_sala;
        END IF;

        -- RN-06 y RN-08: snapshots historicos.
        NEW.precio_unitario := v_precio;
        NEW.descuento_pct   := fn_descuento_cliente(v_cliente);
    END IF;

    -- RN-08: subtotal del renglon.
    NEW.subtotal := ROUND(NEW.cantidad * NEW.precio_unitario * (100 - NEW.descuento_pct) / 100, 2);

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_renglon_comprobante_antes ON renglon_comprobante;
CREATE TRIGGER trg_renglon_comprobante_antes
BEFORE INSERT OR UPDATE ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION trg_renglon_comprobante_antes();

-- ---------------------------------------------------------------------
-- trg_renglon_comprobante_despues  (AFTER INSERT OR UPDATE OR DELETE)
--
-- Reglas: RN-09 (descuenta el stock de la sala) y RN-08 (el total del
--         comprobante es la suma de sus renglones y no se carga a mano).
--
-- En INSERT descuenta del stock de la sala la cantidad vendida. En UPDATE
-- y DELETE NO toca el stock: un renglon emitido no devuelve botellas
-- (ademas, DELETE se usa para depurar historico: consigna D1).
-- En los tres casos recalcula la cabecera:
--   subtotal  = SUM(cantidad * precio_unitario)   (bruto)
--   total     = fn_total_comprobante(nro)         (con descuento)
--   descuento = subtotal - total
-- Si el comprobante ya no existe (borrado en cascada) el UPDATE no
-- afecta filas y no hace nada.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_renglon_comprobante_despues()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_sala INTEGER;
    v_nros INTEGER[];
    v_nro  INTEGER;
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- RN-09: descontar el stock vendido.
        SELECT c.id_sala INTO v_sala
          FROM comprobante c
         WHERE c.nro_comprobante = NEW.nro_comprobante;

        UPDATE stock_sala s
           SET cantidad = s.cantidad - NEW.cantidad
         WHERE s.id_sala = v_sala AND s.cod_vino = NEW.cod_vino;

        v_nros := ARRAY[NEW.nro_comprobante];
    ELSIF TG_OP = 'UPDATE' THEN
        v_nros := ARRAY[OLD.nro_comprobante, NEW.nro_comprobante];
    ELSE
        v_nros := ARRAY[OLD.nro_comprobante];
    END IF;

    -- RN-08: recalcular la cabecera.
    FOREACH v_nro IN ARRAY v_nros LOOP
        UPDATE comprobante c
           SET subtotal  = x.bruto,
               descuento = x.bruto - x.neto,
               total     = x.neto
          FROM (SELECT COALESCE(SUM(r.cantidad * r.precio_unitario), 0)::NUMERIC(12,2) AS bruto,
                       fn_total_comprobante(v_nro) AS neto
                  FROM renglon_comprobante r
                 WHERE r.nro_comprobante = v_nro) x
         WHERE c.nro_comprobante = v_nro;
    END LOOP;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_renglon_comprobante_despues ON renglon_comprobante;
CREATE TRIGGER trg_renglon_comprobante_despues
AFTER INSERT OR UPDATE OR DELETE ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION trg_renglon_comprobante_despues();

-- =====================================================================
-- INGRESOS Y TRANSFERENCIAS: estados, fecha y bloqueo de renglones
-- =====================================================================

-- ---------------------------------------------------------------------
-- trg_control_estado_documento  (BEFORE UPDATE en ingreso y transferencia)
--
-- Reglas: RN-10 (ingreso) y RN-11 (transferencia).
--
-- Solo permite en_confeccion -> terminado -> procesado. No retrocede ni
-- se saltea un paso. Un UPDATE que no cambia el estado pasa sin control.
-- Un mismo codigo de funcion sirve para las dos tablas: la regla es igual.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_control_estado_documento()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.estado = OLD.estado THEN
        RETURN NEW;
    END IF;

    IF (OLD.estado = 'en_confeccion' AND NEW.estado = 'terminado')
    OR (OLD.estado = 'terminado'     AND NEW.estado = 'procesado') THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'Transicion de estado invalida en %: % -> %. Solo se permite en_confeccion -> terminado -> procesado, sin retrocesos (%)',
        TG_TABLE_NAME, OLD.estado, NEW.estado,
        CASE TG_TABLE_NAME WHEN 'ingreso' THEN 'RN-10' ELSE 'RN-11' END;
END;
$$;

DROP TRIGGER IF EXISTS trg_ingreso_estados ON ingreso;
CREATE TRIGGER trg_ingreso_estados
BEFORE UPDATE OF estado ON ingreso
FOR EACH ROW EXECUTE FUNCTION trg_control_estado_documento();

DROP TRIGGER IF EXISTS trg_transferencia_estados ON transferencia;
CREATE TRIGGER trg_transferencia_estados
BEFORE UPDATE OF estado ON transferencia
FOR EACH ROW EXECUTE FUNCTION trg_control_estado_documento();

-- ---------------------------------------------------------------------
-- trg_transferencia_fecha  (BEFORE INSERT OR UPDATE en transferencia)
--
-- Regla: RN-11. La fecha de confeccion es la actual y no se puede modificar.
--
-- En INSERT fuerza CURRENT_DATE, aunque el cliente envie otra fecha.
-- En UPDATE rechaza cualquier cambio de fecha_confeccion.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_transferencia_fecha()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.fecha_confeccion := CURRENT_DATE;
    ELSIF NEW.fecha_confeccion IS DISTINCT FROM OLD.fecha_confeccion THEN
        RAISE EXCEPTION 'La fecha de confeccion de la transferencia % no puede modificarse (RN-11)',
            OLD.nro_transferencia;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_transferencia_fecha ON transferencia;
CREATE TRIGGER trg_transferencia_fecha
BEFORE INSERT OR UPDATE ON transferencia
FOR EACH ROW EXECUTE FUNCTION trg_transferencia_fecha();

-- ---------------------------------------------------------------------
-- trg_renglon_ingreso_confeccion  (BEFORE INSERT/UPDATE/DELETE)
--
-- Regla: RN-12. Un ingreso que no esta en confeccion no admite agregar,
--        modificar ni quitar renglones.
--
-- Lee el estado de la cabecera con FOR SHARE: asi no puede cambiar de
-- estado (la cabecera se bloquea FOR UPDATE al procesarla) mientras se
-- esta modificando un renglon.
-- Si la cabecera ya no existe (borrado en cascada de un ingreso, consigna
-- D5) la operacion se permite. Si no existe en un INSERT, lo rechaza la FK.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_renglon_ingreso_confeccion()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_cods   INTEGER[];
    v_cod    INTEGER;
    v_estado estado_documento;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_cods := ARRAY[NEW.cod_ingreso];
    ELSIF TG_OP = 'DELETE' THEN
        v_cods := ARRAY[OLD.cod_ingreso];
    ELSE
        v_cods := ARRAY[OLD.cod_ingreso, NEW.cod_ingreso];
    END IF;

    FOREACH v_cod IN ARRAY v_cods LOOP
        SELECT i.estado INTO v_estado
          FROM ingreso i
         WHERE i.cod_ingreso = v_cod
           FOR SHARE;

        IF FOUND AND v_estado <> 'en_confeccion' THEN
            RAISE EXCEPTION 'El ingreso % no esta en confeccion (estado actual: %): no admite agregar, modificar ni quitar renglones (RN-12)',
                v_cod, v_estado;
        END IF;
    END LOOP;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_renglon_ingreso_confeccion ON renglon_ingreso;
CREATE TRIGGER trg_renglon_ingreso_confeccion
BEFORE INSERT OR UPDATE OR DELETE ON renglon_ingreso
FOR EACH ROW EXECUTE FUNCTION trg_renglon_ingreso_confeccion();

-- ---------------------------------------------------------------------
-- trg_renglon_transferencia_confeccion  (BEFORE INSERT/UPDATE/DELETE)
--
-- Regla: RN-12. Igual que el anterior, para transferencias.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_renglon_transferencia_confeccion()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_nros   INTEGER[];
    v_nro    INTEGER;
    v_estado estado_documento;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_nros := ARRAY[NEW.nro_transferencia];
    ELSIF TG_OP = 'DELETE' THEN
        v_nros := ARRAY[OLD.nro_transferencia];
    ELSE
        v_nros := ARRAY[OLD.nro_transferencia, NEW.nro_transferencia];
    END IF;

    FOREACH v_nro IN ARRAY v_nros LOOP
        SELECT t.estado INTO v_estado
          FROM transferencia t
         WHERE t.nro_transferencia = v_nro
           FOR SHARE;

        IF FOUND AND v_estado <> 'en_confeccion' THEN
            RAISE EXCEPTION 'La transferencia % no esta en confeccion (estado actual: %): no admite agregar, modificar ni quitar renglones (RN-12)',
                v_nro, v_estado;
        END IF;
    END LOOP;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_renglon_transferencia_confeccion ON renglon_transferencia;
CREATE TRIGGER trg_renglon_transferencia_confeccion
BEFORE INSERT OR UPDATE OR DELETE ON renglon_transferencia
FOR EACH ROW EXECUTE FUNCTION trg_renglon_transferencia_confeccion();

-- =====================================================================
-- VINOS: auditoria, composicion y trazabilidad
-- =====================================================================

-- ---------------------------------------------------------------------
-- trg_vino_auditoria  (AFTER UPDATE OF precio en vino)
--
-- Regla: RN-13. Todo cambio de precio de un vino queda auditado (fecha,
--        usuario, precio anterior y nuevo).
--
-- fecha_hora y usuario los completan los DEFAULT de auditoria_precio
-- (now() y current_user). Solo se dispara si el precio realmente cambia.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_vino_auditoria_precio()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO auditoria_precio (cod_vino, precio_anterior, precio_nuevo)
    VALUES (NEW.cod_vino, OLD.precio, NEW.precio);
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_vino_auditoria ON vino;
CREATE TRIGGER trg_vino_auditoria
AFTER UPDATE OF precio ON vino
FOR EACH ROW
WHEN (OLD.precio IS DISTINCT FROM NEW.precio)
EXECUTE FUNCTION trg_vino_auditoria_precio();

-- ---------------------------------------------------------------------
-- ctg_vino_cepa_suma_100 y ctg_vino_composicion
-- (CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED)
--
-- Regla: RN-05. Los porcentajes de corte de un vino suman exactamente 100.
--
-- Un CHECK ve una sola fila, asi que la suma por vino necesita un trigger.
-- Es DIFERIDO: se evalua al COMMIT, cuando ya estan cargadas todas las
-- cepas del vino. Si no, no se podria insertar la composicion fila por fila.
--   * ctg_vino_cepa_suma_100: al insertar, modificar o borrar una cepa.
--   * ctg_vino_composicion:   al insertar un vino, para rechazar un vino
--     sin ninguna cepa (suma 0), que el trigger anterior no veria.
-- Si el vino ya no existe (borrado en cascada) no se valida.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_validar_composicion_vino()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_cods  INTEGER[];
    v_cod   INTEGER;
    v_suma  NUMERIC;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_cods := ARRAY[NEW.cod_vino];
    ELSIF TG_OP = 'DELETE' THEN
        v_cods := ARRAY[OLD.cod_vino];
    ELSE
        v_cods := ARRAY[OLD.cod_vino, NEW.cod_vino];
    END IF;

    FOREACH v_cod IN ARRAY v_cods LOOP
        IF NOT EXISTS (SELECT 1 FROM vino v WHERE v.cod_vino = v_cod) THEN
            CONTINUE;
        END IF;

        SELECT COALESCE(SUM(vc.porcentaje), 0) INTO v_suma
          FROM vino_cepa vc
         WHERE vc.cod_vino = v_cod;

        IF v_suma <> 100 THEN
            RAISE EXCEPTION 'La composicion del vino % suma % y debe sumar exactamente 100 (RN-05)',
                v_cod, v_suma;
        END IF;
    END LOOP;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS ctg_vino_cepa_suma_100 ON vino_cepa;
CREATE CONSTRAINT TRIGGER ctg_vino_cepa_suma_100
AFTER INSERT OR UPDATE OR DELETE ON vino_cepa
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION trg_validar_composicion_vino();

DROP TRIGGER IF EXISTS ctg_vino_composicion ON vino;
CREATE CONSTRAINT TRIGGER ctg_vino_composicion
AFTER INSERT ON vino
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION trg_validar_composicion_vino();

-- ---------------------------------------------------------------------
-- trg_vino_lote_bodega  (BEFORE INSERT OR UPDATE en vino_lote)
--
-- Regla: trazabilidad (regla cruzada entre tablas, no es un FK ni un CHECK).
--        El lote de uva debe haber sido entregado a la bodega que elabora
--        el vino (lote_uva.cuit_bodega = vino.cuit_bodega).
--
-- Si el lote o el vino no existen, lo rechaza la FK.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_vino_lote_bodega()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_bodega_lote cuit_dom;
    v_bodega_vino cuit_dom;
BEGIN
    SELECT l.cuit_bodega INTO v_bodega_lote FROM lote_uva l WHERE l.id_lote = NEW.id_lote;
    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    SELECT v.cuit_bodega INTO v_bodega_vino FROM vino v WHERE v.cod_vino = NEW.cod_vino;
    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    IF v_bodega_lote <> v_bodega_vino THEN
        RAISE EXCEPTION 'El lote % fue entregado a la bodega % pero el vino % lo elabora la bodega %: el lote debe pertenecer a la bodega del vino (trazabilidad)',
            NEW.id_lote, v_bodega_lote, NEW.cod_vino, v_bodega_vino;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_vino_lote_bodega ON vino_lote;
CREATE TRIGGER trg_vino_lote_bodega
BEFORE INSERT OR UPDATE ON vino_lote
FOR EACH ROW EXECUTE FUNCTION trg_vino_lote_bodega();

-- =====================================================================
-- CLIENTES: coherencia entre tipo_cliente y los subtipos
-- =====================================================================

-- ---------------------------------------------------------------------
-- ctg_cliente_tipo, ctg_cliente_distribuidor_tipo, ctg_cliente_exportador_tipo
-- (CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED)
--
-- Regla: especializacion total y exclusiva de clientes (decisiones.md 2.3).
--   socio         -> sin fila en cliente_distribuidor ni cliente_exportador
--   distribuidor  -> fila en cliente_distribuidor y ninguna en exportador
--   exportador    -> fila en cliente_exportador y ninguna en distribuidor
--
-- Es DIFERIDO porque el subtipo tiene FK al cliente: la fila del cliente
-- se inserta primero y la del subtipo despues, dentro de la misma
-- transaccion. Si no fuera diferido, rechazaria todo alta de distribuidor
-- o exportador. Se dispara desde las tres tablas porque una incoherencia
-- puede venir de cualquiera. Si el cliente ya no existe (borrado en
-- cascada) no se valida.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_validar_tipo_cliente()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_id      INTEGER;
    v_tipo    tipo_cliente;
    v_es_dist BOOLEAN;
    v_es_exp  BOOLEAN;
    v_ok      BOOLEAN;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_id := OLD.id_cliente;
    ELSE
        v_id := NEW.id_cliente;
    END IF;

    SELECT c.tipo_cliente INTO v_tipo FROM cliente c WHERE c.id_cliente = v_id;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    v_es_dist := EXISTS (SELECT 1 FROM cliente_distribuidor d WHERE d.id_cliente = v_id);
    v_es_exp  := EXISTS (SELECT 1 FROM cliente_exportador   e WHERE e.id_cliente = v_id);

    v_ok := CASE v_tipo
                WHEN 'socio'        THEN NOT v_es_dist AND NOT v_es_exp
                WHEN 'distribuidor' THEN v_es_dist AND NOT v_es_exp
                WHEN 'exportador'   THEN v_es_exp AND NOT v_es_dist
            END;

    IF NOT v_ok THEN
        RAISE EXCEPTION 'Incoherencia de tipo de cliente: el cliente % es de tipo % pero su subtipo no corresponde (fila de distribuidor: %, fila de exportador: %)',
            v_id, v_tipo, v_es_dist, v_es_exp;
    END IF;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS ctg_cliente_tipo ON cliente;
CREATE CONSTRAINT TRIGGER ctg_cliente_tipo
AFTER INSERT OR UPDATE OF tipo_cliente ON cliente
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION trg_validar_tipo_cliente();

DROP TRIGGER IF EXISTS ctg_cliente_distribuidor_tipo ON cliente_distribuidor;
CREATE CONSTRAINT TRIGGER ctg_cliente_distribuidor_tipo
AFTER INSERT OR UPDATE OR DELETE ON cliente_distribuidor
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION trg_validar_tipo_cliente();

DROP TRIGGER IF EXISTS ctg_cliente_exportador_tipo ON cliente_exportador;
CREATE CONSTRAINT TRIGGER ctg_cliente_exportador_tipo
AFTER INSERT OR UPDATE OR DELETE ON cliente_exportador
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION trg_validar_tipo_cliente();

COMMIT;

-- =====================================================================
-- Verificacion (ejecutar a mano despues de aplicar la migracion)
--
-- Triggers creados (sin los internos de las FK):
--   SELECT c.relname AS tabla, t.tgname AS trigger,
--          t.tgenabled AS habilitado,
--          (t.tgconstraint <> 0) AS es_constraint_trigger,
--          t.tgdeferrable AS diferible, t.tginitdeferred AS diferido
--     FROM pg_trigger t
--     JOIN pg_class c ON c.oid = t.tgrelid
--    WHERE NOT t.tgisinternal AND c.relnamespace = 'public'::regnamespace
--    ORDER BY 1, 2;
--
-- Pruebas con datos que no quedan en la base:
--   db/test/test_triggers.sql
-- =====================================================================