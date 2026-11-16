-- 02_controles.sql – Consultas de control después de la carga histórica
-- (corregido: estados en minúscula según el enum estado_documento;
--  columnas reales del esquema; C7 y C8 con FULL OUTER JOIN y COALESCE;
--  C9 con ventas como negativo y entradas primero en el mismo día;
--  C2 con conteo de TODAS las tablas de public)

-- C1: Triggers de usuario que no están habilitados
SELECT c.relname, t.tgname, t.tgenabled
FROM   pg_trigger t
JOIN   pg_class c ON c.oid = t.tgrelid
WHERE  NOT t.tgisinternal
  AND  t.tgenabled <> 'O';

-- C2: Conteo de filas de TODAS las tablas de public
SELECT 'analisis_calidad'      AS tabla, COUNT(*) FROM analisis_calidad      UNION ALL
SELECT 'auditoria_precio'      AS tabla, COUNT(*) FROM auditoria_precio      UNION ALL
SELECT 'bodega'                AS tabla, COUNT(*) FROM bodega                UNION ALL
SELECT 'cepa'                  AS tabla, COUNT(*) FROM cepa                  UNION ALL
SELECT 'cliente'               AS tabla, COUNT(*) FROM cliente               UNION ALL
SELECT 'cliente_distribuidor'  AS tabla, COUNT(*) FROM cliente_distribuidor  UNION ALL
SELECT 'cliente_exportador'    AS tabla, COUNT(*) FROM cliente_exportador    UNION ALL
SELECT 'comprobante'           AS tabla, COUNT(*) FROM comprobante           UNION ALL
SELECT 'departamento'          AS tabla, COUNT(*) FROM departamento          UNION ALL
SELECT 'empleado'              AS tabla, COUNT(*) FROM empleado              UNION ALL
SELECT 'finca'                 AS tabla, COUNT(*) FROM finca                 UNION ALL
SELECT 'ingreso'               AS tabla, COUNT(*) FROM ingreso               UNION ALL
SELECT 'localidad'             AS tabla, COUNT(*) FROM localidad             UNION ALL
SELECT 'lote_uva'              AS tabla, COUNT(*) FROM lote_uva              UNION ALL
SELECT 'maridaje'              AS tabla, COUNT(*) FROM maridaje              UNION ALL
SELECT 'parcela'               AS tabla, COUNT(*) FROM parcela               UNION ALL
SELECT 'permiso_exportacion'   AS tabla, COUNT(*) FROM permiso_exportacion   UNION ALL
SELECT 'renglon_comprobante'   AS tabla, COUNT(*) FROM renglon_comprobante   UNION ALL
SELECT 'renglon_ingreso'       AS tabla, COUNT(*) FROM renglon_ingreso       UNION ALL
SELECT 'renglon_transferencia' AS tabla, COUNT(*) FROM renglon_transferencia UNION ALL
SELECT 'sala_venta'            AS tabla, COUNT(*) FROM sala_venta            UNION ALL
SELECT 'stock_deposito'        AS tabla, COUNT(*) FROM stock_deposito        UNION ALL
SELECT 'stock_sala'            AS tabla, COUNT(*) FROM stock_sala            UNION ALL
SELECT 'transferencia'         AS tabla, COUNT(*) FROM transferencia         UNION ALL
SELECT 'transportista'         AS tabla, COUNT(*) FROM transportista         UNION ALL
SELECT 'transportista_localidad' AS tabla, COUNT(*) FROM transportista_localidad UNION ALL
SELECT 'vino'                  AS tabla, COUNT(*) FROM vino                  UNION ALL
SELECT 'vino_cepa'             AS tabla, COUNT(*) FROM vino_cepa             UNION ALL
SELECT 'vino_lote'             AS tabla, COUNT(*) FROM vino_lote             UNION ALL
SELECT 'vino_maridaje'         AS tabla, COUNT(*) FROM vino_maridaje;

-- C3: Filas huérfanas en relaciones principales (ejemplo: renglon_comprobante sin comprobante)
SELECT rc.* FROM renglon_comprobante rc
LEFT JOIN comprobante c ON c.nro_comprobante = rc.nro_comprobante
WHERE c.nro_comprobante IS NULL;

