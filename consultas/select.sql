-- ============================================================================
-- CONSULTAS DE SELECCIÓN (S1 a S8 + U6-R) — Bodegas del Atuel
-- ============================================================================

-- S1. Vinos más vendidos según cantidad de botellas despachadas.
-- Enunciado: Obtener el ranking de los 10 vinos más vendidos ordenados por la
--            cantidad total de botellas despachadas en comprobantes de venta.
-- Estrategia: INNER JOIN entre renglon_comprobante y vino agrupando por
--             cod_vino y nombre. Se suma rc.cantidad con COALESCE(..., 0) y se
--             ordena descendentemente por botellas_vendidas (desempatando por
--             cod_vino ASC). Aprovecha el índice covering
--             idx_renglon_comprobante_cod_vino cuando el planificador estima
--             menor costo por Index Only Scan.
SELECT rc.cod_vino,
       v.nombre,
       COALESCE(SUM(rc.cantidad), 0)::BIGINT AS botellas_vendidas
  FROM renglon_comprobante rc
  JOIN vino v ON v.cod_vino = rc.cod_vino
 GROUP BY rc.cod_vino, v.nombre
 ORDER BY botellas_vendidas DESC, rc.cod_vino ASC
 LIMIT 10;

-- S2. Catálogo de vinos con composición varietal y stock total disponible.
-- Enunciado: Listar todos los vinos registrados junto con el detalle de sus
--            cepas y porcentajes de corte, su añada, precio unitario y el
--            stock total actual (depósito central más todas las salas de venta).
-- Estrategia: LEFT JOIN desde vino hacia vino_cepa, cepa y la vista derivada
--             vw_stock_total_vino para no excluir vinos sin cepas cargadas o
--             sin stock. Se utiliza STRING_AGG ordenado por porcentaje DESC
--             para consolidar la composición varietal en una sola fila por vino.
SELECT v.cod_vino,
       v.nombre,
       v.tipo,
       v.anada,
       v.precio,
       COALESCE(
           STRING_AGG(
               c.nombre || ' (' || vc.porcentaje || '%)',
               ', ' ORDER BY vc.porcentaje DESC, c.nombre ASC
           ),
           'Sin composición registrada'
       ) AS composicion_varietal,
       COALESCE(st.stock_total, 0)::BIGINT AS stock_total
  FROM vino v
  LEFT JOIN vino_cepa vc ON vc.cod_vino = v.cod_vino
  LEFT JOIN cepa c ON c.id_cepa = vc.id_cepa
  LEFT JOIN vw_stock_total_vino st ON st.cod_vino = v.cod_vino
 GROUP BY v.cod_vino, v.nombre, v.tipo, v.anada, v.precio, st.stock_total
 ORDER BY v.cod_vino ASC;

-- S3. Clientes que compraron en una sala de venta determinada.
-- Enunciado: Listar los clientes distintos que realizaron al menos una compra
--            en la sala de venta indicada (ejemplo: id_sala = 1), mostrando
--            cantidad de comprobantes emitidos y monto acumulado en esa sala.
-- Estrategia: JOIN entre cliente, comprobante y sala_venta filtrando por
--             c.id_sala = 1. Utiliza el índice compuesto
--             idx_comprobante_sala_fecha (id_sala, fecha) para localizar
--             directamente los comprobantes de la sala sin recorrer toda la tabla.
SELECT cl.id_cliente,
       cl.apellido_razon_social,
       cl.nombre,
       cl.tipo_cliente,
       COUNT(c.nro_comprobante)::BIGINT AS cantidad_compras,
       COALESCE(SUM(c.total), 0)::NUMERIC(12,2) AS monto_acumulado
  FROM cliente cl
  JOIN comprobante c ON c.id_cliente = cl.id_cliente
  JOIN sala_venta s ON s.id_sala = c.id_sala
 WHERE c.id_sala = 1
 GROUP BY cl.id_cliente, cl.apellido_razon_social, cl.nombre, cl.tipo_cliente
 ORDER BY monto_acumulado DESC, cl.id_cliente ASC;

