-- ============================================================================
-- MODIFICACIONES INSERT (I1 a I6) EN TRANSACCIÓN — Bodegas del Atuel
-- Patrón: BEGIN -> control previo -> INSERT -> control posterior -> ROLLBACK
-- Valores concretos tomados del dataset de seed.py (bodegas_atuel_bench).
-- Para cambiar un valor, buscar el comentario "PARÁMETRO".
-- No se calculan totales, descuentos ni stock a mano.
-- Fechas relativas con CURRENT_DATE.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- I1. Cobertura de General Alvear (5505) para el transportista que menos
--     ingresos trasladados tuvo en el último trimestre.
-- Estrategia: CTE que cuenta sólo ingresos trasladados (estado 'procesado' o
--   'terminado') del último trimestre por transportista, con LEFT JOIN desde
--   transportista para incluir a los que no tuvieron ninguno. Desempate por
--   cod_transportista. ON CONFLICT para respetar la PK compuesta.
-- ----------------------------------------------------------------------------
BEGIN;
-- control previo: cobertura existente en General Alvear
SELECT cod_transportista, codigo_postal
  FROM transportista_localidad
 WHERE codigo_postal = '5505'
 ORDER BY cod_transportista;
-- control previo: conteo de ingresos trasladados por transportista en el último trimestre
SELECT t.cod_transportista, COUNT(i.cod_ingreso) AS ingresos_trimestre
  FROM transportista t
  LEFT JOIN ingreso i
    ON i.cod_transportista = t.cod_transportista
   AND i.fecha >= CURRENT_DATE - INTERVAL '3 months'
   AND i.estado IN ('terminado', 'procesado')
 GROUP BY t.cod_transportista
 ORDER BY ingresos_trimestre ASC, t.cod_transportista ASC;

WITH menor_actividad AS (
    SELECT t.cod_transportista
      FROM transportista t
      LEFT JOIN ingreso i
        ON i.cod_transportista = t.cod_transportista
       AND i.fecha >= CURRENT_DATE - INTERVAL '3 months'
       AND i.estado IN ('terminado', 'procesado')
     GROUP BY t.cod_transportista
     ORDER BY COUNT(i.cod_ingreso) ASC, t.cod_transportista ASC
     LIMIT 1
)
INSERT INTO transportista_localidad (cod_transportista, codigo_postal)
SELECT cod_transportista, '5505'
  FROM menor_actividad
ON CONFLICT (cod_transportista, codigo_postal) DO NOTHING;

-- control posterior: cobertura insertada
SELECT tl.cod_transportista, t.razon_social, tl.codigo_postal
  FROM transportista_localidad tl
  JOIN transportista t ON t.cod_transportista = tl.cod_transportista
 WHERE tl.codigo_postal = '5505'
 ORDER BY tl.cod_transportista;
ROLLBACK;


-- ----------------------------------------------------------------------------
-- I2. Maridaje «cordero al disco» asociado a los vinos tintos con graduación >= 14.
-- Estrategia: la rama sólo actúa si EXISTEN vinos que cumplan la condición
--   (si no existen, no se crea el maridaje). Se usa un bloque DO para decidir.
--   temperatura_servicio = 18 °C (valor orientativo; CHECK admite 0-30).
-- ----------------------------------------------------------------------------
BEGIN;
-- control previo: vinos que cumplen la condición
SELECT cod_vino, nombre, tipo, graduacion
  FROM vino
 WHERE tipo = 'tinto' AND graduacion >= 14
 ORDER BY cod_vino;
-- control previo: maridaje existente
SELECT id_maridaje, nombre, temperatura_servicio
  FROM maridaje
 WHERE nombre = 'cordero al disco';

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM vino WHERE tipo = 'tinto' AND graduacion >= 14) THEN
        -- Crea el maridaje si no existe. PARÁMETRO: temperatura_servicio (18).
        INSERT INTO maridaje (nombre, temperatura_servicio)
        VALUES ('cordero al disco', 18)
        ON CONFLICT (nombre) DO NOTHING;

        INSERT INTO vino_maridaje (cod_vino, id_maridaje)
        SELECT v.cod_vino, m.id_maridaje
          FROM vino v
          CROSS JOIN maridaje m
         WHERE v.tipo = 'tinto'
           AND v.graduacion >= 14
           AND m.nombre = 'cordero al disco'
        ON CONFLICT (cod_vino, id_maridaje) DO NOTHING;
    ELSE
        RAISE NOTICE 'No hay vinos tintos con graduación >= 14: no se crea el maridaje.';
    END IF;
