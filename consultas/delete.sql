-- ============================================================================
-- MODIFICACIONES DELETE (D1 a D3) EN TRANSACCIÓN — Bodegas del Atuel
-- Patrón: BEGIN -> control previo -> sentencia -> control posterior -> ROLLBACK
-- ============================================================================

-- D1. Eliminación de un comprobante de venta y borrado en cascada de sus renglones.
BEGIN;
-- Control previo
SELECT COUNT(*) AS comprobantes_previos FROM comprobante WHERE nro_comprobante = 1;
SELECT COUNT(*) AS renglones_previos FROM renglon_comprobante WHERE nro_comprobante = 1;

-- Sentencia (1 fila afectada en comprobante -> ON DELETE CASCADE en renglon_comprobante)
DELETE FROM comprobante
 WHERE nro_comprobante = 1;

-- Control posterior
SELECT COUNT(*) AS comprobantes_posteriores FROM comprobante WHERE nro_comprobante = 1;
SELECT COUNT(*) AS renglones_posteriores FROM renglon_comprobante WHERE nro_comprobante = 1;
ROLLBACK;

-- D2. Eliminación de un permiso de exportación y recálculo de descuento (U6).
BEGIN;
-- Control previo (cliente con 4 permisos -> descuento 35.00 %)
SELECT e.id_cliente, COUNT(p.codigo) AS permisos_previos, e.porcentaje_descuento AS descuento_previo
  FROM cliente_exportador e
  JOIN permiso_exportacion p ON p.id_cliente = e.id_cliente
 WHERE e.id_cliente = 3
 GROUP BY e.id_cliente, e.porcentaje_descuento;

-- Sentencia (1 fila afectada en permiso_exportacion -> baja descuento a 30.00 %)
DELETE FROM permiso_exportacion
 WHERE codigo = (
     SELECT MIN(codigo)
       FROM permiso_exportacion
      WHERE id_cliente = 3
 );

-- Control posterior (permisos = 3 -> porcentaje_descuento = 30.00 %)
SELECT e.id_cliente, COUNT(p.codigo) AS permisos_posteriores, e.porcentaje_descuento AS descuento_posterior
  FROM cliente_exportador e
  JOIN permiso_exportacion p ON p.id_cliente = e.id_cliente
 WHERE e.id_cliente = 3
 GROUP BY e.id_cliente, e.porcentaje_descuento;
ROLLBACK;

-- D3. Eliminación de cepa sin parcelas implantadas (tras alta temporal en transacción).
BEGIN;
INSERT INTO cepa (nombre, tipo) VALUES ('Cepa Temporal Prueba', 'tinta');

-- Control previo
SELECT COUNT(*) AS cepas_prueba_previo FROM cepa WHERE nombre = 'Cepa Temporal Prueba';

-- Sentencia (1 fila afectada en cepa; si tuviera parcelas fallaría por ON DELETE RESTRICT)
DELETE FROM cepa
 WHERE nombre = 'Cepa Temporal Prueba';

-- Control posterior
SELECT COUNT(*) AS cepas_prueba_posterior FROM cepa WHERE nombre = 'Cepa Temporal Prueba';
ROLLBACK;