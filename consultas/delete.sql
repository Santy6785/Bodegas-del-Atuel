-- ============================================================================
-- MODIFICACIONES DELETE (D1 a D6) EN TRANSACCIÓN — Bodegas del Atuel
-- Patrón: BEGIN -> control previo -> DELETE -> control posterior -> ROLLBACK
-- Valores concretos tomados del dataset de seed.py (bodegas_atuel_bench).
-- Para cambiar un valor, buscar el comentario "PARÁMETRO".
-- Cada bloque termina en ROLLBACK: la base queda igual al final del script.
-- Antigüedad calculada con CURRENT_DATE.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- D1. Borrar los comprobantes con más de 5 años de antigüedad asociados a
--     clientes socios del club.
-- Estrategia: el DELETE sobre comprobante no necesita tocar renglon_comprobante:
--   la FK ON DELETE CASCADE los elimina. Los controles cuentan los renglones
--   antes y después para demostrar el borrado en cascada.
-- ----------------------------------------------------------------------------
BEGIN;
-- control previo: comprobantes a borrar
SELECT COUNT(*) AS comprobantes_a_borrar,
       MIN(c.fecha) AS fecha_mas_antigua,
       MAX(c.fecha) AS fecha_mas_reciente
  FROM comprobante c
  JOIN cliente cl ON cl.id_cliente = c.id_cliente
 WHERE cl.tipo_cliente = 'socio'
   AND c.fecha < CURRENT_DATE - INTERVAL '5 years';
-- control previo: renglones que deberían irse por CASCADE
SELECT COUNT(*) AS renglones_a_borrar
  FROM renglon_comprobante rc
  JOIN comprobante c ON c.nro_comprobante = rc.nro_comprobante
  JOIN cliente cl    ON cl.id_cliente     = c.id_cliente
 WHERE cl.tipo_cliente = 'socio'
   AND c.fecha < CURRENT_DATE - INTERVAL '5 years';
-- control previo: totales de la base
SELECT (SELECT COUNT(*) FROM comprobante)       AS comprobantes_totales,
       (SELECT COUNT(*) FROM renglon_comprobante) AS renglones_totales;

DELETE FROM comprobante c
 USING cliente cl
 WHERE cl.id_cliente = c.id_cliente
   AND cl.tipo_cliente = 'socio'
   AND c.fecha < CURRENT_DATE - INTERVAL '5 years';

-- control posterior: no quedan comprobantes viejos de socios
SELECT COUNT(*) AS comprobantes_viejos_socios_restantes
  FROM comprobante c
  JOIN cliente cl ON cl.id_cliente = c.id_cliente
 WHERE cl.tipo_cliente = 'socio'
   AND c.fecha < CURRENT_DATE - INTERVAL '5 years';
-- control posterior: totales (los renglones bajaron por CASCADE)
SELECT (SELECT COUNT(*) FROM comprobante)       AS comprobantes_totales,
       (SELECT COUNT(*) FROM renglon_comprobante) AS renglones_totales;
ROLLBACK;


-- ----------------------------------------------------------------------------
-- D2. Eliminar las cepas que no componen ningún vino ni están plantadas en
--     ninguna parcela.
-- Estrategia: NOT EXISTS sobre vino_cepa y parcela. Las FK de ambas tablas
--   son ON DELETE RESTRICT, por lo que una cepa en uso no podría borrarse
--   aunque el filtro fallara: la base es la última barrera.
-- ----------------------------------------------------------------------------
BEGIN;
-- control previo: cepas candidatas a borrar
SELECT c.id_cepa, c.nombre, c.tipo
  FROM cepa c
 WHERE NOT EXISTS (SELECT 1 FROM vino_cepa vc WHERE vc.id_cepa = c.id_cepa)
   AND NOT EXISTS (SELECT 1 FROM parcela p    WHERE p.id_cepa  = c.id_cepa)
 ORDER BY c.id_cepa;
-- control previo: cantidad total de cepas
SELECT COUNT(*) AS cepas_totales_previas FROM cepa;

DELETE FROM cepa c
 WHERE NOT EXISTS (SELECT 1 FROM vino_cepa vc WHERE vc.id_cepa = c.id_cepa)
   AND NOT EXISTS (SELECT 1 FROM parcela p    WHERE p.id_cepa  = c.id_cepa);

