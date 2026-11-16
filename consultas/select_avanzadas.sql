-- ============================================================================
-- CONSULTAS AVANZADAS (S9 a S12) — Bodegas del Atuel
-- ============================================================================

-- S9. Ficha integral de cada vino con bodega, cepas, maridajes y stock.
-- Enunciado: Obtener la ficha completa de los vinos registrados, incluyendo su
--            bodega elaboradora, composición varietal porcentual, maridajes
--            recomendados (con temperatura de servicio) y el desglose de
--            stock en depósito central, salas de venta y total general.
-- Estrategia: LEFT JOIN desde vino hacia bodega, vino_cepa/cepa,
--             vino_maridaje/maridaje y la vista derivada vw_stock_total_vino.
--             Se emplea STRING_AGG(DISTINCT ...) para consolidar tanto las
--             cepas como los maridajes en una sola fila por vino sin producir
--             producto cartesiano entre ambas relaciones N:M.
SELECT v.cod_vino,
       v.nombre AS vino,
       v.tipo,
       v.anada,
       v.volumen_ml,
       v.graduacion,
       v.precio,
       b.razon_social AS bodega,
       COALESCE(
           STRING_AGG(
               DISTINCT c.nombre || ' (' || vc.porcentaje || '%)',
               ', '
           ),
           'Sin composición'
       ) AS cepas,
       COALESCE(
           STRING_AGG(
               DISTINCT m.nombre || ' (' || m.temperatura_servicio || ' °C)',
               ', '
           ),
           'Sin maridajes'
       ) AS maridajes,
       COALESCE(st.stock_deposito, 0)::BIGINT AS stock_deposito,
       COALESCE(st.stock_salas, 0)::BIGINT AS stock_salas,
       COALESCE(st.stock_total, 0)::BIGINT AS stock_total
  FROM vino v
  JOIN bodega b ON b.cuit = v.cuit_bodega
  LEFT JOIN vino_cepa vc ON vc.cod_vino = v.cod_vino
  LEFT JOIN cepa c ON c.id_cepa = vc.id_cepa
  LEFT JOIN vino_maridaje vm ON vm.cod_vino = v.cod_vino
  LEFT JOIN maridaje m ON m.id_maridaje = vm.id_maridaje
  LEFT JOIN vw_stock_total_vino st ON st.cod_vino = v.cod_vino
 GROUP BY v.cod_vino, v.nombre, v.tipo, v.anada, v.volumen_ml, v.graduacion,
          v.precio, b.razon_social, st.stock_deposito, st.stock_salas, st.stock_total
 ORDER BY v.cod_vino ASC;

-- S10. Rendimiento agrícola (kg/ha) por parcela y campaña comparado con su cepa.
-- Enunciado: Calcular el rendimiento en kilogramos por hectárea (kg/ha) de
--            cada parcela en cada campaña cosechada, y compararlo contra el
--            rendimiento promedio de las parcelas implantadas con la misma cepa
--            en esa campaña.
-- Estrategia: CTE (rendimiento_parcela) que une finca, parcela, cepa y
--             lote_uva para derivar el atributo calculado rendimiento_kg_ha =
--             kilos / superficie_ha, combinado con una subconsulta
--             correlacionada que obtiene el promedio de kg/ha de la misma cepa
--             y campaña para identificar parcelas sobre el promedio varietal.
WITH rendimiento_parcela AS (
    SELECT f.id_finca,
           f.nombre AS finca,
           p.nro_parcela,
           p.superficie_ha,
           c.id_cepa,
           c.nombre AS cepa,
           lu.campania,
           SUM(lu.kilos)::NUMERIC(12,2) AS kilos_cosechados,
           ROUND(SUM(lu.kilos) / p.superficie_ha, 2) AS rendimiento_kg_ha
      FROM parcela p
      JOIN finca f ON f.id_finca = p.id_finca
      JOIN cepa c ON c.id_cepa = p.id_cepa
      JOIN lote_uva lu ON lu.id_finca = p.id_finca AND lu.nro_parcela = p.nro_parcela
     GROUP BY f.id_finca, f.nombre, p.nro_parcela, p.superficie_ha,
              c.id_cepa, c.nombre, lu.campania
)
SELECT rp.finca,
       rp.nro_parcela,
       rp.cepa,
       rp.campania,
       rp.superficie_ha,
       rp.kilos_cosechados,
       rp.rendimiento_kg_ha,
       (
           SELECT ROUND(AVG(rp2.rendimiento_kg_ha), 2)
             FROM rendimiento_parcela rp2
            WHERE rp2.id_cepa = rp.id_cepa
              AND rp2.campania = rp.campania
       ) AS promedio_cepa_campania_kg_ha
  FROM rendimiento_parcela rp
 ORDER BY rp.campania DESC, rp.rendimiento_kg_ha DESC, rp.id_finca ASC, rp.nro_parcela ASC;

