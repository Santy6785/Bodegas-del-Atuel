-- 02b_gate.sql – Bloque de control (gate) para transacción de carga histórica
--
-- Cuenta las filas devueltas por C1 y C3 a C13 de 02_controles.sql.
-- Si alguna consulta devuelve filas, lanza RAISE EXCEPTION nombrando el
-- control que falló, para que la transacción de carga se revierta.
-- Diseñado para ejecutarse dentro de la misma transacción que 01_pre_carga,
-- la carga masiva, 03_post_carga y 02_controles.

DO $$
DECLARE
    v_count INTEGER;
BEGIN
    -- C1: Triggers de usuario deshabilitados
    SELECT COUNT(*) INTO v_count
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    WHERE NOT t.tgisinternal
      AND c.relnamespace = 'public'::regnamespace
      AND t.tgenabled <> 'O';
    IF v_count > 0 THEN
        RAISE EXCEPTION 'Fallo en control C1: % trigger(s) de usuario deshabilitado(s)', v_count
            USING ERRCODE = 'check_violation';
    END IF;

    -- C3: Filas huérfanas en renglon_comprobante
    SELECT COUNT(*) INTO v_count
    FROM renglon_comprobante rc
    LEFT JOIN comprobante c ON c.nro_comprobante = rc.nro_comprobante
    WHERE c.nro_comprobante IS NULL;
    IF v_count > 0 THEN
        RAISE EXCEPTION 'Fallo en control C3: % renglón(es) de comprobante huérfano(s)', v_count
            USING ERRCODE = 'check_violation';
    END IF;

    -- C4: Stock negativo en salas
    SELECT COUNT(*) INTO v_count
    FROM stock_sala s WHERE s.cantidad < 0;
    IF v_count > 0 THEN
        RAISE EXCEPTION 'Fallo en control C4: % sala(s) con stock negativo', v_count
            USING ERRCODE = 'check_violation';
    END IF;

    -- C5: Inconsistencias en totales de comprobantes y subtotales de renglones
    SELECT COUNT(*) INTO v_count
    FROM comprobante c
    WHERE c.subtotal <> (
      SELECT COALESCE(SUM(rc.cantidad * rc.precio_unitario),0)
      FROM renglon_comprobante rc WHERE rc.nro_comprobante = c.nro_comprobante
    ) OR c.total <> fn_total_comprobante(c.nro_comprobante);
    IF v_count > 0 THEN
        RAISE EXCEPTION 'Fallo en control C5a: % comprobante(s) con total inconsistente', v_count
            USING ERRCODE = 'check_violation';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM renglon_comprobante rc
    WHERE rc.subtotal <> ROUND(rc.cantidad * rc.precio_unitario * (100 - rc.descuento_pct)/100,2);
    IF v_count > 0 THEN
        RAISE EXCEPTION 'Fallo en control C5b: % renglón(es) con subtotal inconsistente', v_count
            USING ERRCODE = 'check_violation';
    END IF;

    -- C6: Descuento_pct diferente al calculado por fn_descuento_cliente
    SELECT COUNT(*) INTO v_count
    FROM renglon_comprobante rc
    JOIN comprobante co ON co.nro_comprobante = rc.nro_comprobante
    JOIN cliente cl ON cl.id_cliente = co.id_cliente
    WHERE rc.descuento_pct <> fn_descuento_cliente(cl.id_cliente);
    IF v_count > 0 THEN
        RAISE EXCEPTION 'Fallo en control C6: % renglón(es) con descuento_pct inconsistente', v_count
            USING ERRCODE = 'check_violation';
    END IF;

    -- C7: Conservación del stock de sala
    SELECT COUNT(*) INTO v_count
    FROM (
      WITH mov_entr AS (
        SELECT tr.id_sala AS id_sala, rt.cod_vino AS cod_vino, SUM(rt.cantidad) AS entran
        FROM transferencia tr
        JOIN renglon_transferencia rt ON rt.nro_transferencia = tr.nro_transferencia
        WHERE tr.estado = 'procesado'
        GROUP BY tr.id_sala, rt.cod_vino
      ),
      mov_sal AS (
        SELECT c.id_sala AS id_sala, rc.cod_vino AS cod_vino, SUM(rc.cantidad) AS salen
        FROM comprobante c
        JOIN renglon_comprobante rc ON rc.nro_comprobante = c.nro_comprobante
        GROUP BY c.id_sala, rc.cod_vino
      ),
      calc AS (
        SELECT COALESCE(e.id_sala, s.id_sala) AS id_sala,
               COALESCE(e.cod_vino, s.cod_vino) AS cod_vino,
               COALESCE(e.entran, 0) - COALESCE(s.salen, 0) AS esperado
        FROM mov_entr e
        FULL OUTER JOIN mov_sal s ON s.id_sala = e.id_sala AND s.cod_vino = e.cod_vino
      )
      SELECT ss.id_sala, ss.cod_vino
      FROM stock_sala ss
      FULL OUTER JOIN calc c ON c.id_sala = ss.id_sala AND c.cod_vino = ss.cod_vino
      WHERE COALESCE(ss.cantidad, 0) IS DISTINCT FROM COALESCE(c.esperado, 0)
    ) sub;
    IF v_count > 0 THEN
        RAISE EXCEPTION 'Fallo en control C7: % par(es) sala/vino con stock inconsistente', v_count
            USING ERRCODE = 'check_violation';
    END IF;

    -- C8: Conservación del depósito
    SELECT COUNT(*) INTO v_count
    FROM (
      WITH mov_ing AS (
        SELECT ri.cod_vino AS cod_vino, SUM(ri.cantidad) AS entran
        FROM ingreso i
        JOIN renglon_ingreso ri ON ri.cod_ingreso = i.cod_ingreso
        WHERE i.estado = 'procesado'
        GROUP BY ri.cod_vino
      ),
      mov_tr AS (
        SELECT rt.cod_vino AS cod_vino, SUM(rt.cantidad) AS salen
        FROM transferencia tr
        JOIN renglon_transferencia rt ON rt.nro_transferencia = tr.nro_transferencia
        WHERE tr.estado = 'procesado'
        GROUP BY rt.cod_vino
      ),
      calc AS (
        SELECT COALESCE(mi.cod_vino, mt.cod_vino) AS cod_vino,
               COALESCE(mi.entran, 0) - COALESCE(mt.salen, 0) AS esperado
        FROM mov_ing mi
        FULL OUTER JOIN mov_tr mt ON mt.cod_vino = mi.cod_vino
      )
      SELECT sd.cod_vino
      FROM stock_deposito sd
      FULL OUTER JOIN calc c ON c.cod_vino = sd.cod_vino
      WHERE COALESCE(sd.cantidad, 0) IS DISTINCT FROM COALESCE(c.esperado, 0)
    ) sub;
    IF v_count > 0 THEN
        RAISE EXCEPTION 'Fallo en control C8: % vino(s) con stock de depósito inconsistente', v_count
            USING ERRCODE = 'check_violation';
    END IF;

    -- C9: Stock acumulado negativo en alguna ventana
    SELECT COUNT(*) INTO v_count
    FROM (
      WITH movimiento AS (
        SELECT tr.id_sala, rt.cod_vino, tr.fecha_confeccion AS fecha, rt.cantidad
        FROM transferencia tr
        JOIN renglon_transferencia rt ON rt.nro_transferencia = tr.nro_transferencia
        WHERE tr.estado = 'procesado'
        UNION ALL
        SELECT c.id_sala, rc.cod_vino, c.fecha AS fecha, -rc.cantidad
        FROM comprobante c
        JOIN renglon_comprobante rc ON rc.nro_comprobante = c.nro_comprobante
      ),
      acumulado AS (
        SELECT id_sala, cod_vino, fecha, cantidad,
               SUM(cantidad) OVER (
                 PARTITION BY id_sala, cod_vino
                 ORDER BY fecha, CASE WHEN cantidad > 0 THEN 0 ELSE 1 END
                 ROWS UNBOUNDED PRECEDING
               ) AS acumulado
        FROM movimiento
      )
      SELECT * FROM acumulado WHERE acumulado < 0
    ) sub;
    IF v_count > 0 THEN
        RAISE EXCEPTION 'Fallo en control C9: % registro(s) de stock acumulado negativo', v_count
            USING ERRCODE = 'check_violation';
    END IF;

    -- C10: Vinos cuya composición no suma 100
    SELECT COUNT(*) INTO v_count
    FROM vino v
    WHERE NOT EXISTS (
      SELECT 1 FROM vino_cepa vc WHERE vc.cod_vino = v.cod_vino
      GROUP BY vc.cod_vino HAVING SUM(vc.porcentaje) = 100
    );
    IF v_count > 0 THEN
        RAISE EXCEPTION 'Fallo en control C10: % vino(s) con composición distinta de 100%%', v_count
            USING ERRCODE = 'check_violation';
    END IF;

    -- C11: Clientes cuyo tipo no coincide con su subtipo
    SELECT COUNT(*) INTO v_count
    FROM cliente c
    WHERE (c.tipo_cliente = 'distribuidor' AND NOT EXISTS (SELECT 1 FROM cliente_distribuidor d WHERE d.id_cliente = c.id_cliente))
       OR (c.tipo_cliente = 'exportador' AND NOT EXISTS (SELECT 1 FROM cliente_exportador e WHERE e.id_cliente = c.id_cliente))
       OR (c.tipo_cliente = 'socio' AND (
             EXISTS (SELECT 1 FROM cliente_distribuidor d WHERE d.id_cliente = c.id_cliente)
          OR EXISTS (SELECT 1 FROM cliente_exportador e WHERE e.id_cliente = c.id_cliente)));
    IF v_count > 0 THEN
        RAISE EXCEPTION 'Fallo en control C11: % cliente(s) con tipo/subtipo inconsistente', v_count
            USING ERRCODE = 'check_violation';
    END IF;

    -- C12: Ingresos o transferencias procesados sin renglones
    SELECT COUNT(*) INTO v_count
    FROM ingreso i WHERE i.estado = 'procesado' AND NOT EXISTS (SELECT 1 FROM renglon_ingreso ri WHERE ri.cod_ingreso = i.cod_ingreso);
    IF v_count > 0 THEN
        RAISE EXCEPTION 'Fallo en control C12a: % ingreso(s) procesado(s) sin renglón(es)', v_count
            USING ERRCODE = 'check_violation';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM transferencia tr WHERE tr.estado = 'procesado' AND NOT EXISTS (SELECT 1 FROM renglon_transferencia rt WHERE rt.nro_transferencia = tr.nro_transferencia);
    IF v_count > 0 THEN
        RAISE EXCEPTION 'Fallo en control C12b: % transferencia(s) procesada(s) sin renglón(es)', v_count
            USING ERRCODE = 'check_violation';
    END IF;

    -- C13: Documentos con fecha futura
    SELECT COUNT(*) INTO v_count
    FROM comprobante WHERE fecha > CURRENT_DATE;
    IF v_count > 0 THEN
        RAISE EXCEPTION 'Fallo en control C13a: % comprobante(s) con fecha futura', v_count
            USING ERRCODE = 'check_violation';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM ingreso WHERE fecha > CURRENT_DATE;
    IF v_count > 0 THEN
        RAISE EXCEPTION 'Fallo en control C13b: % ingreso(s) con fecha futura', v_count
            USING ERRCODE = 'check_violation';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM transferencia WHERE fecha_confeccion > CURRENT_DATE;
    IF v_count > 0 THEN
        RAISE EXCEPTION 'Fallo en control C13c: % transferencia(s) con fecha futura', v_count
            USING ERRCODE = 'check_violation';
    END IF;
END;
$$;