-- control posterior: no quedan cepas huérfanas y total actualizado
SELECT COUNT(*) AS cepas_huerfanas_restantes
  FROM cepa c
 WHERE NOT EXISTS (SELECT 1 FROM vino_cepa vc WHERE vc.id_cepa = c.id_cepa)
   AND NOT EXISTS (SELECT 1 FROM parcela p    WHERE p.id_cepa  = c.id_cepa);
SELECT COUNT(*) AS cepas_totales_posteriores FROM cepa;
ROLLBACK;


-- ----------------------------------------------------------------------------
-- D3. La sala de una localidad determinada fue dada de baja: eliminar los
--     empleados de esa sala que trabajaron menos de dos años.
-- Estrategia: DELETE con USING sobre sala_venta para filtrar por localidad.
--   No se borra la sala, solo sus empleados recientes (el enunciado no pide
--   borrar la sala). Empleado no tiene dependientes en la base.
-- PARÁMETRO: codigo_postal de la localidad ('5505', General Alvear).
-- ----------------------------------------------------------------------------
BEGIN;
-- control previo: salas de la localidad y sus empleados
SELECT s.id_sala, s.calle, s.numero, s.codigo_postal,
       COUNT(e.cuit) AS empleados_en_sala
  FROM sala_venta s
  LEFT JOIN empleado e ON e.id_sala = s.id_sala
 WHERE s.codigo_postal = '5505'                -- PARÁMETRO: codigo_postal
 GROUP BY s.id_sala, s.calle, s.numero, s.codigo_postal
 ORDER BY s.id_sala;
-- control previo: empleados a borrar (menos de dos años de antigüedad)
SELECT e.cuit, e.nombre, e.fecha_ingreso, e.id_sala
  FROM empleado e
  JOIN sala_venta s ON s.id_sala = e.id_sala
 WHERE s.codigo_postal = '5505'                -- PARÁMETRO: codigo_postal
   AND e.fecha_ingreso > CURRENT_DATE - INTERVAL '2 years'
 ORDER BY e.id_sala, e.fecha_ingreso;
-- control previo: total de empleados
SELECT COUNT(*) AS empleados_totales_previos FROM empleado;

DELETE FROM empleado e
 USING sala_venta s
 WHERE s.id_sala = e.id_sala
   AND s.codigo_postal = '5505'                -- PARÁMETRO: codigo_postal
   AND e.fecha_ingreso > CURRENT_DATE - INTERVAL '2 years';

-- control posterior: no quedan empleados recientes en esa localidad
SELECT COUNT(*) AS empleados_recientes_restantes
  FROM empleado e
  JOIN sala_venta s ON s.id_sala = e.id_sala
 WHERE s.codigo_postal = '5505'
   AND e.fecha_ingreso > CURRENT_DATE - INTERVAL '2 years';
SELECT COUNT(*) AS empleados_totales_posteriores FROM empleado;
ROLLBACK;


-- ----------------------------------------------------------------------------
-- D4. Borrar los clientes socios que nunca compraron y se dieron de alta
--     hace más de 5 años.
-- Estrategia: NOT EXISTS sobre comprobante (el cliente no tiene ventas).
--   Los socios no tienen fila en subtipos, así que no hay CASCADE pendiente.
--   Un cliente con compras no se podría borrar: comprobante.id_cliente es
--   ON DELETE RESTRICT.
-- ----------------------------------------------------------------------------
BEGIN;
-- control previo: clientes a borrar
SELECT cl.id_cliente, cl.apellido_razon_social, cl.nombre,
       cl.fecha_alta, cl.codigo_postal
  FROM cliente cl
 WHERE cl.tipo_cliente = 'socio'
   AND cl.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
   AND NOT EXISTS (SELECT 1 FROM comprobante c WHERE c.id_cliente = cl.id_cliente)
 ORDER BY cl.id_cliente;
-- control previo: total de clientes
SELECT COUNT(*) AS clientes_totales_previos FROM cliente;

DELETE FROM cliente cl
 WHERE cl.tipo_cliente = 'socio'
   AND cl.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
   AND NOT EXISTS (SELECT 1 FROM comprobante c WHERE c.id_cliente = cl.id_cliente);

