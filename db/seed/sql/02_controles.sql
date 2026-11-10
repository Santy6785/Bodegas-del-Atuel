-- 02_controles.sql – Consultas de control después de la carga histórica
-- (corregido: estados en minúscula según el enum estado_documento;
--  columnas reales del esquema; C7 y C8 con FULL OUTER JOIN)

-- C1: Triggers de usuario que no están habilitados
SELECT c.relname, t.tgname, t.tgenabled
FROM   pg_trigger t
JOIN   pg_class c ON c.oid = t.tgrelid
WHERE  NOT t.tgisinternal
  AND  t.tgenabled <> 'O';

-- C2: Conteo de filas por tabla principal (ejemplo)
SELECT 'cliente' AS tabla, COUNT(*) FROM cliente UNION ALL
SELECT 'vino', COUNT(*) FROM vino UNION ALL
SELECT 'renglon_comprobante', COUNT(*) FROM renglon_comprobante;

-- C3: Filas huérfanas en relaciones principales (ejemplo: renglon_comprobante sin comprobante)
SELECT rc.* FROM renglon_comprobante rc
LEFT JOIN comprobante c ON c.nro_comprobante = rc.nro_comprobante
WHERE c.nro_comprobante IS NULL;

-- C4: Stock negativo en salas
SELECT s.* FROM stock_sala s WHERE s.cantidad < 0;

-- C5: Inconsistencias en totales de comprobantes y subtotales de renglones
-- 5a: Totales del comprobante
SELECT c.* FROM comprobante c
WHERE c.subtotal <> (
  SELECT COALESCE(SUM(rc.cantidad * rc.precio_unitario),0)
  FROM renglon_comprobante rc WHERE rc.nro_comprobante = c.nro_comprobante
) OR c.total <> fn_total_comprobante(c.nro_comprobante);
-- 5b: Subtotales de renglones
SELECT rc.* FROM renglon_comprobante rc
WHERE rc.subtotal <> ROUND(rc.cantidad * rc.precio_unitario * (100 - rc.descuento_pct)/100,2);

-- C6: Descuento_pct diferente al calculado por fn_descuento_cliente
SELECT rc.* FROM renglon_comprobante rc
JOIN comprobante co ON co.nro_comprobante = rc.nro_comprobante
JOIN cliente cl ON cl.id_cliente = co.id_cliente
WHERE rc.descuento_pct <> fn_descuento_cliente(cl.id_cliente);

-- C7: Conservación del stock de sala (stock inicial 0).
-- esperado = transferencias_procesadas_entran - ventas_comprobante_salen, por (id_sala, cod_vino).
-- FULL OUTER JOIN contra stock_sala para detectar pares con movimiento y sin fila de stock.
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
WHERE ss.cantidad IS DISTINCT FROM c.esperado;

-- C8: Conservación del depósito (por vino).
-- esperado = ingresos_procesados_entran - transferencias_procesadas_salen.
-- FULL OUTER JOIN contra stock_deposito.
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
WHERE sd.cantidad IS DISTINCT FROM c.esperado;

-- C9: Stock acumulado que alguna vez queda negativo (ventana, por sala).
-- ingreso no tiene id_sala (su stock va al depósito), por lo que solo
-- transferencia puede particionarse por sala.
WITH movimiento AS (
  SELECT tr.id_sala, rt.cod_vino, tr.fecha_confeccion AS fecha, rt.cantidad
  FROM transferencia tr
  JOIN renglon_transferencia rt ON rt.nro_transferencia = tr.nro_transferencia
  WHERE tr.estado = 'procesado'
),
acumulado AS (
  SELECT id_sala, cod_vino, fecha, cantidad,
         SUM(cantidad) OVER (PARTITION BY id_sala, cod_vino ORDER BY fecha ROWS UNBOUNDED PRECEDING) AS acumulado
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