-- S4. Ingresos de vinos a depósito central pendientes de procesamiento.
-- Enunciado: Obtener los remitos de ingreso de vinos al depósito central cuyo
--            estado aún no fue procesado (estado <> 'procesado'), incluyendo la
--            empresa transportista, la bodega origen y el total de botellas.
-- Estrategia: JOIN de ingreso con transportista y bodega (y LEFT JOIN a
--             renglon_ingreso para totalizar botellas) filtrando por el
--             predicado de alta selectividad estado <> 'procesado', ordenados
--             cronológicamente por fecha de ingreso.
SELECT i.cod_ingreso,
       i.fecha,
       i.estado,
       t.cod_transportista,
       t.razon_social AS transportista,
       b.cuit AS cuit_bodega,
       b.razon_social AS bodega,
       COALESCE(SUM(ri.cantidad), 0)::BIGINT AS total_botellas
  FROM ingreso i
  JOIN transportista t ON t.cod_transportista = i.cod_transportista
  JOIN bodega b ON b.cuit = i.cuit_bodega
  LEFT JOIN renglon_ingreso ri ON ri.cod_ingreso = i.cod_ingreso
 WHERE i.estado <> 'procesado'
 GROUP BY i.cod_ingreso, i.fecha, i.estado, t.cod_transportista, t.razon_social, b.cuit, b.razon_social
 ORDER BY i.fecha ASC, i.cod_ingreso ASC;

-- S5. Transferencias de vinos hacia salas de venta pendientes de procesamiento.
-- Enunciado: Listar las transferencias internas de mercadería desde depósito
--            central hacia salas de venta que permanecen pendientes
--            (estado <> 'procesado'), detallando sala destino y cantidad total.
-- Estrategia: JOIN de transferencia con sala_venta (y LEFT JOIN a
--             renglon_transferencia) filtrando por estado <> 'procesado'.
--             Aprovecha directamente el índice parcial
--             idx_transferencia_pendiente_sala ON transferencia (id_sala,
--             fecha_confeccion) WHERE estado <> 'procesado', evitando escanear
--             el histórico ya procesado.
SELECT tr.nro_transferencia,
       tr.fecha_confeccion,
       tr.estado,
       s.id_sala,
       s.calle || ' ' || s.numero AS direccion_sala,
       COALESCE(SUM(rt.cantidad), 0)::BIGINT AS total_botellas
  FROM transferencia tr
  JOIN sala_venta s ON s.id_sala = tr.id_sala
  LEFT JOIN renglon_transferencia rt ON rt.nro_transferencia = tr.nro_transferencia
 WHERE tr.estado <> 'procesado'
 GROUP BY tr.nro_transferencia, tr.fecha_confeccion, tr.estado, s.id_sala, s.calle, s.numero
 ORDER BY tr.fecha_confeccion ASC, tr.nro_transferencia ASC;

-- S6. Vinos sin stock en una sala de venta pero disponibles en depósito central.
-- Enunciado: Identificar los vinos cuyo stock actual en una sala de venta
--            específica (ejemplo: id_sala = 1) es igual a 0, pero que cuentan
--            con stock mayor a 0 en el depósito central para reposición.
-- Estrategia: LEFT JOIN entre vino y stock_deposito filtrando mediante la
--             función almacenada fn_stock_sala(1, v.cod_vino) = 0 (que
--             consolida transferencias recibidas menos ventas en la sala) y
--             COALESCE(sd.cantidad, 0) > 0 en depósito central.
SELECT v.cod_vino,
       v.nombre,
       COALESCE(sd.cantidad, 0)::BIGINT AS stock_deposito
  FROM vino v
  LEFT JOIN stock_deposito sd ON sd.cod_vino = v.cod_vino
 WHERE fn_stock_sala(1, v.cod_vino) = 0
   AND COALESCE(sd.cantidad, 0) > 0
 ORDER BY v.cod_vino ASC;

