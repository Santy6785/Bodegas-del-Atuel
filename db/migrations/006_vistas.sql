-- =====================================================================
-- 006_vistas.sql
-- Bodegas del Atuel - Vistas del Sistema (Etapa 2)
--
-- Vistas exigidas por la cátedra (mínimo 3, incluyendo una materializada):
--   1. vw_stock_total_vino
--      Consolida el stock de cada vino sumando el depósito central y
--      todas las salas de venta. Útil para catálogo general y consigna S9.
--
--   2. vw_ventas_mensuales_sala (MATERIALIZADA)
--      Agregación de facturación, comprobantes y botellas por sala y mes.
--      Se materializa porque en producción involucra cientos de miles
--      de renglones (comprobantes y renglones). Dispone de un índice único
--      para permitir REFRESH MATERIALIZED VIEW CONCURRENTLY.
--
--   3. vw_documentos_pendientes
--      Unifica ingresos y transferencias que aún no fueron procesados
--      (estados 'en_confeccion' y 'terminado'). Facilita el monitoreo logístico.
--
-- Se ejecuta después de 001 a 005. Es idempotente (DROP CASCADE + CREATE).
-- =====================================================================

BEGIN;

-- =====================================================================
-- 1. vw_stock_total_vino
-- =====================================================================
-- Propósito: Calcular el stock disponible total por vino en toda la empresa.
-- Suma el stock en el depósito central y el stock distribuido en todas las salas.
-- Si un vino no tiene stock en alguna ubicación, se muestra 0 (COALESCE).
-- =====================================================================

DROP VIEW IF EXISTS vw_stock_total_vino CASCADE;

CREATE OR REPLACE VIEW vw_stock_total_vino AS
SELECT
    v.cod_vino,
    v.nombre                     AS vino_nombre,
    v.tipo                       AS vino_tipo,
    v.anada,
    v.volumen_ml,
    v.precio,
    b.cuit                       AS cuit_bodega,
    b.razon_social               AS bodega_razon_social,
    COALESCE(sd.cantidad, 0)     AS stock_deposito,
    COALESCE(ss.stock_salas, 0)::BIGINT AS stock_salas,
    (COALESCE(sd.cantidad, 0) + COALESCE(ss.stock_salas, 0))::BIGINT AS stock_total
FROM vino v
JOIN bodega b ON b.cuit = v.cuit_bodega
LEFT JOIN stock_deposito sd ON sd.cod_vino = v.cod_vino
LEFT JOIN (
    SELECT
        cod_vino,
        SUM(cantidad) AS stock_salas
    FROM stock_sala
    GROUP BY cod_vino
) ss ON ss.cod_vino = v.cod_vino;

COMMENT ON VIEW vw_stock_total_vino IS
    'Stock consolidado por vino: suma del depósito central y todas las salas de venta.';


-- =====================================================================
-- 2. vw_ventas_mensuales_sala (VISTA MATERIALIZADA)
-- =====================================================================
-- Propósito: Reporte gerencial de ventas agregadas mensualmente por sala.
--
-- Justificación de materialización:
--   La tabla de comprobantes superará las 150.000 filas y renglones más de
--   500.000 (Etapa 3). Realizar este cálculo analítico en tiempo real en cada
--   consulta del tablero generaría un costo computacional innecesario.
--   La vista materializada almacena el resultado físico y se refresca
--   periódicamente con REFRESH MATERIALIZED VIEW CONCURRENTLY.
-- =====================================================================

DROP MATERIALIZED VIEW IF EXISTS vw_ventas_mensuales_sala CASCADE;

CREATE MATERIALIZED VIEW vw_ventas_mensuales_sala AS
SELECT
    s.id_sala,
    s.calle || ' ' || s.numero                      AS sala_direccion,
    l.codigo_postal,
    l.nombre                                        AS localidad,
    EXTRACT(YEAR FROM c.fecha)::INTEGER             AS anio,
    EXTRACT(MONTH FROM c.fecha)::INTEGER            AS mes,
    TO_CHAR(c.fecha, 'YYYY-MM')                     AS periodo,
    COUNT(c.nro_comprobante)::INTEGER               AS cantidad_comprobantes,
    COALESCE(SUM(c.subtotal), 0)::NUMERIC(14,2)     AS total_subtotal,
    COALESCE(SUM(c.descuento), 0)::NUMERIC(14,2)    AS total_descuento,
    COALESCE(SUM(c.total), 0)::NUMERIC(14,2)        AS total_facturado,
    COALESCE(SUM(r.total_botellas), 0)::BIGINT      AS total_botellas_vendidas