-- C4: Stock negativo en salas
SELECT s.* FROM stock_sala s WHERE s.cantidad < 0;

-- C5: Inconsistencias en totales de comprobantes y subtotales de renglones
-- 5a: Totales del comprobante.
--     subtotal  = bruto = SUM(cantidad * precio_unitario)  (sin descuento)
--     total     = neto  = fn_total_comprobante(nro)        (con descuento)
--     fn_total_comprobante recibe nro_comprobante y devuelve
--     SUM(ROUND(cantidad * precio_unitario * (100 - descuento_pct) / 100, 2))
-- 5b: Subtotales de renglones
SELECT c.* FROM comprobante c
WHERE c.subtotal <> (
  SELECT COALESCE(SUM(rc.cantidad * rc.precio_unitario),0)
  FROM renglon_comprobante rc WHERE rc.nro_comprobante = c.nro_comprobante
) OR c.total <> fn_total_comprobante(c.nro_comprobante);
SELECT rc.* FROM renglon_comprobante rc
WHERE rc.subtotal <> ROUND(rc.cantidad * rc.precio_unitario * (100 - rc.descuento_pct)/100,2);

-- C6: Descuento_pct diferente al calculado por fn_descuento_cliente
-- fn_descuento_cliente recibe id_cliente (INTEGER), no tipo_cliente.
-- Devuelve: socio=10, distribuidor=20, exportador=porcentaje_descuento.
SELECT rc.* FROM renglon_comprobante rc
JOIN comprobante co ON co.nro_comprobante = rc.nro_comprobante
JOIN cliente cl ON cl.id_cliente = co.id_cliente
WHERE rc.descuento_pct <> fn_descuento_cliente(cl.id_cliente);

-- C7: Conservación del stock de sala (stock inicial 0).
-- esperado = transferencias_procesadas_entran - ventas_comprobante_salen, por (id_sala, cod_vino).
-- FULL OUTER JOIN contra stock_sala para detectar pares con movimiento y sin fila de stock.
-- COALESCE en ambos lados de IS DISTINCT FROM para no marcar pares sin movimiento ni fila.
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
SELECT ss.id_sala, ss.cod_vino, ss.cantidad AS real, c.esperado
FROM stock_sala ss
FULL OUTER JOIN calc c ON c.id_sala = ss.id_sala AND c.cod_vino = ss.cod_vino
WHERE COALESCE(ss.cantidad, 0) IS DISTINCT FROM COALESCE(c.esperado, 0);

-- C8: Conservación del depósito (por vino).
-- esperado = ingresos_procesados_entran - transferencias_procesadas_salen.
-- FULL OUTER JOIN contra stock_deposito.
-- COALESCE en ambos lados de IS DISTINCT FROM.
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
SELECT sd.cod_vino, sd.cantidad AS real, c.esperado
FROM stock_deposito sd
FULL OUTER JOIN calc c ON c.cod_vino = sd.cod_vino
WHERE COALESCE(sd.cantidad, 0) IS DISTINCT FROM COALESCE(c.esperado, 0);

