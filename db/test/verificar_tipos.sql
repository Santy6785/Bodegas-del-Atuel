-- =====================================================================
-- verificar_tipos.sql
-- Bodegas del Atuel - Verificacion del ENUM estado_documento y del
-- DOMAIN cuit_dom (creados en 001_esquema.sql).
--
-- Comprueba tres cosas:
--   1. Que los tipos existen con la definicion esperada.
--   2. Que se usan en TODAS las columnas donde corresponde (y solo ahi).
--   3. Que rechazan valores invalidos.
--
-- No deja datos: las pruebas de INSERT fallan a proposito y, si alguna
-- no fallara, el script se detiene con un error.
--
-- Uso (desde la raiz del proyecto, con la base ya migrada):
--   Git Bash / Linux / Mac:
--     docker compose exec -T db psql -U <POSTGRES_USER> -d <POSTGRES_DB> < db/test/verificar_tipos.sql
--   PowerShell:
--     Get-Content db/test/verificar_tipos.sql | docker compose exec -T db psql -U <POSTGRES_USER> -d <POSTGRES_DB>
-- =====================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------
-- 1. Informacion (para capturas del informe)
-- ---------------------------------------------------------------------

\echo '--- Valores del ENUM estado_documento (en orden) ---'
SELECT enumsortorder AS orden, enumlabel AS valor
  FROM pg_enum
 WHERE enumtypid = 'estado_documento'::regtype
 ORDER BY enumsortorder;

\echo '--- Restriccion del DOMAIN cuit_dom ---'
SELECT conname, pg_get_constraintdef(oid) AS definicion
  FROM pg_constraint
 WHERE contypid = 'cuit_dom'::regtype;

\echo '--- Columnas de tablas que usan cuit_dom ---'
SELECT c.relname AS tabla, a.attname AS columna
  FROM pg_attribute a
  JOIN pg_class c      ON c.oid = a.attrelid
  JOIN pg_namespace ns ON ns.oid = c.relnamespace
 WHERE ns.nspname = 'public' AND c.relkind = 'r'
   AND a.attnum > 0 AND NOT a.attisdropped
   AND a.atttypid = 'cuit_dom'::regtype
 ORDER BY 1, 2;

\echo '--- Columnas de tablas que usan estado_documento ---'
SELECT c.relname AS tabla, a.attname AS columna
  FROM pg_attribute a
  JOIN pg_class c      ON c.oid = a.attrelid
  JOIN pg_namespace ns ON ns.oid = c.relnamespace
 WHERE ns.nspname = 'public' AND c.relkind = 'r'
   AND a.attnum > 0 AND NOT a.attisdropped
   AND a.atttypid = 'estado_documento'::regtype
 ORDER BY 1, 2;

-- ---------------------------------------------------------------------
-- 2. Verificaciones de uso (fallan con EXCEPTION si algo no coincide)
-- ---------------------------------------------------------------------

DO $$
DECLARE
    n INTEGER;
BEGIN
    -- 2.1 El ENUM tiene exactamente los tres estados, en el orden del circuito.
    IF (SELECT array_agg(enumlabel::text ORDER BY enumsortorder)
          FROM pg_enum
         WHERE enumtypid = 'estado_documento'::regtype)
       IS DISTINCT FROM ARRAY['en_confeccion', 'terminado', 'procesado'] THEN
        RAISE EXCEPTION 'FALLO: estado_documento no tiene los valores esperados (en_confeccion, terminado, procesado)';
    END IF;
    RAISE NOTICE 'OK: estado_documento = en_confeccion < terminado < procesado';

    -- 2.2 cuit_dom se usa en las 6 columnas CUIT:
    --     empleado.cuit, bodega.cuit, lote_uva.cuit_bodega, vino.cuit_bodega,
    --     transportista.cuit, ingreso.cuit_bodega
    SELECT count(*) INTO n
      FROM pg_attribute a
      JOIN pg_class c      ON c.oid = a.attrelid
      JOIN pg_namespace ns ON ns.oid = c.relnamespace
     WHERE ns.nspname = 'public' AND c.relkind = 'r'
       AND a.attnum > 0 AND NOT a.attisdropped
       AND a.atttypid = 'cuit_dom'::regtype;
    IF n <> 6 THEN
        RAISE EXCEPTION 'FALLO: se esperaban 6 columnas con cuit_dom y hay %', n;
    END IF;
    RAISE NOTICE 'OK: cuit_dom se usa en 6 columnas';

    -- 2.3 Ninguna columna con "cuit" en el nombre usa otro tipo.
    SELECT count(*) INTO n
      FROM pg_attribute a
      JOIN pg_class c      ON c.oid = a.attrelid
      JOIN pg_namespace ns ON ns.oid = c.relnamespace
     WHERE ns.nspname = 'public' AND c.relkind = 'r'
       AND a.attnum > 0 AND NOT a.attisdropped
       AND a.attname LIKE '%cuit%'
       AND a.atttypid <> 'cuit_dom'::regtype;
    IF n <> 0 THEN
        RAISE EXCEPTION 'FALLO: hay % columnas "cuit" que no usan el dominio cuit_dom', n;
    END IF;
    RAISE NOTICE 'OK: ninguna columna cuit usa un tipo distinto de cuit_dom';

    -- 2.4 estado_documento se usa en las 2 columnas de estado:
    --     ingreso.estado y transferencia.estado
    SELECT count(*) INTO n
      FROM pg_attribute a
      JOIN pg_class c      ON c.oid = a.attrelid
      JOIN pg_namespace ns ON ns.oid = c.relnamespace
     WHERE ns.nspname = 'public' AND c.relkind = 'r'
       AND a.attnum > 0 AND NOT a.attisdropped
       AND a.atttypid = 'estado_documento'::regtype;
    IF n <> 2 THEN
        RAISE EXCEPTION 'FALLO: se esperaban 2 columnas con estado_documento y hay %', n;
    END IF;
    RAISE NOTICE 'OK: estado_documento se usa en 2 columnas (ingreso, transferencia)';

    -- 2.5 Ninguna columna "estado" usa otro tipo (texto libre).
    SELECT count(*) INTO n
      FROM pg_attribute a
      JOIN pg_class c      ON c.oid = a.attrelid
      JOIN pg_namespace ns ON ns.oid = c.relnamespace
     WHERE ns.nspname = 'public' AND c.relkind = 'r'
       AND a.attnum > 0 AND NOT a.attisdropped
       AND a.attname = 'estado'
       AND a.atttypid <> 'estado_documento'::regtype;
    IF n <> 0 THEN
        RAISE EXCEPTION 'FALLO: hay % columnas "estado" que no usan estado_documento', n;
    END IF;
    RAISE NOTICE 'OK: ninguna columna estado usa un tipo distinto de estado_documento';