-- S7. Empresa/s transportista/s con mayor cantidad de ingresos en el último mes.
-- Enunciado: Determinar qué empresa o empresas transportistas registraron la
--            mayor cantidad de ingresos al depósito central durante el último
--            mes calendario (CURRENT_DATE - INTERVAL '1 month'), contemplando
--            posibles empates en el primer puesto.
-- Estrategia: CTE (ranking) que une transportista con ingreso filtrando por
--             i.fecha >= CURRENT_DATE - INTERVAL '1 month', agrupa por
--             transportista y aplica la función ventana DENSE_RANK() OVER
--             (ORDER BY COUNT(i.cod_ingreso) DESC) para devolver todos los
--             transportistas empatados con puesto = 1.
WITH ranking AS (
    SELECT t.cod_transportista,
           t.razon_social,
           COUNT(i.cod_ingreso)::BIGINT AS cantidad_ingresos,
           DENSE_RANK() OVER (ORDER BY COUNT(i.cod_ingreso) DESC) AS puesto
      FROM transportista t
      JOIN ingreso i ON i.cod_transportista = t.cod_transportista
     WHERE i.fecha >= CURRENT_DATE - INTERVAL '1 month'
     GROUP BY t.cod_transportista, t.razon_social
    HAVING COUNT(i.cod_ingreso) > 0
)
SELECT cod_transportista,
       razon_social,
       cantidad_ingresos
  FROM ranking
 WHERE puesto = 1
 ORDER BY cod_transportista ASC;

-- S8. Monto total facturado por sala de venta en un período.
-- Enunciado: Calcular el monto total facturado por cada sala de venta durante
--            el último trimestre (CURRENT_DATE - INTERVAL '3 months'),
--            incluyendo aquellas salas que no hayan registrado ventas en el
--            período con total 0.00.
-- Estrategia: LEFT JOIN desde sala_venta hacia comprobante colocando el filtro
--             temporal (c.fecha >= CURRENT_DATE - INTERVAL '3 months') dentro
--             de la cláusula ON para preservar todas las salas en el resultado.
--             Suma el atributo comprobante.total y aprovecha el índice compuesto
--             idx_comprobante_sala_fecha (id_sala, fecha).
SELECT s.id_sala,
       s.calle,
       s.numero,
       COALESCE(SUM(c.total), 0)::NUMERIC(12,2) AS monto_total
  FROM sala_venta s
  LEFT JOIN comprobante c
    ON c.id_sala = s.id_sala
   AND c.fecha >= CURRENT_DATE - INTERVAL '3 months'
 GROUP BY s.id_sala, s.calle, s.numero
 ORDER BY monto_total DESC, s.id_sala ASC;

-- U6-R. Exportadores con más de 3 permisos de exportación y su descuento vigente.
-- Enunciado: Reformulación de la consigna U6 (antes de subir el descuento al 35 %).
-- Estrategia: JOIN a cliente_exportador, LEFT JOIN a permiso_exportacion con
--             agregación, HAVING sobre el conteo de todos los permisos cargados.
--             El descuento se obtiene de fn_descuento_cliente, no se calcula aquí.
SELECT c.id_cliente,
       c.apellido_razon_social,
       c.nombre,
       COUNT(p.codigo) AS cantidad_permisos,
       fn_descuento_cliente(c.id_cliente) AS descuento_pct
  FROM cliente c
  JOIN cliente_exportador e ON e.id_cliente = c.id_cliente
  LEFT JOIN permiso_exportacion p ON p.id_cliente = c.id_cliente
 GROUP BY c.id_cliente, c.apellido_razon_social, c.nombre
HAVING COUNT(p.codigo) > 3
 ORDER BY c.id_cliente;