-- C9: Stock acumulado que alguna vez queda negativo (ventana, por sala).
-- Transferencias procesadas SUMAN (entran a la sala, positivo).
-- Ventas (comprobantes) RESTAN (salen de la sala, negativo).
-- Ordenadas por fecha, con las entradas primero en el mismo día.
-- Devuelve las filas con acumulado < 0.
WITH movimiento AS (
  -- Transferencias: entran (positivo)
  SELECT tr.id_sala, rt.cod_vino, tr.fecha_confeccion AS fecha, rt.cantidad
  FROM transferencia tr
  JOIN renglon_transferencia rt ON rt.nro_transferencia = tr.nro_transferencia
  WHERE tr.estado = 'procesado'
  UNION ALL
  -- Ventas: salen (negativo)
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
SELECT * FROM acumulado WHERE acumulado < 0;

-- C10: Vinos cuya composición no suma 100 (tabla real: vino_cepa, no vino_composicion)
SELECT v.cod_vino, v.nombre FROM vino v
WHERE NOT EXISTS (
  SELECT 1 FROM vino_cepa vc WHERE vc.cod_vino = v.cod_vino
  GROUP BY vc.cod_vino HAVING SUM(vc.porcentaje) = 100
);

-- C11: Clientes cuyo tipo no coincide con su subtipo (distribuidor/exportador/socio)
SELECT c.* FROM cliente c
WHERE (c.tipo_cliente = 'distribuidor' AND NOT EXISTS (SELECT 1 FROM cliente_distribuidor d WHERE d.id_cliente = c.id_cliente))
   OR (c.tipo_cliente = 'exportador' AND NOT EXISTS (SELECT 1 FROM cliente_exportador e WHERE e.id_cliente = c.id_cliente))
   OR (c.tipo_cliente = 'socio' AND (
         EXISTS (SELECT 1 FROM cliente_distribuidor d WHERE d.id_cliente = c.id_cliente)
      OR EXISTS (SELECT 1 FROM cliente_exportador e WHERE e.id_cliente = c.id_cliente)));

-- C12: Ingresos o transferencias procesados sin renglones
SELECT i.* FROM ingreso i WHERE i.estado = 'procesado' AND NOT EXISTS (SELECT 1 FROM renglon_ingreso ri WHERE ri.cod_ingreso = i.cod_ingreso);
SELECT tr.* FROM transferencia tr WHERE tr.estado = 'procesado' AND NOT EXISTS (SELECT 1 FROM renglon_transferencia rt WHERE rt.nro_transferencia = tr.nro_transferencia);

-- C13: Documentos con fecha futura
SELECT * FROM comprobante WHERE fecha > CURRENT_DATE;
SELECT * FROM ingreso WHERE fecha > CURRENT_DATE;
SELECT * FROM transferencia WHERE fecha_confeccion > CURRENT_DATE;

-- C3b: Filas huérfanas en TODAS las claves foráneas
CREATE OR REPLACE FUNCTION pg_temp.check_fk_orphans()
RETURNS TABLE(fk_name text, tabla_hija text, tabla_padre text, huerfanas bigint)
LANGUAGE plpgsql AS $$
DECLARE
    r RECORD;
    where_nn text;
    where_eq text;
    q text;
    n bigint;
    i int;
BEGIN
    FOR r IN
        SELECT c.conname AS fk_name,
               c.conrelid::regclass::text AS th,
               c.confrelid::regclass::text AS tp,
               array_agg(ah.attname ORDER BY u.ord) AS ch,
               array_agg(ap.attname ORDER BY u.ord) AS cp
        FROM pg_constraint c
        JOIN LATERAL unnest(c.conkey, c.confkey) WITH ORDINALITY AS u(h, p, ord) ON true
        JOIN pg_attribute ah ON ah.attrelid = c.conrelid AND ah.attnum = u.h
        JOIN pg_attribute ap ON ap.attrelid = c.confrelid AND ap.attnum = u.p
        WHERE c.contype = 'f' AND c.connamespace = 'public'::regnamespace
        GROUP BY c.conname, c.conrelid, c.confrelid
    LOOP
        where_nn := '';
        where_eq := '';
        FOR i IN 1..array_length(r.ch, 1) LOOP
            IF i > 1 THEN
                where_nn := where_nn || ' AND ';
                where_eq := where_eq || ' AND ';
            END IF;
            where_nn := where_nn || format('h.%I IS NOT NULL', r.ch[i]);
            where_eq := where_eq || format('h.%I = p.%I', r.ch[i], r.cp[i]);
        END LOOP;
        q := format('SELECT count(*) FROM %s h WHERE %s AND NOT EXISTS (SELECT 1 FROM %s p WHERE %s)', r.th, where_nn, r.tp, where_eq);
        EXECUTE q INTO n;
        fk_name := r.fk_name; tabla_hija := r.th; tabla_padre := r.tp; huerfanas := n;
        RETURN NEXT;
    END LOOP;
END;
$$;

SELECT fk_name, tabla_hija, tabla_padre, huerfanas
FROM pg_temp.check_fk_orphans()
WHERE huerfanas > 0
ORDER BY fk_name;

SELECT count(*) AS fks_revisadas
FROM pg_constraint
WHERE contype = 'f' AND connamespace = 'public'::regnamespace;
