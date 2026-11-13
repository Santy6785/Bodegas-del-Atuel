-- =====================================================================
-- generar_datos_prueba.sql
-- Script de generación de datos de prueba para TPI #56
-- Objetivo: 20.000 clientes, 150.000 comprobantes, 500.000 renglones, ~1.000 vinos
-- Usar sesión: session_replication_role = replica para evitar triggers
-- =====================================================================

-- Nota: Este script debe ejecutarse DESPUÉ de aplicar las migraciones 001-007.
-- No ejecutar sobre la base principal (bodegas_atuel) en producción.
-- Usar una base de datos separada (ej. bodegas_perf).

-- --------------------------------------------------------------------
-- PASO 1: Crear la base de datos separada (fuera del alcance de este script)
-- --------------------------------------------------------------------
-- CREATE DATABASE bodegas_perf;
-- \c bodegas_perf
-- Luego ejecutar este script.

-- --------------------------------------------------------------------
-- PASO 2: Aplicar migraciones (001 a 007)
-- --------------------------------------------------------------------
-- \i ../db/migrations/001_esquema.sql
-- \i ../db/migrations/002_constraints.sql
-- \i ../db/migrations/003_funciones.sql
-- \i ../db/migrations/004_procedimientos.sql
-- \i ../db/migrations/005_triggers.sql
-- \i ../db/migrations/006_vistas.sql
-- \i ../db/migrations/007_roles.sql

-- --------------------------------------------------------------------
-- PASO 3: Poblar tabla 'cepa' con datos fijos (semilla fija = 1000 cepas)
-- --------------------------------------------------------------------
BEGIN;

-- Insertar 1000 cepas (Mix de tintas y blancas)
INSERT INTO cepa (nombre, tipo)
SELECT
    'Cepa ' || i,
    CASE WHEN i % 2 = 0 THEN 'tinta' ELSE 'blanca' END
FROM generate_series(1, 1000) AS s(i);

-- Insertar algunos vinos de prueba (~1000 vinos con datos realistas)
INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
SELECT
    'Vino ' || i,
    CASE WHEN i % 2 = 0 THEN 'tinto' ELSE 'blanco' END,
    2018 + (i % 6),  -- añadas: 2018, 2019, 2020, 2021, 2022, 2023
    750,
    ROUND(10.0 + (i % 15) + (random() * 10), 2)::NUMERIC(5,2),
    ROUND(300000000 + (i % 999999999)::INTEGER, 0)::CHAR(11)  -- cuit sintético
FROM generate_series(1, 1000) AS s(i);

-- Insertar composición (cepas) para cada vino - algunos tendrán 2 cepas
INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
SELECT
    v.cod_vino,
    c.id_cepa,
    CASE WHEN random() > 0.3 THEN 80 ELSE 20 END AS porcentaje  -- 70% tendrán una cepa, 30% dos
FROM generate_series(1, 1000) AS v
CROSS JOIN cepa c
WHERE random() > 0.7  -- Control de filas para no exceder
ON CONFLICT DO NOTHING;

-- Insertar maridajes para algunos vinos
INSERT INTO vino_maridaje (cod_vino, cod_maridaje)
SELECT
    v.cod_vino,
    (random() * 10 + 1)::INTEGER  -- IDs de maridaje existentes
FROM generate_series(1, 1000) AS v
LIMIT 800;

COMMIT;

-- --------------------------------------------------------------------
-- PASO 4: Poblar 20.000 clientes (con subtipos distribuidos)
-- Usar session_replication_role = replica para evitar triggers de coherencia
-- --------------------------------------------------------------------
BEGIN;

-- Clientes socio (70%)
INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento, nro_documento,
                     direccion, codigo_postal, fecha_alta, tipo_cliente)
SELECT
    'Apellido ' || i,
    'Nombre ' || i,
    CASE WHEN random() > 0.3 THEN 'DNI' ELSE 'CUIT' END,
    ROUND(10000000 + (i % 89999999)::INTEGER, 0)::CHAR(11),
    'Dirección ' || i,
    LPAD((random() * 9999 + 1000)::INTEGER, 4, '0'),  -- códigos postales aleatorios
    DATE '2020-01-01' + (random() * 730)::INTEGER,  -- últimos 2 años
    'socio'
FROM generate_series(1, 14000) AS s(i);

-- Clientes distribuidor (20%)
INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento, nro_documento,
                     direccion, codigo_postal, fecha_alta, tipo_cliente)
