-- ============================================================================
-- MODIFICACIONES UPDATE (U1 a U5) EN TRANSACCIÓN — Bodegas del Atuel
-- Nota U6: reformulada el 2026-11-08 a consulta de lectura (U6-R en select.sql).
-- Patrón: BEGIN -> control previo -> sentencia -> control posterior -> ROLLBACK
-- ============================================================================

-- U1. Actualización del precio unitario de un vino y disparo de auditoría.
BEGIN;
SELECT cod_vino, nombre, precio AS precio_previo FROM vino WHERE cod_vino = 1;
SELECT COUNT(*) AS auditorias_previas FROM auditoria_precio WHERE cod_vino = 1;
UPDATE vino SET precio = precio + 500.00 WHERE cod_vino = 1;
SELECT cod_vino, nombre, precio AS precio_posterior FROM vino WHERE cod_vino = 1;
SELECT cod_vino, precio_anterior, precio_nuevo, usuario FROM auditoria_precio WHERE cod_vino = 1 ORDER BY id_auditoria DESC LIMIT 1;
ROLLBACK;

-- U2. Transición de ingreso (en_confeccion -> terminado -> procesado, RN-10) y stock.
BEGIN;
WITH ins AS (
    INSERT INTO ingreso (fecha, estado, cod_transportista, cuit_bodega)
    VALUES (CURRENT_DATE, 'en_confeccion', 1, '20123456781')
    RETURNING cod_ingreso
)
INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
SELECT cod_ingreso, 2, 50 FROM ins;
SELECT cod_ingreso, estado AS estado_previo FROM ingreso WHERE estado = 'en_confeccion';
SELECT cod_vino, cantidad AS stock_previo FROM stock_deposito WHERE cod_vino = 2;
UPDATE ingreso SET estado = 'terminado' WHERE estado = 'en_confeccion';
UPDATE ingreso SET estado = 'procesado' WHERE estado = 'terminado';
SELECT COUNT(*) AS pendientes_posteriores FROM ingreso WHERE estado <> 'procesado';
SELECT cod_vino, cantidad AS stock_posterior FROM stock_deposito WHERE cod_vino = 2;
ROLLBACK;

-- U3. Actualización de CUIT de bodega con propagación ON UPDATE CASCADE a vino.
BEGIN;
SELECT cuit, razon_social FROM bodega WHERE cuit = '20123456781';
SELECT COUNT(*) AS vinos_asociados_previo FROM vino WHERE cuit_bodega = '20123456781';
UPDATE bodega SET cuit = '20999999991' WHERE cuit = '20123456781';
SELECT COUNT(*) AS vinos_con_cuit_nuevo FROM vino WHERE cuit_bodega = '20999999991';
SELECT COUNT(*) AS vinos_con_cuit_viejo FROM vino WHERE cuit_bodega = '20123456781';
ROLLBACK;

-- U4. Actualización masiva controlada de dirección para clientes del CP 5561.
BEGIN;
SELECT COUNT(*) AS clientes_cp_previo FROM cliente WHERE codigo_postal = '5561';
UPDATE cliente SET direccion = direccion || ' (Verificado)' WHERE codigo_postal = '5561';
SELECT COUNT(*) AS clientes_actualizados FROM cliente WHERE codigo_postal = '5561' AND direccion LIKE '%(Verificado)';
ROLLBACK;

-- U5. Transición de transferencia (en_confeccion -> terminado -> procesado, RN-10).
BEGIN;
WITH tr AS (
    INSERT INTO transferencia (id_sala, fecha_confeccion, estado)
    VALUES (1, CURRENT_DATE, 'en_confeccion')
    RETURNING nro_transferencia
)
INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
SELECT nro_transferencia, 3, 24 FROM tr;
SELECT cantidad AS deposito_previo FROM stock_deposito WHERE cod_vino = 3;
SELECT fn_stock_sala(1, 3) AS sala_previo;
UPDATE transferencia SET estado = 'terminado' WHERE estado = 'en_confeccion';
UPDATE transferencia SET estado = 'procesado' WHERE estado = 'terminado';
SELECT cantidad AS deposito_posterior FROM stock_deposito WHERE cod_vino = 3;
SELECT fn_stock_sala(1, 3) AS sala_posterior;
ROLLBACK;