END $$;

-- control posterior: maridaje y asociaciones
SELECT id_maridaje, nombre, temperatura_servicio
  FROM maridaje
 WHERE nombre = 'cordero al disco';
SELECT vm.cod_vino, v.tipo, v.graduacion, m.nombre AS maridaje
  FROM vino_maridaje vm
  JOIN maridaje m ON m.id_maridaje = vm.id_maridaje
  JOIN vino v     ON v.cod_vino    = vm.cod_vino
 WHERE m.nombre = 'cordero al disco'
 ORDER BY vm.cod_vino;
ROLLBACK;


-- ----------------------------------------------------------------------------
-- I3. Comprobante con tres renglones para un cliente dado, en la sala 1,
--     dentro de una transacción, usando sp_crear_comprobante.
-- Estrategia: el procedimiento inserta cabecera y renglones; los triggers
--   calculan precio, descuento, subtotal y total, y descuentan el stock de
--   sala. Si algún renglón no tiene stock, sp_crear_comprobante lanza P0001 y
--   todo se revierte. El número de comprobante se devuelve por INOUT y se
--   verifica con fn_total_comprobante.
-- PARÁMETROS: id_cliente (1), cod_vinos (1, 2, 3), cantidades (2, 1, 3).
-- Antes de ejecutar, verificar stock con el primer control previo.
-- ----------------------------------------------------------------------------
BEGIN;
-- control previo: stock de sala 1 de los tres vinos
SELECT cod_vino, fn_stock_sala(1, cod_vino) AS stock_sala_1
  FROM (VALUES (1), (2), (3)) AS v(cod_vino)
 ORDER BY cod_vino;
-- control previo: cantidad de comprobantes
SELECT COUNT(*) AS comprobantes_previos FROM comprobante;

DO $$
DECLARE
    v_nro INTEGER;
BEGIN
    CALL sp_crear_comprobante(
        1,                                   -- PARÁMETRO: id_cliente
        1,                                   -- id_sala (fija: sala 1)
        ARRAY[1, 2, 3]::INTEGER[],           -- PARÁMETRO: cod_vinos
        ARRAY[2, 1, 3]::INTEGER[],           -- PARÁMETRO: cantidades
        v_nro
    );
    RAISE NOTICE 'Comprobante creado: %', v_nro;
END $$;

-- control posterior: cabecera calculada por la base
SELECT c.nro_comprobante, c.fecha, c.id_cliente, c.id_sala,
       c.subtotal, c.descuento, c.total,
       fn_total_comprobante(c.nro_comprobante) AS total_funcion
  FROM comprobante c
 WHERE c.nro_comprobante = (SELECT MAX(nro_comprobante) FROM comprobante);
-- control posterior: renglones con precio y descuento snapshot
SELECT rc.cod_vino, rc.cantidad, rc.precio_unitario, rc.descuento_pct, rc.subtotal
  FROM renglon_comprobante rc
 WHERE rc.nro_comprobante = (SELECT MAX(nro_comprobante) FROM comprobante)
 ORDER BY rc.cod_vino;
-- control posterior: stock de sala descontado
SELECT cod_vino, fn_stock_sala(1, cod_vino) AS stock_sala_1
  FROM (VALUES (1), (2), (3)) AS v(cod_vino)
 ORDER BY cod_vino;
ROLLBACK;


-- ----------------------------------------------------------------------------
-- I4. Alta de bodega nueva.
-- Estrategia: CUIT ficticio que no existe en el seed (DOMAIN cuit_dom, 11 dígitos).
--   Control previo confirma que el CUIT está libre.
-- PARÁMETROS: cuit ('20999888777'), razon_social, domicilio.
-- ----------------------------------------------------------------------------
BEGIN;
-- control previo: cantidad de bodegas y existencia del CUIT
SELECT COUNT(*) AS bodegas_previas FROM bodega;
SELECT COUNT(*) AS cuit_ocupado FROM bodega WHERE cuit = '20999888777';

INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('20999888777', 'Bodega Prueba Atuel', 'Ruta Nacional 143, km 15');

-- control posterior: fila nueva
SELECT cuit, razon_social, domicilio FROM bodega WHERE cuit = '20999888777';
SELECT COUNT(*) AS bodegas_posteriores FROM bodega;
ROLLBACK;


-- ----------------------------------------------------------------------------
-- I5. Alta de sala de venta nueva.
-- Estrategia: id_sala es identity (no se envía). La localidad debe existir por
--   FK; el control previo lo verifica.
-- PARÁMETROS: calle, numero, dia_cierre (enum dia_semana), codigo_postal ('5505').
-- ----------------------------------------------------------------------------
BEGIN;
-- control previo: cantidad de salas y localidad destino
SELECT COUNT(*) AS salas_previas FROM sala_venta;
SELECT codigo_postal, nombre FROM localidad WHERE codigo_postal = '5505';

INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal)
VALUES ('Calle Falsa', '123', 'lunes', '5505')   -- PARÁMETRO: calle, numero, dia_cierre, codigo_postal
RETURNING id_sala, calle, numero, dia_cierre, codigo_postal;

-- control posterior: cantidad de salas
SELECT COUNT(*) AS salas_posteriores FROM sala_venta;
ROLLBACK;


-- ----------------------------------------------------------------------------
-- I6. Ingreso en confección de 120 botellas de «Malbec Reserva» 750 ml.
--     NO se procesa: no se llama a terminar_ingreso ni a sp_procesar_ingreso.
-- Estrategia: estado toma el DEFAULT 'en_confeccion'. Si hay más de una añada,
--   se usa la más reciente. Si el vino no existe, el INSERT no hace nada y el
--   control previo lo deja visible.
-- PARÁMETROS: cod_transportista (1), cuit_bodega ('20123456781').
-- ----------------------------------------------------------------------------
BEGIN;
-- control previo: vino elegido y su stock en depósito
SELECT cod_vino, nombre, volumen_ml, anada
  FROM vino
 WHERE nombre = 'Malbec Reserva' AND volumen_ml = 750
 ORDER BY anada DESC
 LIMIT 1;
SELECT sd.cod_vino, sd.cantidad AS stock_deposito_previo
  FROM stock_deposito sd
 WHERE sd.cod_vino = (
     SELECT cod_vino FROM vino
      WHERE nombre = 'Malbec Reserva' AND volumen_ml = 750
      ORDER BY anada DESC LIMIT 1
 );
SELECT COUNT(*) AS ingresos_previos FROM ingreso;

-- Inserción: ingreso y renglón en la misma sentencia.
WITH vino_malbec AS (
    SELECT cod_vino FROM vino
     WHERE nombre = 'Malbec Reserva' AND volumen_ml = 750
     ORDER BY anada DESC
     LIMIT 1
),
nuevo_ingreso AS (
    INSERT INTO ingreso (fecha, cod_transportista, cuit_bodega)
    SELECT CURRENT_DATE, 1, '20123456781'        -- PARÁMETRO: cod_transportista, cuit_bodega
      FROM vino_malbec
    RETURNING cod_ingreso
)
INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
SELECT n.cod_ingreso, v.cod_vino, 120           -- PARÁMETRO: cantidad (120)
  FROM nuevo_ingreso n
  CROSS JOIN vino_malbec v;

-- control posterior: ingreso creado en confección, renglón y stock sin cambios
SELECT i.cod_ingreso, i.fecha, i.estado, i.cod_transportista, i.cuit_bodega
  FROM ingreso i
 WHERE i.cod_ingreso = (SELECT MAX(cod_ingreso) FROM ingreso);
SELECT ri.cod_ingreso, ri.cod_vino, ri.cantidad
  FROM renglon_ingreso ri
 WHERE ri.cod_ingreso = (SELECT MAX(cod_ingreso) FROM ingreso);
SELECT sd.cod_vino, sd.cantidad AS stock_deposito_posterior
  FROM stock_deposito sd
 WHERE sd.cod_vino = (
     SELECT cod_vino FROM vino
      WHERE nombre = 'Malbec Reserva' AND volumen_ml = 750
      ORDER BY anada DESC LIMIT 1
 );
ROLLBACK;