SELECT
    'Distribuidor ' || i,
    NULL,
    'CUIT',
    ROUND(30000000 + (i % 89999999)::INTEGER, 0)::CHAR(11),
    'Dir Dist ' || i,
    LPAD((random() * 9999 + 1000)::INTEGER, 4, '0'),
    DATE '2020-01-01' + (random() * 730)::INTEGER,
    'distribuidor'
FROM generate_series(1, 4000) AS s(i);

-- Clientes exportador (10%)
INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento, nro_documento,
                    direccion, codigo_postal, fecha_alta, tipo_cliente)
SELECT
    'Exportadora ' || i,
    NULL,
    'CUIT',
    ROUND(31000000 + (i % 89999999)::INTEGER, 0)::CHAR(11),
    'Dir Exp ' || i,
    LPAD((random() * 9999 + 1000)::INTEGER, 4, '0'),
    DATE '2020-01-01' + (random() * 730)::INTEGER,
    'exportador'
FROM generate_series(1, 2000) AS s(i);

-- Insertar subtipos para distribuidores
INSERT INTO cliente_distribuidor (id_cliente, zona_cobertura, nro_habilitacion)
SELECT id_cliente,
       'Zona ' || (i % 10),
       'HAB-' || LPAD((random() * 999 + 1)::INTEGER, 3, '0')
FROM generate_series(1, 4000) AS s(i)
JOIN cliente c ON c.id_cliente = s.i
WHERE c.tipo_cliente = 'distribuidor';

-- Insertar subtipos para exportadores
INSERT INTO cliente_exportador (id_cliente, pais_destino, porcentaje_descuento)
SELECT id_cliente,
       'País ' || (i % 20),
       30.00  -- DEFAULT 30 por defecto
FROM generate_series(1, 2000) AS s(i)
JOIN cliente c ON c.id_cliente = s.i
WHERE c.tipo_cliente = 'exportador';

-- Insertar permisos de exportación
INSERT INTO permiso_exportacion (id_cliente, codigo, fecha_emision, fecha_vencimiento)
SELECT id_cliente,
       'PE-' || LPAD((random() * 999 + 1)::INTEGER, 3, '0'),
       CURRENT_DATE - (random() * 365)::INTEGER,
       CURRENT_DATE + (random() * 365)::INTEGER
FROM generate_series(1, 2000) AS s(i)
JOIN cliente c ON c.id_cliente = s.i
WHERE c.tipo_cliente = 'exportador';

COMMIT;

-- --------------------------------------------------------------------
-- PASO 5: Poblar 150.000 comprobantes con renglones
-- Usar session_replication_role = replica para evitar triggers de stock/venta
-- --------------------------------------------------------------------
BEGIN;

-- Habilitar modo réplica para evitar triggers que fallen con datos de prueba
SET session_replication_role = replica;

-- Insertar comprobantes (150,000)
-- Usamos un contador global y lo distribuimos por cliente y sala
INSERT INTO comprobante (fecha, id_cliente, id_sala, subtotal, descuento, total)
SELECT
    DATE '2024-01-01' + (random() * 365)::INTEGER,  -- 2024
    (random() * 19999 + 1)::INTEGER,  -- id_cliente 1-20000 (aprox, algunos repetidos)
    (random() * 9 + 1)::INTEGER,  -- id_sala 1-10
    0::NUMERIC,  -- se calcularán triggers
    0::NUMERIC,
    0::NUMERIC
FROM generate_series(1, 150000) AS s(i);

-- Ahora asignar renglones a cada comprobante
-- Cada comprobante tendrá entre 1 y 5 renglones
-- Usamos un enfoque más controlado

