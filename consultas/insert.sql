-- ============================================================================
-- MODIFICACIONES INSERT (I1 a I3) EN TRANSACCIÓN — Bodegas del Atuel
-- Patrón: BEGIN -> control previo -> sentencia -> control posterior -> ROLLBACK
-- ============================================================================

-- I1. Alta de ingreso en confección con su renglón de detalle (RN-12).
BEGIN;
SELECT COUNT(*) AS ingresos_previos FROM ingreso;
SELECT COUNT(*) AS renglones_previos FROM renglon_ingreso;
WITH nuevo_ingreso AS (
    INSERT INTO ingreso (fecha, estado, cod_transportista, cuit_bodega)
    VALUES (CURRENT_DATE, 'en_confeccion', 1, '20123456781')
    RETURNING cod_ingreso
)
INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
SELECT cod_ingreso, 1, 120 FROM nuevo_ingreso;
SELECT COUNT(*) AS ingresos_posteriores FROM ingreso;
SELECT COUNT(*) AS renglones_posteriores FROM renglon_ingreso;
ROLLBACK;

-- I2. Alta de comprobante de venta en sala con descuento de stock.
BEGIN;
SELECT COUNT(*) AS comprobantes_previos FROM comprobante;
SELECT fn_stock_sala(1, 1) AS stock_sala_previo;
WITH nuevo_comp AS (
    INSERT INTO comprobante (fecha, id_cliente, id_sala)
    VALUES (CURRENT_DATE, 1, 1)
    RETURNING nro_comprobante
)
INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento_pct, subtotal)
SELECT nro_comp.nro_comprobante, 1, 6, v.precio, 0, ROUND(6 * v.precio, 2)
  FROM nuevo_comp nro_comp
  JOIN vino v ON v.cod_vino = 1;
SELECT COUNT(*) AS comprobantes_posteriores FROM comprobante;
SELECT fn_stock_sala(1, 1) AS stock_sala_posterior;
ROLLBACK;

-- I3. Alta de permiso de exportación y actualización automática de descuento (U6).
BEGIN;
SELECT e.id_cliente, COUNT(p.codigo) AS permisos_previos, e.porcentaje_descuento AS descuento_previo
  FROM cliente_exportador e
  LEFT JOIN permiso_exportacion p ON p.id_cliente = e.id_cliente
 GROUP BY e.id_cliente, e.porcentaje_descuento
HAVING COUNT(p.codigo) = 3
 ORDER BY e.id_cliente
 LIMIT 1;
WITH exp_objetivo AS (
    SELECT e.id_cliente
      FROM cliente_exportador e
      LEFT JOIN permiso_exportacion p ON p.id_cliente = e.id_cliente
     GROUP BY e.id_cliente
    HAVING COUNT(p.codigo) = 3
     ORDER BY e.id_cliente
     LIMIT 1
)
INSERT INTO permiso_exportacion (id_cliente, codigo, fecha_emision, fecha_vencimiento)
SELECT id_cliente, 'PERM-TEST-TX-999', CURRENT_DATE, CURRENT_DATE + INTERVAL '1 year'
  FROM exp_objetivo;
SELECT e.id_cliente, COUNT(p.codigo) AS permisos_posteriores, e.porcentaje_descuento AS descuento_posterior
  FROM cliente_exportador e
  JOIN permiso_exportacion p ON p.id_cliente = e.id_cliente
 WHERE p.codigo = 'PERM-TEST-TX-999'
 GROUP BY e.id_cliente, e.porcentaje_descuento;
ROLLBACK;