-- S11. Ranking mensual de facturación por sala de venta y suma acumulada.
-- Enunciado: Obtener la facturación mensual de cada sala de venta durante los
--            últimos 6 meses, indicando su posición en el ranking mensual entre
--            salas (RANK) y el monto acumulado histórico de esa sala a lo largo
--            del período evaluado.
-- Estrategia: CTE (ventas_mensuales) que agrupa comprobante por id_sala y mes
--             (DATE_TRUNC('month', fecha)) aprovechando el índice compuesto
--             idx_comprobante_sala_fecha. Luego aplica dos funciones ventana:
--             RANK() OVER (PARTITION BY mes ORDER BY monto_mensual DESC) para
--             el puesto mensual y SUM(monto_mensual) OVER (PARTITION BY id_sala
--             ORDER BY mes) para la suma acumulada progresiva por sala.
WITH ventas_mensuales AS (
    SELECT s.id_sala,
           s.calle || ' ' || s.numero AS sala,
           DATE_TRUNC('month', c.fecha)::DATE AS mes,
           COUNT(c.nro_comprobante)::BIGINT AS cantidad_comprobantes,
           COALESCE(SUM(c.total), 0)::NUMERIC(14,2) AS monto_mensual
      FROM sala_venta s
      JOIN comprobante c ON c.id_sala = s.id_sala
     WHERE c.fecha >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '5 months'
     GROUP BY s.id_sala, s.calle, s.numero, DATE_TRUNC('month', c.fecha)
)
SELECT mes,
       id_sala,
       sala,
       cantidad_comprobantes,
       monto_mensual,
       RANK() OVER (PARTITION BY mes ORDER BY monto_mensual DESC) AS ranking_mensual,
       SUM(monto_mensual) OVER (
           PARTITION BY id_sala
           ORDER BY mes ASC
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       )::NUMERIC(14,2) AS suma_acumulada_sala
  FROM ventas_mensuales
 ORDER BY mes DESC, ranking_mensual ASC, id_sala ASC;

-- S12. División relacional: clientes que compraron TODOS los vinos espumantes.
-- Enunciado: Identificar los clientes que adquirieron al menos una unidad de
--            TODOS los vinos de tipo 'espumante' registrados en el catálogo de
--            la bodega.
-- Estrategia: División relacional clásica en SQL estándar mediante doble
--             NOT EXISTS: se seleccionan los clientes para los cuales NO EXISTE
--             ningún vino v con v.tipo = 'espumante' tal que NO EXISTA un
--             renglón de comprobante emitido a ese cliente conteniendo dicho
--             cod_vino. Se incluye guarda EXISTS sobre el conjunto divisor para
--             evitar verdad vacua si no existieran vinos de ese tipo.
SELECT cl.id_cliente,
       cl.apellido_razon_social,
       cl.nombre,
       cl.tipo_cliente
  FROM cliente cl
 WHERE EXISTS (
           SELECT 1
             FROM vino v0
            WHERE v0.tipo = 'espumante'
       )
   AND NOT EXISTS (
           SELECT 1
             FROM vino v
            WHERE v.tipo = 'espumante'
              AND NOT EXISTS (
                      SELECT 1
                        FROM comprobante c
                        JOIN renglon_comprobante rc
                          ON rc.nro_comprobante = c.nro_comprobante
                       WHERE c.id_cliente = cl.id_cliente
                         AND rc.cod_vino = v.cod_vino
                  )
       )
 ORDER BY cl.id_cliente ASC;