-- Primero, conseguir lista de todos los vinos y sus cantidades disponibles
-- Insertar renglones_comprobante
WITH comps AS (
    SELECT nro_comprobante FROM comprobante ORDER BY nro_comprobante LIMIT 150000
),
vino_counts AS (
    SELECT cod_vino, COUNT(*) AS total_renglones
    FROM vino_cepa
    GROUP BY cod_vino
),
sala_distribucion AS (
    SELECT id_sala FROM sala_venta ORDER BY id_sala LIMIT 10
),
renglones AS (
    SELECT
        c.nro_comprobante,
        v.cod_vino,
        -- Cantidad entre 1 y 12
        (random() * 12 + 1)::INTEGER AS cantidad,
        -- Precio unitario basado en el vino
        ROUND(1000 + (random() * 20000)::INTEGER, 0)::NUMERIC(12,2) AS precio_unitario,
        -- Descuento por cliente (socio 10%, distribuidor 20%, exportador 30%)
        CASE WHEN c.tipo_cliente = 'socio' THEN ROUND(1000 + (random() * 2000)::INTEGER, 0)::NUMERIC(5,2)
             WHEN c.tipo_cliente = 'distribuidor' THEN ROUND(2000 + (random() * 3000)::INTEGER, 0)::NUMERIC(5,2)
             WHEN c.tipo_cliente = 'exportador' THEN ROUND(3000 + (random() * 2000)::INTEGER, 0)::NUMERIC(5,2)
             ELSE 0 END AS descuento_pct
    FROM comps c
    CROSS JOIN (SELECT cod_vino FROM vino LIMIT 1000) v
    JOIN cliente cl ON cl.tipo_cliente =
        CASE WHEN random() > 0.7 THEN 'socio'
             WHEN random() > 0.35 THEN 'distribuidor'
             ELSE 'exportador' END
    JOIN sala_distribucion s ON TRUE
    ORDER BY c.nro_comprobante, random()
    LIMIT 500000  -- Objetivo: 500,000 renglones
)
INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento_pct, subtotal)
SELECT nro_comprobante, cod_vino, cantidad, precio_unitario, descuento_pct,
       (cantidad * precio_unitario) * (1 - descuento_pct / 100)::NUMERIC(12,2) AS subtotal
FROM renglones;

-- Recalcular totales en comprobante (subtotal, descuento, total) - los triggers deberían hacerlo,
-- pero como estamos en modo réplica, lo hacemos explícitamente
UPDATE comprobante c
SET subtotal = rc.subtotal_total,
    descuento = rc.descuento_total,
    total = rc.total_total
FROM (
    SELECT
        nro_comprobante,
        SUM(subtotal) AS subtotal_total,
        SUM(subtotal * descuento_pct / 100) AS descuento_total,
        SUM(subtotal * (1 - descuento_pct / 100)) AS total_total
    FROM renglon_comprobante
    GROUP BY nro_comprobante
) rc
WHERE c.nro_comprobante = rc.nro_comprobante;

SET session_replication_role = DEFAULT;

COMMIT;

-- --------------------------------------------------------------------
-- PASO 6: Poblar stock_sala y stock_deposito
-- --------------------------------------------------------------------
BEGIN;

-- Stock en depósito (cantidad aleatoria por vino)
INSERT INTO stock_deposito (cod_vino, cantidad)
SELECT cod_vino, (random() * 500)::INTEGER
FROM generate_series(1, 1000) AS v;

-- Stock en salas (distribución aleatoria)
INSERT INTO stock_sala (cod_vino, id_sala, cantidad)
SELECT v.cod_vino, s.id_sala, (random() * 100)::INTEGER
FROM generate_series(1, 1000) AS v
CROSS JOIN (SELECT id_sala FROM sala_venta LIMIT 10) s;

-- Actualizar vistas materializadas si existen
-- REFRESH MATERIALIZED VIEW CONCURRENTLY vw_ventas_mensuales_sala;

COMMIT;

-- --------------------------------------------------------------------
-- PASO 7: Analizar tablas para que el planificador use estadísticas
-- --------------------------------------------------------------------
ANALYZE cepa;
ANALYZE vino;
ANALYZE vino_cepa;
ANALYZE cliente;
ANALYZE comprobante;
ANALYZE renglon_comprobante;
ANALYZE stock_sala;
ANALYZE stock_deposito;
ANALYZE bodega;
ANALYZE sala_venta;
ANALYZE localidades;
ANALYZE departamento;
ANALYZE finca;
ANALYZE parcela;
ANALYZE lote_uva;
ANALYZE permiso_exportacion;
ANALYZE maridaje;

-- --------------------------------------------------------------------
-- PASO 8: Verificar conteos objetivo
-- --------------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM vino) AS total_vinos,
    (SELECT COUNT(*) FROM cliente) AS total_clientes,
    (SELECT COUNT(*) FROM comprobante) AS total_comprobantes,
    (SELECT COUNT(*) FROM renglon_comprobante) AS total_renglones,
    (SELECT COUNT(*) FROM cepa) AS total_cepa;

-- --------------------------------------------------------------------
-- PASO 9: Instrucciones para borrar la base de prueba
-- --------------------------------------------------------------------
-- DROP DATABASE bodegas_perf;