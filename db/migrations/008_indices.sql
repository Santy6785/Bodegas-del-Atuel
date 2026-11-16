-- ============================================================================
-- Migración 008: Índices secundarios justificados (Issue #97)
-- ============================================================================
-- Criterios aplicados (ver docs/decisiones.md §2.12 y docs/planes_explain.md):
--   1. Índice compuesto (igualdad + rango): comprobante(id_sala, fecha).
--   2. Índice parcial con WHERE: transferencia(id_sala, fecha_confeccion) WHERE estado <> 'procesado'.
--   3. Índice sobre FK + INCLUDE: renglon_comprobante(cod_vino) INCLUDE (cantidad, subtotal).
--   4. Índice de expresión: cliente(LOWER(apellido_razon_social)).
--   5. Índice covering adicional justificado: comprobante(fecha) INCLUDE (id_sala, total).
-- ============================================================================

-- 1. Índice compuesto (igualdad primero, rango después):
-- Acelera consultas filtradas por sala de venta y ventana temporal (S3, S8, S11),
-- evitando escaneos secuenciales completos sobre el historial de comprobantes.
CREATE INDEX idx_comprobante_sala_fecha
    ON comprobante (id_sala, fecha);

-- 2. Índice parcial con WHERE:
-- Indexa únicamente las transferencias activas (en_confeccion / terminado) usadas por
-- vw_documentos_pendientes y listados operativos (S4, S5), manteniendo el índice compacto
-- y sin costo de mantenimiento sobre el histórico ya procesado.
CREATE INDEX idx_transferencia_pendiente_sala
    ON transferencia (id_sala, fecha_confeccion)
    WHERE estado <> 'procesado';

-- 3. Índice sobre clave foránea (FK) con INCLUDE:
-- PostgreSQL no indexa automáticamente las FK. Indexar renglon_comprobante(cod_vino) con
-- INCLUDE (cantidad, subtotal) habilita Index Only Scan en el ranking de vinos (S1, S2, S9)
-- y acelera la verificación referencial ON DELETE RESTRICT de vino (RN-14).
CREATE INDEX idx_renglon_comprobante_cod_vino
    ON renglon_comprobante (cod_vino)
    INCLUDE (cantidad, subtotal);

-- 4. Índice de expresión:
-- Permite resolver búsquedas case-insensitive por apellido o razón social de clientes
-- (LOWER(apellido_razon_social)) sin forzar un Seq Scan sobre la tabla cliente.
CREATE INDEX idx_cliente_apellido_lower
    ON cliente (LOWER(apellido_razon_social));

-- 5. Índice adicional justificado (covering para agregación temporal global):
-- Optimiza reportes por ventana de fechas sobre todas las salas en simultáneo
-- (como S8: ventas del último trimestre), resolviendo el filtro por fecha y la suma
-- de total por sala mediante Index Only Scan sin acceder al heap de comprobante.
CREATE INDEX idx_comprobante_fecha_inc
    ON comprobante (fecha)
    INCLUDE (id_sala, total);