FROM sala_venta s
JOIN localidad l ON l.codigo_postal = s.codigo_postal
JOIN comprobante c ON c.id_sala = s.id_sala
LEFT JOIN (
    SELECT
        nro_comprobante,
        SUM(cantidad) AS total_botellas
    FROM renglon_comprobante
    GROUP BY nro_comprobante
) r ON r.nro_comprobante = c.nro_comprobante
GROUP BY
    s.id_sala,
    s.calle,
    s.numero,
    l.codigo_postal,
    l.nombre,
    EXTRACT(YEAR FROM c.fecha),
    EXTRACT(MONTH FROM c.fecha),
    TO_CHAR(c.fecha, 'YYYY-MM')
WITH DATA;

-- Índice único para habilitar REFRESH MATERIALIZED VIEW CONCURRENTLY
CREATE UNIQUE INDEX idx_vw_ventas_mensuales_sala_pk
    ON vw_ventas_mensuales_sala (id_sala, anio, mes);

CREATE INDEX idx_vw_ventas_mensuales_periodo
    ON vw_ventas_mensuales_sala (periodo);

COMMENT ON MATERIALIZED VIEW vw_ventas_mensuales_sala IS
    'Ventas agregadas por sala y período mensual. Materializada para optimizar consultas del tablero.';


-- =====================================================================
-- 3. vw_documentos_pendientes
-- =====================================================================
-- Propósito: Vista operativa unificada para logística y distribución.
-- Lista todos los ingresos y transferencias que se encuentran pendientes
-- de procesamiento (estados 'en_confeccion' o 'terminado').
-- Permite visualizar origen, destino, transportista y volumen en botellas.
-- =====================================================================

DROP VIEW IF EXISTS vw_documentos_pendientes CASCADE;

CREATE OR REPLACE VIEW vw_documentos_pendientes AS
-- Ingresos pendientes hacia depósito central
SELECT
    'ingreso'::VARCHAR(20)          AS tipo_documento,
    i.cod_ingreso                   AS nro_documento,
    i.fecha                         AS fecha_emision,
    i.estado,
    b.razon_social                  AS origen,
    'Depósito Central'::VARCHAR(150) AS destino,
    t.razon_social                  AS transportista,
    COALESCE(ri.total_botellas, 0)::BIGINT   AS total_botellas,
    COALESCE(ri.total_variedades, 0)::BIGINT AS total_variedades,
    (CURRENT_DATE - i.fecha)::INTEGER        AS dias_pendiente
FROM ingreso i
JOIN bodega b ON b.cuit = i.cuit_bodega
JOIN transportista t ON t.cod_transportista = i.cod_transportista
LEFT JOIN (
    SELECT
        cod_ingreso,
        SUM(cantidad)            AS total_botellas,
        COUNT(DISTINCT cod_vino) AS total_variedades
    FROM renglon_ingreso
    GROUP BY cod_ingreso
) ri ON ri.cod_ingreso = i.cod_ingreso
WHERE i.estado <> 'procesado'

UNION ALL

-- Transferencias pendientes hacia salas de venta
SELECT
    'transferencia'::VARCHAR(20)    AS tipo_documento,
    tr.nro_transferencia            AS nro_documento,
    tr.fecha_confeccion             AS fecha_emision,
    tr.estado,
    'Depósito Central'::VARCHAR(150) AS origen,
    (s.calle || ' ' || s.numero || ' (' || loc.nombre || ')')::VARCHAR(150) AS destino,
    NULL::VARCHAR(150)              AS transportista,
    COALESCE(rt.total_botellas, 0)::BIGINT   AS total_botellas,
    COALESCE(rt.total_variedades, 0)::BIGINT AS total_variedades,
    (CURRENT_DATE - tr.fecha_confeccion)::INTEGER AS dias_pendiente
FROM transferencia tr
JOIN sala_venta s ON s.id_sala = tr.id_sala
JOIN localidad loc ON loc.codigo_postal = s.codigo_postal
LEFT JOIN (
    SELECT
        nro_transferencia,
        SUM(cantidad)            AS total_botellas,
        COUNT(DISTINCT cod_vino) AS total_variedades
    FROM renglon_transferencia
    GROUP BY nro_transferencia
) rt ON rt.nro_transferencia = tr.nro_transferencia
WHERE tr.estado <> 'procesado';

COMMENT ON VIEW vw_documentos_pendientes IS
    'Documentos de movimiento de stock (ingresos y transferencias) no procesados.';

COMMIT;
