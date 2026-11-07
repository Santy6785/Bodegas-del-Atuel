-- =====================================================================
-- 003_funciones.sql
-- Bodegas del Atuel - Funciones de calculo reutilizables
--
-- Contiene 4 funciones:
--   fn_descuento_cliente(tipo_cliente)   IMMUTABLE
--   fn_total_comprobante(nro)            STABLE
--   fn_stock_sala(sala, vino)            STABLE
--   fn_antiguedad_anios(fecha)           STABLE
--
-- Criterio de volatilidad (lo que PostgreSQL puede asumir del resultado):
--   * IMMUTABLE: depende solo de sus argumentos. Mismo argumento, mismo
--     resultado, siempre.
--   * STABLE:    depende de las tablas o de la fecha actual. Es constante
--     dentro de una misma sentencia, pero puede cambiar entre sentencias.
--
-- IMPORTANTE: ninguna de estas funciones se usa dentro de un CHECK.
-- Las que leen tablas o la fecha actual (las tres STABLE) cambian con el
-- tiempo y romperian la restauracion de un backup. Las reglas que
-- dependen de ellas van en triggers (005) o procedimientos (004).
--
-- Se ejecuta despues de 001 y 002. Es idempotente (CREATE OR REPLACE).
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- fn_descuento_cliente
--
-- Proposito : porcentaje de descuento que corresponde a un tipo de
--             cliente (RN-06): socio 10, distribuidor 20, exportador 30.
-- Parametros: p_tipo  tipo_cliente  tipo de cliente.
-- Devuelve  : NUMERIC con el porcentaje (ej. 10.00). NULL si p_tipo es NULL.
-- Volatilidad: IMMUTABLE. Solo depende del argumento: no lee tablas ni la
--              fecha, los porcentajes son constantes de la regla.
-- Uso       : el trigger de renglon_comprobante copia este valor a
--             descuento_pct al insertar (snapshot historico).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_descuento_cliente(p_tipo tipo_cliente)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
    SELECT CASE p_tipo
        WHEN 'socio'        THEN 10.00
        WHEN 'distribuidor' THEN 20.00
        WHEN 'exportador'   THEN 30.00
    END;
$$;

COMMENT ON FUNCTION fn_descuento_cliente(tipo_cliente) IS
    'RN-06. Porcentaje de descuento por tipo de cliente (10/20/30). IMMUTABLE.';

-- ---------------------------------------------------------------------
-- fn_total_comprobante
--
-- Proposito : total a pagar de un comprobante: suma de sus renglones con
--             el descuento aplicado (RN-08). El total no se carga a mano.
-- Parametros: p_nro  INTEGER  numero del comprobante (nro_comprobante).
-- Devuelve  : NUMERIC(12,2). Es 0 si el comprobante no tiene renglones
--             o no existe.
-- Formula   : por renglon, ROUND(cantidad * precio_unitario *
--             (100 - descuento_pct) / 100, 2). El subtotal almacenado de
--             cada renglon debe calcularse con esta misma formula.
-- Volatilidad: STABLE. Lee renglon_comprobante.
-- Nota      : el subtotal bruto de la cabecera es
--             SUM(cantidad * precio_unitario) y el descuento es
--             bruto - total. Los calcula el trigger (005).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_total_comprobante(p_nro INTEGER)
RETURNS NUMERIC
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
               SUM(ROUND(r.cantidad * r.precio_unitario * (100 - r.descuento_pct) / 100, 2)),
               0
           )::NUMERIC(12,2)
      FROM renglon_comprobante r
     WHERE r.nro_comprobante = p_nro;
$$;

COMMENT ON FUNCTION fn_total_comprobante(INTEGER) IS
    'RN-08. Total de un comprobante: suma de renglones con descuento aplicado. STABLE.';

-- ---------------------------------------------------------------------
-- fn_stock_sala
--
-- Proposito : stock actual de un vino en una sala (RN-09). Si la sala
--             nunca recibio ese vino devuelve 0 en lugar de NULL.
-- Parametros: p_sala  INTEGER  id de la sala de venta.
--             p_vino  INTEGER  codigo del vino.
-- Devuelve  : INTEGER, nunca NULL.
-- Volatilidad: STABLE. Lee stock_sala.
-- Uso       : trigger BEFORE INSERT en renglon_comprobante (validacion
--             de stock) y consultas S6 y S9.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_stock_sala(p_sala INTEGER, p_vino INTEGER)
RETURNS INTEGER
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        (SELECT s.cantidad
           FROM stock_sala s
          WHERE s.id_sala = p_sala
            AND s.cod_vino = p_vino),
        0);
$$;

COMMENT ON FUNCTION fn_stock_sala(INTEGER, INTEGER) IS
    'RN-09. Stock de un vino en una sala; 0 si no hay fila. STABLE.';

-- ---------------------------------------------------------------------
-- fn_antiguedad_anios
--
-- Proposito : anios completos transcurridos desde una fecha hasta hoy.
--             Sirve para la antiguedad de un empleado (consignas U2 y D3).
-- Parametros: p_fecha  DATE  fecha de ingreso.
-- Devuelve  : INTEGER, anios cumplidos (>= 0). NULL si p_fecha es NULL.
--             Si la fecha es futura devuelve 0.
-- Volatilidad: STABLE, NO IMMUTABLE: usa CURRENT_DATE, y el resultado
--              cambia con el tiempo. Marcarla IMMUTABLE seria un error.
--              Por la misma razon no puede usarse en un CHECK ni en un
--              indice de expresion.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_antiguedad_anios(p_fecha DATE)
RETURNS INTEGER
LANGUAGE sql
STABLE
STRICT
AS $$
    SELECT GREATEST(
        EXTRACT(YEAR FROM age(CURRENT_DATE::timestamp, p_fecha::timestamp))::INTEGER,
        0);
$$;

COMMENT ON FUNCTION fn_antiguedad_anios(DATE) IS
    'Anios completos desde una fecha hasta hoy. STABLE (usa CURRENT_DATE).';

COMMIT;

-- =====================================================================
-- Verificacion rapida (ejecutar a mano despues de aplicar la migracion)
--
-- Volatilidad de cada funcion (i = IMMUTABLE, s = STABLE, v = VOLATILE):
--   SELECT proname, provolatile
--     FROM pg_proc
--    WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'fn\_%'
--    ORDER BY proname;
--   -- Esperado: fn_antiguedad_anios s, fn_descuento_cliente i,
--   --           fn_stock_sala s, fn_total_comprobante s
--
-- Resultados esperados:
--   SELECT fn_descuento_cliente('socio'),
--          fn_descuento_cliente('distribuidor'),
--          fn_descuento_cliente('exportador');           -- 10.00 | 20.00 | 30.00
--   SELECT fn_antiguedad_anios((CURRENT_DATE - INTERVAL '6 years')::date);   -- 6
--   SELECT fn_antiguedad_anios((CURRENT_DATE - INTERVAL '5 years 11 months')::date);  -- 5
--   SELECT fn_antiguedad_anios((CURRENT_DATE + INTERVAL '1 year')::date);    -- 0
--   SELECT fn_stock_sala(-1, -1);                        -- 0 (sin fila)
--   SELECT fn_total_comprobante(-1);                     -- 0.00 (sin renglones)
-- =====================================================================