-- control posterior: no quedan socios sin compras dados de alta hace más de 5 años
SELECT COUNT(*) AS socios_sin_compras_antiguos_restantes
  FROM cliente cl
 WHERE cl.tipo_cliente = 'socio'
   AND cl.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
   AND NOT EXISTS (SELECT 1 FROM comprobante c WHERE c.id_cliente = cl.id_cliente);
SELECT COUNT(*) AS clientes_totales_posteriores FROM cliente;
ROLLBACK;


-- ----------------------------------------------------------------------------
-- D5. Eliminar los ingresos en estado procesado de hace más de 365 días.
-- Estrategia: DELETE sobre ingreso. renglon_ingreso se borra por CASCADE.
--   El trigger trg_renglon_ingreso_confeccion no bloquea ese borrado: al
--   borrarse el renglón en cascada, la cabecera ya no existe y el trigger no
--   encuentra estado que impedirlo.
-- ----------------------------------------------------------------------------
BEGIN;
-- control previo: ingresos a borrar
SELECT i.cod_ingreso, i.fecha, i.estado, i.cuit_bodega
  FROM ingreso i
 WHERE i.estado = 'procesado'
   AND i.fecha < CURRENT_DATE - INTERVAL '365 days'
 ORDER BY i.cod_ingreso;
-- control previo: renglones que deberían irse por CASCADE
SELECT COUNT(*) AS renglones_a_borrar
  FROM renglon_ingreso ri
  JOIN ingreso i ON i.cod_ingreso = ri.cod_ingreso
 WHERE i.estado = 'procesado'
   AND i.fecha < CURRENT_DATE - INTERVAL '365 days';
-- control previo: totales
SELECT (SELECT COUNT(*) FROM ingreso)          AS ingresos_totales,
       (SELECT COUNT(*) FROM renglon_ingreso)  AS renglones_ingreso_totales;

DELETE FROM ingreso i
 WHERE i.estado = 'procesado'
   AND i.fecha < CURRENT_DATE - INTERVAL '365 days';

-- control posterior: no quedan procesados viejos
SELECT COUNT(*) AS procesados_viejos_restantes
  FROM ingreso i
 WHERE i.estado = 'procesado'
   AND i.fecha < CURRENT_DATE - INTERVAL '365 days';
-- control posterior: totales (los renglones bajaron por CASCADE)
SELECT (SELECT COUNT(*) FROM ingreso)          AS ingresos_totales,
       (SELECT COUNT(*) FROM renglon_ingreso)  AS renglones_ingreso_totales;
ROLLBACK;


-- ----------------------------------------------------------------------------
-- D6. Borrar los clientes socios sin compras que viven en una localidad
--     específica.
-- Estrategia: igual a D4, con un filtro adicional por codigo_postal.
--   El enunciado no pide antigüedad, así que el filtro de fecha_alta no aplica.
-- PARÁMETRO: codigo_postal de la localidad ('5505', General Alvear).
-- ----------------------------------------------------------------------------
BEGIN;
-- control previo: clientes a borrar
SELECT cl.id_cliente, cl.apellido_razon_social, cl.nombre,
       cl.fecha_alta, cl.codigo_postal
  FROM cliente cl
 WHERE cl.tipo_cliente = 'socio'
   AND cl.codigo_postal = '5505'               -- PARÁMETRO: codigo_postal
   AND NOT EXISTS (SELECT 1 FROM comprobante c WHERE c.id_cliente = cl.id_cliente)
 ORDER BY cl.id_cliente;
-- control previo: total de clientes
SELECT COUNT(*) AS clientes_totales_previos FROM cliente;

DELETE FROM cliente cl
 WHERE cl.tipo_cliente = 'socio'
   AND cl.codigo_postal = '5505'               -- PARÁMETRO: codigo_postal
   AND NOT EXISTS (SELECT 1 FROM comprobante c WHERE c.id_cliente = cl.id_cliente);

-- control posterior: no quedan socios sin compras en esa localidad
SELECT COUNT(*) AS socios_sin_compras_localidad_restantes
  FROM cliente cl
 WHERE cl.tipo_cliente = 'socio'
   AND cl.codigo_postal = '5505'
   AND NOT EXISTS (SELECT 1 FROM comprobante c WHERE c.id_cliente = cl.id_cliente);
SELECT COUNT(*) AS clientes_totales_posteriores FROM cliente;
ROLLBACK;