END
$$;

-- ---------------------------------------------------------------------
-- 3. Comportamiento: los valores invalidos se rechazan
-- ---------------------------------------------------------------------

-- 3.1 DOMAIN: valores validos e invalidos.
DO $$
BEGIN
    PERFORM '30123456789'::cuit_dom;
    RAISE NOTICE 'OK: cuit_dom acepta 11 digitos';
END
$$;

DO $$
BEGIN
    PERFORM '123'::cuit_dom;
    RAISE EXCEPTION 'FALLO: cuit_dom acepto un CUIT de 3 digitos';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK: cuit_dom rechaza un CUIT de 3 digitos (23514)';
END
$$;

DO $$
BEGIN
    PERFORM '3012345678A'::cuit_dom;
    RAISE EXCEPTION 'FALLO: cuit_dom acepto un CUIT con letras';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK: cuit_dom rechaza un CUIT con letras (23514)';
END
$$;

-- 3.2 ENUM: un estado fuera del circuito se rechaza.
DO $$
BEGIN
    PERFORM 'cancelado'::estado_documento;
    RAISE EXCEPTION 'FALLO: estado_documento acepto un valor inexistente';
EXCEPTION WHEN invalid_text_representation THEN
    RAISE NOTICE 'OK: estado_documento rechaza ''cancelado'' (22P02)';
END
$$;

-- 3.3 El orden del ENUM sirve para validar transiciones sin retroceso (RN-10, RN-11).
DO $$
BEGIN
    IF NOT ('en_confeccion'::estado_documento < 'terminado'::estado_documento
        AND 'terminado'::estado_documento     < 'procesado'::estado_documento) THEN
        RAISE EXCEPTION 'FALLO: el orden de estado_documento no es el del circuito';
    END IF;
    RAISE NOTICE 'OK: el orden del ENUM permite comparar estados con < y >';
END
$$;

-- 3.4 En las tablas reales: el CUIT invalido se rechaza al insertar.
--     Si el INSERT no fallara, el RAISE EXCEPTION aborta el script y la
--     transaccion del bloque se descarta (no queda ninguna fila).
DO $$
BEGIN
    INSERT INTO bodega (cuit, razon_social, domicilio)
    VALUES ('123', 'Prueba tipos', 'Prueba tipos');
    RAISE EXCEPTION 'FALLO: bodega acepto un CUIT invalido';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK: bodega.cuit rechaza un CUIT invalido';
END
$$;

-- 3.5 En las tablas reales: un estado inexistente se rechaza al insertar.
DO $$
BEGIN
    INSERT INTO ingreso (fecha, estado, cod_transportista, cuit_bodega)
    VALUES (CURRENT_DATE, 'cancelado', 1, '30123456789');
    RAISE EXCEPTION 'FALLO: ingreso acepto un estado inexistente';
EXCEPTION WHEN invalid_text_representation THEN
    RAISE NOTICE 'OK: ingreso.estado rechaza un estado inexistente';
END
$$;

\echo '=== Verificacion de tipos terminada sin errores ==='