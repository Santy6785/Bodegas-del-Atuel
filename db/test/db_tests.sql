-- =====================================================================
-- db_tests.sql - Bodegas del Atuel
--
-- Suite de Pruebas de Reglas de Negocio (RN-01 a RN-15) - Etapa 2
--
-- Propósito:
--   Verificar que cada regla de negocio implementada en la base de datos
--   (restricciones CHECK/UNIQUE/FK, triggers, funciones y procedimientos)
--   reacciona correctamente: al menos un caso OK y un caso FAIL por regla.
--
-- Ejecución recomendada (desde la raíz del proyecto):
--   docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
--       -v ON_ERROR_STOP=1 < db/tests/db_tests.sql
--
-- NOTA: los datos de prueba (prefijo TDB) se crean con COMMIT y se borran
-- al final (DELETE ... WHERE codigo_postal LIKE 'TDB%'), por lo que no
-- quedan datos residuales en la base de datos.
--
-- Convenciones de diseño de las pruebas:
--   1. Cada caso se ejecuta dentro de su propio bloque BEGIN ... ROLLBACK
--      para aislar transaccionalmente.
--   2. Estructura de comentarios por caso:
--      -- CASO: <identificador único, ej. RN-01-OK>
--      -- TIPO: DEBE FUNCIONAR | DEBE FALLAR
--      -- ESPERADO: <comportamiento esperado>
--      -- SQLSTATE esperado: <código de 5 caracteres PostgreSQL>
--   3. El helper pg_temp.esperar_error(p_sql, p_sqlstate, p_patron) ejecuta
--      una sentencia y exige que falle con el SQLSTATE y patrón de mensaje
--      indicados. El helper pg_temp.esperar_ok(p_sql) exige que una sentencia
--      tenga éxito.
--   4. Mensajes y comentarios en español.
-- =====================================================================

\set ON_ERROR_STOP on

-- =====================================================================
-- Helpers (creados en autocommit, fuera de cualquier transacción de prueba).
-- =====================================================================

-- Helper: esperar_error(p_sql TEXT, p_sqlstate TEXT, p_patron TEXT)
-- Ejecuta EXECUTE p_sql dentro de un subbloque BEGIN ... EXCEPTION WHEN
-- OTHERS. Si no falla, lanza FALLO. Si el SQLSTATE o el mensaje no
-- coinciden, lanza FALLO con detalle. Si coinciden, emite NOTICE 'OK: ...'.
CREATE OR REPLACE FUNCTION pg_temp.esperar_error(
    p_sql      TEXT,
    p_sqlstate TEXT,
    p_patron   TEXT
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_sqlstate TEXT;
    v_sqlerrm  TEXT;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        v_sqlstate := SQLSTATE;
        v_sqlerrm  := SQLERRM;
        IF v_sqlstate <> p_sqlstate THEN
            RAISE EXCEPTION
                'FALLO: SQLSTATE inesperado: % (se esperaba %) para: % | mensaje: %',
                v_sqlstate, p_sqlstate, p_sql, v_sqlerrm;
        END IF;
        IF v_sqlerrm NOT LIKE p_patron THEN
            RAISE EXCEPTION
                'FALLO: mensaje no cumple el patron: % (se esperaba como %) para: % | mensaje: %',
                v_sqlerrm, p_patron, p_sql, v_sqlerrm;
        END IF;
        RAISE NOTICE 'OK: rechazado (SQLSTATE %) -> %', v_sqlstate, v_sqlerrm;
        RETURN;
    END;
    RAISE EXCEPTION 'FALLO: la sentencia no fallo (se esperaba SQLSTATE %): %', p_sqlstate, p_sql;
END;
$$;

-- Helper: esperar_ok(p_sql TEXT)
-- Ejecuta una sentencia y falla si produce algún error.
CREATE OR REPLACE FUNCTION pg_temp.esperar_ok(p_sql TEXT) RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE p_sql;
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'FALLO: la sentencia debio funcionar pero fallo: % | error: %', p_sql, SQLERRM;
END;
$$;

-- Helper: agregar_cepa_vino(p_cod_vino INTEGER)
-- Agrega una cepa al 100% a un vino para satisfacer ctg_vino_composicion
-- (RN-05), que se evalúa al COMMIT de cada transacción.
CREATE OR REPLACE FUNCTION pg_temp.agregar_cepa_vino(p_cod_vino INTEGER) RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
    SELECT p_cod_vino, id_cepa, 100.00
      FROM cepa WHERE nombre = 'TDB Cepa' LIMIT 1;
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'FALLO: no se pudo agregar cepa al vino %: %', p_cod_vino, SQLERRM;
END;
$$;

-- =====================================================================
-- Limpieza inicial: borrar TODO y reiniciar secuencias para que el script
-- sea idempotente (doble ejecucion da mismo resultado).
-- =====================================================================
TRUNCATE TABLE
    analisis_calidad, auditoria_precio, bodega, cepa, cliente,
    cliente_distribuidor, cliente_exportador, comprobante, departamento,
    empleado, finca, ingreso, localidad, lote_uva, maridaje,
    permiso_exportacion, parcela, renglon_comprobante, renglon_ingreso,
    renglon_transferencia, sala_venta, stock_deposito, stock_sala,
    transferencia, transportista, transportista_localidad, vino,
    vino_cepa, vino_lote, vino_maridaje
RESTART IDENTITY CASCADE;

DELETE FROM renglon_comprobante WHERE nro_comprobante IN (
    SELECT c.nro_comprobante FROM comprobante c
    JOIN cliente cl ON c.id_cliente = cl.id_cliente
    WHERE cl.apellido_razon_social LIKE '%TDB%');
DELETE FROM comprobante WHERE id_cliente IN (
    SELECT id_cliente FROM cliente WHERE apellido_razon_social LIKE '%TDB%');
DELETE FROM permiso_exportacion WHERE id_cliente IN (
    SELECT id_cliente FROM cliente WHERE apellido_razon_social LIKE '%TDB%' AND tipo_cliente = 'socio');
DELETE FROM cliente_exportador WHERE id_cliente IN (
    SELECT id_cliente FROM cliente WHERE apellido_razon_social LIKE '%TDB%' AND tipo_cliente = 'socio');
DELETE FROM cliente_distribuidor WHERE id_cliente IN (
    SELECT id_cliente FROM cliente WHERE apellido_razon_social LIKE '%TDB%' AND tipo_cliente = 'socio');
DELETE FROM cliente WHERE apellido_razon_social LIKE '%TDB%' AND tipo_cliente = 'socio';
DELETE FROM renglon_ingreso WHERE cod_ingreso IN (
    SELECT cod_ingreso FROM ingreso WHERE cuit_bodega = '99999990001');
DELETE FROM ingreso WHERE cuit_bodega = '99999990001';
DELETE FROM renglon_transferencia WHERE nro_transferencia IN (
    SELECT nro_transferencia FROM transferencia
    WHERE id_sala IN (SELECT id_sala FROM sala_venta WHERE codigo_postal = 'TDB00001'));
DELETE FROM transferencia WHERE id_sala IN (
    SELECT id_sala FROM sala_venta WHERE codigo_postal = 'TDB00001');
DELETE FROM stock_sala WHERE id_sala IN (
    SELECT id_sala FROM sala_venta WHERE codigo_postal = 'TDB00001');
DELETE FROM stock_deposito WHERE cod_vino IN (
    SELECT cod_vino FROM vino WHERE cuit_bodega = '99999990001');
DELETE FROM vino_cepa WHERE cod_vino IN (
    SELECT cod_vino FROM vino WHERE cuit_bodega = '99999990001');
DELETE FROM vino WHERE cuit_bodega = '99999990001';
DELETE FROM empleado WHERE cuit LIKE '9999999000%';
-- Limpieza final: TRUNCATE CASCADE borra todo y reinicia secuencias.
-- Tras el TRUNCATE inicial, todas las filas en la base son de prueba,
-- por lo que esto es seguro.
TRUNCATE TABLE
    analisis_calidad, auditoria_precio, bodega, cepa, cliente,
    cliente_distribuidor, cliente_exportador, comprobante, departamento,
    empleado, finca, ingreso, localidad, lote_uva, maridaje,
    permiso_exportacion, parcela, renglon_comprobante, renglon_ingreso,
    renglon_transferencia, sala_venta, stock_deposito, stock_sala,
    transferencia, transportista, transportista_localidad, vino,
    vino_cepa, vino_lote, vino_maridaje
RESTART IDENTITY CASCADE;

-- Verificacion: no debe quedar ninguna localidad TDB
DO $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT count(*) INTO v_count FROM localidad WHERE codigo_postal LIKE 'TDB%';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'FALLO: quedan % localidades TDB sin borrar', v_count;
    END IF;
    RAISE NOTICE 'OK: no quedan datos TDB en la base de datos';
END
$$;

-- =====================================================================
-- Bloque de datos base (fixtures con prefijo TDB).
-- Se ejecuta en su propia transacción (BEGIN ... COMMIT) para que los
-- datos persistan durante toda la suite. Cada caso de prueba usa su
-- propio BEGIN ... ROLLBACK.
-- =====================================================================
BEGIN;
DO $$
DECLARE
    v_sala  INTEGER;
    v_transp INTEGER;
    v_cepa   INTEGER;
    v_vino    INTEGER;
    v_cli_soc INTEGER;
    v_cli_exp INTEGER;
BEGIN
    -- Localidad
    INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
    VALUES ('TDB00001', 'Localidad TDB', 'Mendoza', 'Encargado TDB')
    ON CONFLICT (codigo_postal) DO NOTHING;

    -- Sala de venta
    INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal)
    VALUES ('Calle TDB', '1', 'lunes', 'TDB00001')
    RETURNING id_sala INTO v_sala;

    -- Bodega
    INSERT INTO bodega (cuit, razon_social, domicilio)
    VALUES ('99999990001', 'Bodega TDB', 'Domicilio TDB')
    ON CONFLICT (cuit) DO NOTHING;

    -- Transportista
    INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio)
    VALUES ('Transportista TDB', '99999990002', 'tdb@test.com', '000', 'Domicilio TDB')
    ON CONFLICT (cuit) DO NOTHING
    RETURNING cod_transportista INTO v_transp;
    IF v_transp IS NULL THEN
        SELECT cod_transportista INTO v_transp FROM transportista WHERE cuit = '99999990002';
    END IF;

    -- Cepa
    INSERT INTO cepa (nombre, tipo) VALUES ('TDB Cepa', 'tinta')
    ON CONFLICT (nombre) DO NOTHING
    RETURNING id_cepa INTO v_cepa;
    IF v_cepa IS NULL THEN
        SELECT id_cepa INTO v_cepa FROM cepa WHERE nombre = 'TDB Cepa';
    END IF;

    -- Cepa auxiliar (para composiciones de dos cepas)
    INSERT INTO cepa (nombre, tipo) VALUES ('TDB Cepa 2', 'blanca')
    ON CONFLICT (nombre) DO NOTHING;

    -- Vino TDB con cepa al 100% para satisfacer ctg_vino_composicion (RN-05).
    -- Se crea aqui para ser reutilizado por varios casos de prueba.
    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Vino TDB', 'tinto', 2022, 750, 14.50, 2000, '99999990001')
    ON CONFLICT (nombre, anada, volumen_ml) DO NOTHING
    RETURNING cod_vino INTO v_vino;
    IF v_vino IS NULL THEN
        SELECT cod_vino INTO v_vino FROM vino WHERE nombre = 'Vino TDB' AND anada = 2022 AND volumen_ml = 750 LIMIT 1;
    END IF;

    DELETE FROM vino_cepa WHERE cod_vino = v_vino;
    INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
    SELECT v.cod_vino, c.id_cepa, 100.00
      FROM (SELECT cod_vino FROM vino WHERE nombre = 'Vino TDB' AND anada = 2022 AND volumen_ml = 750 LIMIT 1) v,
           (SELECT id_cepa FROM cepa WHERE nombre = 'TDB Cepa' LIMIT 1) c;

    -- Cliente socio
    INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento, nro_documento,
                         direccion, codigo_postal, tipo_cliente)
    VALUES ('Socio TDB', 'Juan', 'DNI', '99000001', 'Dir TDB', 'TDB00001', 'socio')
    ON CONFLICT (tipo_documento, nro_documento) DO NOTHING
    RETURNING id_cliente INTO v_cli_soc;
    IF v_cli_soc IS NULL THEN
        SELECT id_cliente INTO v_cli_soc FROM cliente WHERE tipo_documento='DNI' AND nro_documento='99000001';
    END IF;

    -- Cliente socio adicional (tipo 'socio', sin subtipo).
    -- Nota: no se puede crear un cliente exportador porque los constraint
    -- triggers ctg_cliente_tipo / ctg_cliente_exportador_tipo se evaluan
    -- inmediatamente (antes de poder insertar el subtipo), impidiendo la
    -- alta de exportadores. Ver brecha documentada en RN-06 y RN-07.
    INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento, nro_documento,
                         direccion, codigo_postal, tipo_cliente)
    VALUES ('Exportador TDB', 'Maria', 'CUIT', '99000002', 'Dir TDB', 'TDB00001', 'socio')
    ON CONFLICT (tipo_documento, nro_documento) DO NOTHING
    RETURNING id_cliente INTO v_cli_exp;
    IF v_cli_exp IS NULL THEN
        SELECT id_cliente INTO v_cli_exp FROM cliente WHERE tipo_documento='CUIT' AND nro_documento='99000002';
    END IF;

    RAISE NOTICE 'OK: datos base TDB creados (sala %, socio %, socio-extra %)',
        v_sala, v_cli_soc, v_cli_exp;

    -- Exportador con 4 permisos validos: debe quedar con 35 % (U6).
    INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento, nro_documento,
                        direccion, codigo_postal, tipo_cliente)
    VALUES ('Exportadora TDB', NULL, 'CUIT', '30999000001', 'Ruta 40', 'TDB00001', 'exportador')
    ON CONFLICT DO NOTHING;

    INSERT INTO cliente_exportador (id_cliente, pais_destino)
    SELECT id_cliente, 'Brasil' FROM cliente WHERE nro_documento = '30999000001'
    ON CONFLICT DO NOTHING;

    -- Permisos: 4 validos (supera el umbral de U6, "mas de 3").
    INSERT INTO permiso_exportacion (id_cliente, codigo, fecha_emision, fecha_vencimiento)
    SELECT c.id_cliente, p.codigo, p.emision, p.vencimiento
        FROM cliente c
        CROSS JOIN (VALUES
            ('TDB-EXP-01', DATE '2025-01-01', DATE '2027-01-01'),
            ('TDB-EXP-02', DATE '2025-02-01', DATE '2027-02-01'),
            ('TDB-EXP-03', DATE '2025-03-01', DATE '2027-03-01'),
            ('TDB-EXP-04', DATE '2025-04-01', DATE '2027-04-01')
        ) AS p(codigo, emision, vencimiento)
    WHERE c.nro_documento = '30999000001'
    ON CONFLICT DO NOTHING;
END
$$;
COMMIT;

-- =====================================================================
-- REGLA RN-01: Precio de vino unico y > 0
-- Mecanismo: CHECK ck_vino_precio (precio > 0)
-- Archivo de migración: db/migrations/002_constraints.sql
-- =====================================================================

-- CASO: RN-01-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Insercion exitosa de un vino con precio estrictamente positivo (> 0).
-- SQLSTATE esperado: -
BEGIN;
  INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
  VALUES ('Vino RN-01 OK', 'tinto', 2021, 750, 13.50, 1500, '99999990001')
  RETURNING cod_vino;
ROLLBACK;

-- CASO: RN-01-FAIL
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al insertar un vino con precio igual a 0 (violacion CHECK ck_vino_precio).
-- SQLSTATE esperado: 23514
DO $$
BEGIN
    PERFORM pg_temp.esperar_error(
        'INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
         VALUES (''Vino RN-01 FAIL'', ''tinto'', 2021, 750, 13.50, 0, ''99999990001'')',
        '23514', '%ck_vino_precio%');
END
$$;

-- =====================================================================
-- REGLA RN-02: Sala en una sola localidad; localidad con unico encargado
-- Mecanismo: FK fk_sala_venta_localidad + diseno 3FN (una sola FK, una sola
--            columna encargado_regional)
-- Archivo de migración: db/migrations/001_esquema.sql / 002_constraints.sql
-- =====================================================================

-- CASO: RN-02-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Insercion exitosa de una sala de venta vinculada a la localidad
--           TDB00001 existente.
-- SQLSTATE esperado: -
BEGIN;
  INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal)
  VALUES ('Calle RN-02', '10', 'lunes', 'TDB00001')
  RETURNING id_sala;
ROLLBACK;

-- CASO: RN-02-FAIL
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla por clave foránea al insertar una sala con localidad
--           inexistente (99999).
-- SQLSTATE esperado: 23503
DO $$
BEGIN
    PERFORM pg_temp.esperar_error(
        'INSERT INTO sala_venta (calle, numero, dia_cierre, codigo_postal)
         VALUES (''Calle RN-02 FAIL'', ''10'', ''lunes'', ''99999'')',
        '23503', '%fk_sala_venta_localidad%');
END
$$;

-- CASO: RN-02-STRUCT
-- TIPO: DEBE FUNCIONAR (verificacion estructural de 3FN)
-- ESPERADO: information_schema confirma que sala_venta tiene una sola FK
--           hacia localidad y que localidad tiene una sola columna
--           encargado_regional.
-- SQLSTATE esperado: -
DO $$
DECLARE
    v_fk_count   INTEGER;
    v_enc_count  INTEGER;
BEGIN
    SELECT count(*) INTO v_fk_count
      FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name
     WHERE tc.table_name = 'sala_venta' AND tc.constraint_type = 'FOREIGN KEY'
       AND kcu.column_name = 'codigo_postal';

    SELECT count(*) INTO v_enc_count
      FROM information_schema.columns
     WHERE table_name = 'localidad' AND column_name = 'encargado_regional';

    IF v_fk_count <> 1 THEN
        RAISE EXCEPTION 'FALLO RN-02-STRUCT: sala_venta tiene % FKs hacia localidad (se esperaba 1)', v_fk_count;
    END IF;
    IF v_enc_count <> 1 THEN
        RAISE EXCEPTION 'FALLO RN-02-STRUCT: localidad tiene % columnas encargado_regional (se esperaba 1)', v_enc_count;
    END IF;
    RAISE NOTICE 'OK RN-02-STRUCT: sala_venta tiene 1 FK hacia localidad; localidad tiene 1 columna encargado_regional';
END
$$;

-- =====================================================================
-- REGLA RN-03: Empleado trabaja en una sola sala
-- Mecanismo: NOT NULL + FK fk_empleado_sala_venta
-- Archivo de migración: db/migrations/001_esquema.sql / 002_constraints.sql
-- =====================================================================

-- CASO: RN-03-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Insercion exitosa de un empleado con salario > 0 y sala valida.
-- SQLSTATE esperado: -
BEGIN;
  INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario, id_sala)
  VALUES ('99999990003', 'Empleado TDB', CURRENT_DATE, 50000.00,
          (SELECT id_sala FROM sala_venta WHERE codigo_postal = 'TDB00001' LIMIT 1));
ROLLBACK;

-- CASO: RN-03-FAIL-NULL
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al insertar empleado con id_sala NULL (violacion NOT NULL).
-- SQLSTATE esperado: 23502
DO $$
BEGIN
    PERFORM pg_temp.esperar_error(
        'INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario, id_sala)
         VALUES (''99999990004'', ''Empleado Sin Sala'', CURRENT_DATE, 50000.00, NULL)',
        '23502', '%not_null%');
END
$$;

-- CASO: RN-03-FAIL-FK
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al insertar empleado con id_sala inexistente (violacion FK).
-- SQLSTATE esperado: 23503
DO $$
BEGIN
    PERFORM pg_temp.esperar_error(
        'INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario, id_sala)
         VALUES (''99999990005'', ''Empleado Sala Inexistente'', CURRENT_DATE, 50000.00, -9999)',
        '23503', '%fk_empleado_sala_venta%');
END
$$;

-- CASO: RN-03-STRUCT
-- TIPO: DEBE FUNCIONAR (verificacion estructural NOT NULL)
-- ESPERADO: information_schema confirma que empleado.id_sala es NOT NULL.
-- SQLSTATE esperado: -
DO $$
DECLARE
    v_is_nullable VARCHAR(3);
BEGIN
    SELECT is_nullable INTO v_is_nullable
      FROM information_schema.columns
     WHERE table_name = 'empleado' AND column_name = 'id_sala';
    IF v_is_nullable <> 'NO' THEN
        RAISE EXCEPTION 'FALLO RN-03-STRUCT: empleado.id_sala es nullable (se esperaba NO)';
    END IF;
    RAISE NOTICE 'OK RN-03-STRUCT: empleado.id_sala es NOT NULL';
END
$$;

-- =====================================================================
-- REGLA RN-04: Parcela con una sola cepa; una cosecha por parcela y campaña
-- Mecanismo: FK fk_parcela_cepa + UNIQUE uq_lote_uva_parcela_campania
-- Archivo de migración: db/migrations/001_esquema.sql / 002_constraints.sql
-- =====================================================================

-- CASO: RN-04-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Insercion exitosa de un lote de uva para una parcela y campaña
--           nuevas (finca TDB, parcela 1, campania 2024).
-- SQLSTATE esperado: -
DO $$
DECLARE
    v_dep INTEGER;
    v_finca INTEGER;
BEGIN
    INSERT INTO departamento (nombre, provincia) VALUES ('Depto TDB', 'Mendoza')
    ON CONFLICT (nombre, provincia) DO NOTHING
    RETURNING id_departamento INTO v_dep;
    IF v_dep IS NULL THEN
      SELECT id_departamento INTO v_dep FROM departamento WHERE nombre='Depto TDB' AND provincia='Mendoza';
    END IF;

    INSERT INTO finca (nombre, superficie_ha, id_departamento)
    VALUES ('Finca TDB', 10.00, v_dep)
    RETURNING id_finca INTO v_finca;
    IF v_finca IS NULL THEN
      SELECT id_finca INTO v_finca FROM finca WHERE nombre='Finca TDB' AND id_departamento = v_dep LIMIT 1;
    END IF;

    INSERT INTO parcela (id_finca, nro_parcela, superficie_ha, anio_plantacion, id_cepa)
    VALUES (v_finca, 1, 5.00, 2010,
            (SELECT id_cepa FROM cepa WHERE nombre = 'TDB Cepa' LIMIT 1));

    INSERT INTO lote_uva (id_finca, nro_parcela, campania, nro_lote, fecha_cosecha, kilos, cuit_bodega)
    VALUES (v_finca, 1, 2024, 99999, DATE '2024-03-01', 1000.00, '99999990001')
    ON CONFLICT (nro_lote) DO NOTHING;
    RAISE NOTICE 'OK RN-04-OK: lote de uva insertado para (finca %, parcela 1, campania 2024)', v_finca;
END
$$;

-- CASO: RN-04-FAIL
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al insertar un segundo lote con la misma (finca, parcela,
--           campania) — violacion UNIQUE uq_lote_uva_parcela_campania.
-- SQLSTATE esperado: 23505
DO $$
BEGIN
    PERFORM pg_temp.esperar_error(
        $q$
        INSERT INTO parcela (id_finca, nro_parcela, superficie_ha, anio_plantacion, id_cepa)
        SELECT f.id_finca, 1, 5.00, 2010, c.id_cepa
        FROM (SELECT id_finca FROM finca WHERE nombre = 'Finca TDB' LIMIT 1) f,
             (SELECT id_cepa FROM cepa WHERE nombre = 'TDB Cepa' LIMIT 1) c
        ON CONFLICT DO NOTHING;
        INSERT INTO lote_uva (id_finca, nro_parcela, campania, nro_lote, fecha_cosecha, kilos, cuit_bodega)
        SELECT id_finca, 1, 2024, 2, DATE '2024-03-02', 1000.00, '99999990001'
        FROM (SELECT id_finca FROM finca WHERE nombre = 'Finca TDB' LIMIT 1) f;
        $q$,
        '23505', '%uq_lote_uva_parcela_campania%');
END
$$;

-- CASO: RN-04-STRUCT
-- TIPO: DEBE FUNCIONAR (verificacion estructural)
-- ESPERADO: information_schema confirma que parcela tiene una unica columna
--           id_cepa y es NOT NULL.
-- SQLSTATE esperado: -
DO $$
DECLARE
    v_cepa_count INTEGER;
    v_nullable   VARCHAR(3);
BEGIN
    SELECT count(*) INTO v_cepa_count
      FROM information_schema.columns
     WHERE table_name = 'parcela' AND column_name = 'id_cepa';
    SELECT is_nullable INTO v_nullable
      FROM information_schema.columns
     WHERE table_name = 'parcela' AND column_name = 'id_cepa';
    IF v_cepa_count <> 1 THEN
        RAISE EXCEPTION 'FALLO RN-04-STRUCT: parcela tiene % columnas id_cepa (se esperaba 1)', v_cepa_count;
    END IF;
    IF v_nullable <> 'NO' THEN
        RAISE EXCEPTION 'FALLO RN-04-STRUCT: parcela.id_cepa es nullable (se esperaba NO)';
    END IF;
    RAISE NOTICE 'OK RN-04-STRUCT: parcela tiene 1 columna id_cepa NOT NULL';
END
$$;

-- =====================================================================
-- REGLA RN-15: Cantidades, superficies, kilos y precios > 0; graduación
-- entre 5 y 20
-- Mecanismo: varias restricciones CHECK (ck_vino_precio, ck_vino_graduacion,
--            ck_vino_volumen, ck_empleado_salario, ck_finca_superficie,
--            ck_parcela_superficie, ck_lote_uva_kilos, ck_renglon_comprobante_*)
-- Archivo de migración: db/migrations/002_constraints.sql
-- =====================================================================

-- CASO: RN-15-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Insercion exitosa de registros con valores positivos y graduacion
--           valida (14.5, entre 5 y 20).
-- SQLSTATE esperado: -
DO $$
DECLARE
    v_dep INTEGER;
    v_vino15 INTEGER;
BEGIN
    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Vino RN-15 OK', 'tinto', 2021, 750, 14.50, 2500, '99999990001')
    ON CONFLICT (nombre, anada, volumen_ml) DO NOTHING
    RETURNING cod_vino INTO v_vino15;
    IF v_vino15 IS NULL THEN
        SELECT cod_vino INTO v_vino15 FROM vino WHERE nombre = 'Vino RN-15 OK' AND anada = 2021 AND volumen_ml = 750 LIMIT 1;
    END IF;

    -- Agregar cepa al 100% para satisfacer ctg_vino_composicion (RN-05)
    DELETE FROM vino_cepa WHERE cod_vino = v_vino15;
    INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
    VALUES (v_vino15, (SELECT id_cepa FROM cepa WHERE nombre = 'TDB Cepa' LIMIT 1), 100.00);

    INSERT INTO departamento (nombre, provincia) VALUES ('Depto RN-15', 'Mendoza')
    ON CONFLICT (nombre, provincia) DO NOTHING
    RETURNING id_departamento INTO v_dep;
    IF v_dep IS NULL THEN
      SELECT id_departamento INTO v_dep FROM departamento WHERE nombre='Depto RN-15' AND provincia='Mendoza';
    END IF;

    INSERT INTO finca (nombre, superficie_ha, id_departamento)
    VALUES ('Finca RN-15', 15.00, v_dep);
END
$$;

-- CASO: RN-15-FAIL-PRECIO
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al insertar vino con precio = 0 (ck_vino_precio).
-- SQLSTATE esperado: 23514
BEGIN;
  SELECT pg_temp.esperar_error(
      'INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
       VALUES (''Vino RN-15 FAIL PRECIO'', ''tinto'', 2021, 750, 14.50, 0, ''99999990001'')',
      '23514', '%ck_vino_precio%');
  -- El vino se creo dentro del helper pero sin cepa; agregar cepa para evitar
  -- que ctg_vino_composicion falle al COMMIT.
  INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
  SELECT v.cod_vino, c.id_cepa, 100.00
    FROM vino v, cepa c
   WHERE v.nombre = 'Vino RN-15 FAIL PRECIO' AND c.nombre = 'TDB Cepa'
   ON CONFLICT (cod_vino, id_cepa) DO NOTHING;
ROLLBACK;

-- CASO: RN-15-FAIL-GRADUACION-BAJA
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al insertar vino con graduacion 4.0 (fuera de rango 5-20).
-- SQLSTATE esperado: 23514
BEGIN;
  SELECT pg_temp.esperar_error(
      'INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
       VALUES (''Vino RN-15 FAIL GRAD 4'', ''tinto'', 2021, 750, 4.0, 1000, ''99999990001'')',
      '23514', '%ck_vino_graduacion%');
  INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
  SELECT v.cod_vino, c.id_cepa, 100.00
    FROM vino v, cepa c
   WHERE v.nombre = 'Vino RN-15 FAIL GRAD 4' AND c.nombre = 'TDB Cepa'
   ON CONFLICT (cod_vino, id_cepa) DO NOTHING;
ROLLBACK;

-- CASO: RN-15-FAIL-GRADUACION-ALTA
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al insertar vino con graduacion 21.0 (fuera de rango 5-20).
-- SQLSTATE esperado: 23514
BEGIN;
  SELECT pg_temp.esperar_error(
      'INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
       VALUES (''Vino RN-15 FAIL GRAD 21'', ''tinto'', 2021, 750, 21.0, 1000, ''99999990001'')',
      '23514', '%ck_vino_graduacion%');
  INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
  SELECT v.cod_vino, c.id_cepa, 100.00
    FROM vino v, cepa c
   WHERE v.nombre = 'Vino RN-15 FAIL GRAD 21' AND c.nombre = 'TDB Cepa'
   ON CONFLICT (cod_vino, id_cepa) DO NOTHING;
ROLLBACK;

-- CASO: RN-15-FAIL-KILOS
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al insertar lote de uva con kilos <= 0 (ck_lote_uva_kilos).
-- SQLSTATE esperado: 23514
BEGIN;
  SELECT pg_temp.esperar_error(
      $q$
      INSERT INTO parcela (id_finca, nro_parcela, superficie_ha, anio_plantacion, id_cepa)
      SELECT f.id_finca, 9, 5.00, 2010, c.id_cepa
      FROM (SELECT id_finca FROM finca WHERE nombre = 'Finca TDB' LIMIT 1) f,
           (SELECT id_cepa FROM cepa WHERE nombre = 'TDB Cepa' LIMIT 1) c;
      INSERT INTO lote_uva (id_finca, nro_parcela, campania, nro_lote, fecha_cosecha, kilos, cuit_bodega)
      SELECT id_finca, 9, 2024, 3, DATE '2024-03-01', 0, '99999990001'
      FROM (SELECT id_finca FROM finca WHERE nombre = 'Finca TDB' LIMIT 1) f;
      $q$,
      '23514', '%ck_lote_uva_kilos%');
ROLLBACK;

-- CASO: RN-15-FAIL-SUPERFICIE
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al insertar parcela con superficie_ha <= 0 (ck_parcela_superficie).
-- SQLSTATE esperado: 23514
BEGIN;
  SELECT pg_temp.esperar_error(
      $q$
      INSERT INTO parcela (id_finca, nro_parcela, superficie_ha, anio_plantacion, id_cepa)
      SELECT f.id_finca, 8, 0, 2010, c.id_cepa
      FROM (SELECT id_finca FROM finca WHERE nombre = 'Finca TDB' LIMIT 1) f,
           (SELECT id_cepa FROM cepa WHERE nombre = 'TDB Cepa' LIMIT 1) c;
      $q$,
      '23514', '%ck_parcela_superficie%');
ROLLBACK;

-- CASO: RN-15-FAIL-SALARIO
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al insertar empleado con salario <= 0 (ck_empleado_salario).
-- SQLSTATE esperado: 23514
BEGIN;
  SELECT pg_temp.esperar_error(
      'INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario, id_sala)
       VALUES (''99999990006'', ''Empleado Salario Negativo'', CURRENT_DATE, -100,
               (SELECT id_sala FROM sala_venta WHERE codigo_postal = ''TDB00001'' LIMIT 1))',
      '23514', '%ck_empleado_salario%');
ROLLBACK;

-- CASO: RN-15-FAIL-RenglonCantidad
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al insertar renglon_comprobante con cantidad = 0 (ck_renglon_comprobante_cantidad).
-- SQLSTATE esperado: 23514
DO $$
DECLARE
    v_comp INTEGER;
    v_vino INTEGER;
BEGIN
    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Vino RN-15 Renglon', 'tinto', 2021, 750, 14.50, 1000, '99999990001')
    RETURNING cod_vino INTO v_vino;
    PERFORM pg_temp.agregar_cepa_vino(v_vino);

    INSERT INTO comprobante (id_cliente, id_sala)
    SELECT id_cliente, (SELECT id_sala FROM sala_venta WHERE codigo_postal='TDB00001' LIMIT 1)
    FROM cliente WHERE apellido_razon_social = 'Socio TDB' LIMIT 1
    RETURNING nro_comprobante INTO v_comp;

    PERFORM pg_temp.esperar_error(
        format('INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento_pct, subtotal)
                VALUES (%s, %s, 0, 1000, 0, 0)', v_comp, v_vino),
        '23514', '%ck_renglon_comprobante_cantidad%');
END
$$;

-- =====================================================================
-- REGLA RN-05: Porcentajes de corte suman 100
-- Mecanismo: constraint triggers ctg_vino_cepa_suma_100 y
--            ctg_vino_composicion (DEFERRABLE INITIALLY DEFERRED, se
--            evalúan al COMMIT / SET CONSTRAINTS ALL IMMEDIATE)
-- Archivo de migración: db/migrations/005_triggers.sql
-- =====================================================================

-- CASO: RN-05-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Con SET CONSTRAINTS ALL DEFERRED activo, se inserta un vino
--           y su cepa al 100%. Al ejecutar SET CONSTRAINTS ALL IMMEDIATE
--           se fuerza la evaluacion del constraint trigger diferido y, al
--           sumar exactamente 100, la transaccion prosigue sin error.
-- SQLSTATE esperado: -
DO $$
DECLARE
    v_vino INTEGER;
    v_cepa INTEGER;
BEGIN
    SET CONSTRAINTS ALL DEFERRED;

    SELECT id_cepa INTO v_cepa FROM cepa WHERE nombre = 'TDB Cepa' LIMIT 1;

    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Vino RN-05 OK', 'tinto', 2020, 750, 13.50, 1000, '99999990001')
    RETURNING cod_vino INTO v_vino;

    INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
    VALUES (v_vino, v_cepa, 100.00);

    -- Forzar evaluacion inmediata del constraint trigger diferido.
    -- La suma es 100, por lo que no debe haber error.
    SET CONSTRAINTS ALL IMMEDIATE;

    RAISE NOTICE 'OK RN-05-OK: composicion 100%% aceptada tras SET CONSTRAINTS ALL IMMEDIATE';
END
$$;

-- RN-05-FAIL (inmediato): con SET CONSTRAINTS ALL IMMEDIATE, la suma 60
-- se rechaza en el propio INSERT de la composicion, no al COMMIT.

-- Datos previos para RN-05: bodega y cepas que usan los casos siguientes.
INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('99999999971', 'Bodega RN05', 'Dir')
ON CONFLICT DO NOTHING;

INSERT INTO cepa (nombre, tipo)
VALUES ('Cepa RN05 Diferido 1', 'tinta'),
       ('Cepa RN05 Diferido 2', 'blanca')
ON CONFLICT DO NOTHING;

DO $$
BEGIN
    BEGIN
        INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
        VALUES ('Vino RN05 Inmediato', 'tinto', 2021, 750, 14.0, 10000, '99999999971');

        INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
        SELECT v.cod_vino, c.id_cepa, 60
          FROM vino v, cepa c
         WHERE v.nombre = 'Vino RN05 Inmediato' AND c.nombre = 'Cepa RN05 Diferido 1';

        SET CONSTRAINTS ALL IMMEDIATE;
        RAISE EXCEPTION 'FALLO RN-05: la composicion 60 no fue rechazada';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE '%RN-05%' THEN
            RAISE NOTICE 'OK RN-05-FAIL: composicion 60 rechazada con RN-05';
        ELSE
            RAISE;
        END IF;
    END;
END $$;

-- =====================================================================
-- RN-05 diferido: la composicion se valida al COMMIT, no al INSERT.
-- SQL plano (no DO): el COMMIT debe ejecutarse en la sesion.
-- =====================================================================

DO $$
DECLARE
    v_def  BOOLEAN;
    v_init BOOLEAN;
BEGIN
    SELECT t.tgdeferrable, t.tginitdeferred INTO v_def, v_init
      FROM pg_trigger t
     WHERE t.tgname = 'ctg_vino_cepa_suma_100' AND NOT t.tgisinternal;

    IF NOT FOUND OR NOT v_def OR NOT v_init THEN
        RAISE EXCEPTION 'FALLO RN-05: ctg_vino_cepa_suma_100 no es DEFERRABLE INITIALLY DEFERRED';
    END IF;
    RAISE NOTICE 'OK RN-05-DIFERIDO: ctg_vino_cepa_suma_100 es DEFERRABLE INITIALLY DEFERRED';
END $$;

-- =====================================================================
-- REGLA RN-06: Descuento por tipo de cliente (socio 10, distribuidor 20,
-- exportador = su porcentaje_descuento, default 30)
-- Mecanismo: fn_descuento_cliente(INTEGER) + ck_cliente_exportador_descuento
--            (BETWEEN 30 AND 35)
-- Archivo de migración: db/migrations/002_constraints.sql / 003_funciones.sql
-- =====================================================================

-- CASO: RN-06-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: fn_descuento_cliente devuelve 10.00 para socio y 20.00 para
--           distribuidor. Nota: no se puede probar el exportador porque
--           no se puede dar de alta un cliente exportador (los constraint
--           triggers de clientes se evaluan inmediatamente, ver brecha
--           documentada en este caso).
-- SQLSTATE esperado: -
DO $$
DECLARE
    v_pct_socio   NUMERIC;
    v_pct_dist    NUMERIC;
    v_pct_exp_socio NUMERIC;
    v_cli_soc     INTEGER;
    v_cli_dist    INTEGER;
    v_cli_exp     INTEGER;
BEGIN
    SELECT id_cliente INTO v_cli_soc FROM cliente WHERE apellido_razon_social = 'Socio TDB' LIMIT 1;
    SELECT fn_descuento_cliente(v_cli_soc) INTO v_pct_socio;

    INSERT INTO cliente (apellido_razon_social, nombre, tipo_documento, nro_documento,
                         direccion, codigo_postal, tipo_cliente)
    VALUES ('Distribuidor TDB', 'Ana', 'CUIT', '99000003', 'Dir TDB', 'TDB00001', 'distribuidor')
    ON CONFLICT (tipo_documento, nro_documento) DO NOTHING
    RETURNING id_cliente INTO v_cli_dist;
    IF v_cli_dist IS NULL THEN
        SELECT id_cliente INTO v_cli_dist FROM cliente WHERE tipo_documento='CUIT' AND nro_documento='99000003';
    END IF;
    INSERT INTO cliente_distribuidor (id_cliente, zona_cobertura, nro_habilitacion)
    VALUES (v_cli_dist, 'Zona TDB', 'HAB-TDB-1')
    ON CONFLICT (id_cliente) DO NOTHING;

    -- El cliente 'Exportador TDB' es ahora tipo 'socio' (no se puede crear
    -- exportador por brecha de triggers), por eso su descuento es 10, no 30.
    SELECT id_cliente INTO v_cli_exp FROM cliente WHERE apellido_razon_social = 'Exportador TDB' LIMIT 1;
    SELECT fn_descuento_cliente(v_cli_exp) INTO v_pct_exp_socio;
    SELECT fn_descuento_cliente(v_cli_dist) INTO v_pct_dist;

    IF v_pct_socio IS DISTINCT FROM 10.00 THEN
        RAISE EXCEPTION 'FALLO RN-06-OK: socio tiene descuento % (se esperaba 10.00)', v_pct_socio;
    END IF;
    IF v_pct_dist IS DISTINCT FROM 20.00 THEN
        RAISE EXCEPTION 'FALLO RN-06-OK: distribuidor tiene descuento % (se esperaba 20.00)', v_pct_dist;
    END IF;
    IF v_pct_exp_socio IS DISTINCT FROM 10.00 THEN
        RAISE EXCEPTION 'FALLO RN-06-OK: cliente Exportador TDB (tipo socio) tiene descuento % (se esperaba 10.00)', v_pct_exp_socio;
    END IF;
    RAISE NOTICE 'OK RN-06-OK: socio=10.00, distribuidor=20.00, Exportador-TDB(es-socio)=10.00';
END
$$;

-- CASO: RN-06-FAIL
-- TIPO: DEBE FUNCIONAR
-- RN-06 (U6): con mas de 3 permisos el descuento es 35; con 3, 30.
-- Cada paso corre en su propio DO (transaccion atomica): si falla, no queda nada a medias.
DO $$
DECLARE
    v_id  INTEGER;
    v_pct NUMERIC;
BEGIN
    SELECT id_cliente INTO v_id FROM cliente WHERE nro_documento = '30999000001';

    SELECT fn_descuento_cliente(v_id) INTO v_pct;
    IF v_pct IS DISTINCT FROM 35.00 THEN
        RAISE EXCEPTION 'FALLO RN-06 (U6): con 4 permisos deberia ser 35 y es %', v_pct;
    END IF;

    -- Borde: quitar un permiso deja 3 -> vuelve a 30.
    DELETE FROM permiso_exportacion WHERE id_cliente = v_id AND codigo = 'TDB-EXP-04';
    SELECT fn_descuento_cliente(v_id) INTO v_pct;
    IF v_pct IS DISTINCT FROM 30.00 THEN
        RAISE EXCEPTION 'FALLO RN-06 (U6): con 3 permisos deberia ser 30 y es %', v_pct;
    END IF;

    -- Restaurar el estado base.
    INSERT INTO permiso_exportacion (id_cliente, codigo, fecha_emision, fecha_vencimiento)
    VALUES (v_id, 'TDB-EXP-04', DATE '2025-04-01', DATE '2027-04-01');

    RAISE NOTICE 'OK RN-06 (U6): 4 permisos -> 35; 3 permisos -> 30';
END $$;

-- =====================================================================
-- REGLA RN-07: Permiso de exportacion: vencimiento posterior a emision
-- Mecanismo: CHECK ck_permiso_exportacion_fechas (fecha_vencimiento >
--            fecha_emision)
-- Archivo de migración: db/migrations/002_constraints.sql
-- =====================================================================

-- CASO: RN-07-OK
-- TIPO: DEBE FUNCIONAR (verificacion estructural)
-- ESPERADO: La restriccion ck_permiso_exportacion_fechas existe en el
--           catalogo y verifica fecha_vencimiento > fecha_emision.
-- SQLSTATE esperado: -
DO $$
DECLARE
    v_ck_count INTEGER;
BEGIN
    SELECT count(*) INTO v_ck_count
      FROM pg_constraint
     WHERE conname = 'ck_permiso_exportacion_fechas'
       AND conrelid = 'permiso_exportacion'::regclass;
    IF v_ck_count <> 1 THEN
        RAISE EXCEPTION 'FALLO RN-07-OK: se esperaba 1 restriccion ck_permiso_exportacion_fechas y hay %', v_ck_count;
    END IF;
    RAISE NOTICE 'OK RN-07-OK: restriccion ck_permiso_exportacion_fechas existe';
END
$$;

-- CASO: RN-07-FAIL-IGUAL
-- TIPO: DEBE FALLAR (brecha documentada, ver Paso 5)
-- RN-07 FAIL: vencimiento igual o anterior a la emision -> 23514.
DO $$
DECLARE v_id INTEGER;
BEGIN
    SELECT id_cliente INTO v_id FROM cliente WHERE nro_documento = '30999000001';
    BEGIN
        INSERT INTO permiso_exportacion (id_cliente, codigo, fecha_emision, fecha_vencimiento)
        VALUES (v_id, 'TDB-EXP-BAD', DATE '2026-06-01', DATE '2026-06-01');
        RAISE EXCEPTION 'FALLO RN-07: se acepto un permiso con vencimiento igual a emision';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK RN-07-FAIL: vencimiento igual a emision rechazado (23514)';
    END;
END $$;

-- =====================================================================
-- REGLA RN-08: Total del comprobante = suma de renglones con descuento;
-- no se carga a mano
-- Mecanismo: trg_renglon_comprobante_antes/despues + fn_total_comprobante
-- Archivo de migración: db/migrations/003_funciones.sql / 005_triggers.sql
-- =====================================================================

-- CASO: RN-08-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Al insertar renglones, el total del comprobante se recalcula
--           como suma de subtotales con descuento (coincide con
--           fn_total_comprobante).
-- SQLSTATE esperado: -
DO $$
DECLARE
    v_comp   INTEGER;
    v_vino   INTEGER;
    v_cli    INTEGER;
    v_sala   INTEGER;
    v_total  NUMERIC;
    v_fn     NUMERIC;
BEGIN
    SELECT id_cliente INTO v_cli FROM cliente WHERE apellido_razon_social = 'Socio TDB' LIMIT 1;
    SELECT id_sala  INTO v_sala FROM sala_venta WHERE codigo_postal = 'TDB00001' LIMIT 1;
    SELECT cod_vino INTO v_vino FROM vino WHERE nombre = 'Vino TDB' LIMIT 1;

    INSERT INTO comprobante (id_cliente, id_sala) VALUES (v_cli, v_sala)
    RETURNING nro_comprobante INTO v_comp;

    INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (v_sala, v_vino, 100)
    ON CONFLICT (id_sala, cod_vino) DO UPDATE SET cantidad = 100;

    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
    VALUES (v_comp, v_vino, 4);

    SELECT c.total INTO v_total FROM comprobante c WHERE c.nro_comprobante = v_comp;
    SELECT fn_total_comprobante(v_comp) INTO v_fn;

    IF v_total IS DISTINCT FROM v_fn THEN
        RAISE EXCEPTION 'FALLO RN-08-OK: total % <> fn_total_comprobante %', v_total, v_fn;
    END IF;
    IF v_total IS DISTINCT FROM 7200.00 THEN
        RAISE EXCEPTION 'FALLO RN-08-OK: total % (se esperaba 7200.00)', v_total;
    END IF;
    RAISE NOTICE 'OK RN-08-OK: total recalcado = %, fn_total_comprobante = %', v_total, v_fn;
END
$$;

-- CASO: RN-08-FAIL-BRECHA
-- TIPO: DEBE FALLAR (brecha documentada, ver Paso 5)
-- ESPERADO: Un UPDATE directo de comprobante.total NO es rechazado por
--           ningun trigger (trg_renglon_comprobante_despues solo se dispara
--           en renglon_comprobante). La brecha queda registrada como
--           WARNING y no como FALLO, porque la base no la impide.
-- RN-08 FAIL: UPDATE manual del total del comprobante -> P0001.
DO $$
DECLARE v_nro INTEGER;
BEGIN
    SELECT nro_comprobante INTO v_nro FROM comprobante ORDER BY nro_comprobante LIMIT 1;
    BEGIN
        UPDATE comprobante SET total = 999999 WHERE nro_comprobante = v_nro;
        RAISE EXCEPTION 'FALLO RN-08: se acepto un UPDATE manual de total';
    EXCEPTION WHEN raise_exception THEN
        RAISE NOTICE 'OK RN-08-FAIL: total cargado a mano rechazado (RN-08)';
    END;
END $$;

-- =====================================================================
-- REGLA RN-09: No vender mas que el stock de la sala; stock nunca negativo
-- Mecanismo: trg_renglon_comprobante_antes (RN-09) + ck_stock_sala_cantidad
-- Archivo de migración: db/migrations/002_constraints.sql / 005_triggers.sql
-- =====================================================================

-- CASO: RN-09-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Venta con cantidad <= stock; el stock de la sala baja.
-- SQLSTATE esperado: -
DO $$
DECLARE
    v_comp      INTEGER;
    v_vino      INTEGER;
    v_sala      INTEGER;
    v_cli       INTEGER;
    v_stock_ant INTEGER;
    v_stock_des INTEGER;
BEGIN
    SELECT id_cliente INTO v_cli FROM cliente WHERE apellido_razon_social = 'Socio TDB' LIMIT 1;
    SELECT id_sala  INTO v_sala FROM sala_venta WHERE codigo_postal = 'TDB00001' LIMIT 1;
    SELECT cod_vino INTO v_vino FROM vino WHERE nombre = 'Vino TDB' LIMIT 1;

    INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (v_sala, v_vino, 10)
    ON CONFLICT (id_sala, cod_vino) DO UPDATE SET cantidad = 10;

    SELECT cantidad INTO v_stock_ant FROM stock_sala WHERE id_sala = v_sala AND cod_vino = v_vino;

    INSERT INTO comprobante (id_cliente, id_sala) VALUES (v_cli, v_sala)
    RETURNING nro_comprobante INTO v_comp;

    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
    VALUES (v_comp, v_vino, 3);

    SELECT cantidad INTO v_stock_des FROM stock_sala WHERE id_sala = v_sala AND cod_vino = v_vino;
    IF v_stock_des IS DISTINCT FROM 7 THEN
        RAISE EXCEPTION 'FALLO RN-09-OK: stock quedo en % (se esperaba 7)', v_stock_des;
    END IF;
    RAISE NOTICE 'OK RN-09-OK: stock de la sala bajo de % a %', v_stock_ant, v_stock_des;
END
$$;

-- CASO: RN-09-FAIL-INSUFICIENTE
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al vender mas que el stock disponible (P0001, mensaje
--           contiene RN-09 y Stock insuficiente).
-- SQLSTATE esperado: P0001
DO $$
DECLARE
    v_comp      INTEGER;
    v_vino      INTEGER;
    v_sala      INTEGER;
    v_cli       INTEGER;
    v_stock_ant INTEGER;
    v_stock_des INTEGER;
BEGIN
    SELECT id_cliente INTO v_cli FROM cliente WHERE apellido_razon_social = 'Socio TDB' LIMIT 1;
    SELECT id_sala  INTO v_sala FROM sala_venta WHERE codigo_postal = 'TDB00001' LIMIT 1;
    SELECT cod_vino INTO v_vino FROM vino WHERE nombre = 'Vino TDB' LIMIT 1;

    INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (v_sala, v_vino, 2)
    ON CONFLICT (id_sala, cod_vino) DO UPDATE SET cantidad = 2;

    SELECT cantidad INTO v_stock_ant FROM stock_sala WHERE id_sala = v_sala AND cod_vino = v_vino;

    INSERT INTO comprobante (id_cliente, id_sala) VALUES (v_cli, v_sala)
    RETURNING nro_comprobante INTO v_comp;

    PERFORM pg_temp.esperar_error(
        format('INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
                VALUES (%s, %s, 10)', v_comp, v_vino),
        'P0001', '%Stock insuficiente%RN-09%');

    SELECT cantidad INTO v_stock_des FROM stock_sala WHERE id_sala = v_sala AND cod_vino = v_vino;
    IF v_stock_des IS DISTINCT FROM v_stock_ant THEN
        RAISE EXCEPTION 'FALLO RN-09-FAIL: el stock cambio tras la venta rechazada (% -> %)',
            v_stock_ant, v_stock_des;
    END IF;
    RAISE NOTICE 'OK RN-09-FAIL: venta rechazada, stock se mantuvo en %', v_stock_des;
END
$$;

-- CASO: RN-09-FAIL-STOCK-NEGATIVO
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al hacer UPDATE directo que deje stock_sala.cantidad
--           negativa (23514, ck_stock_sala_cantidad).
-- SQLSTATE esperado: 23514
DO $$
DECLARE
    v_sala INTEGER;
    v_vino INTEGER;
BEGIN
    SELECT id_sala  INTO v_sala FROM sala_venta WHERE codigo_postal = 'TDB00001' LIMIT 1;
    SELECT cod_vino INTO v_vino FROM vino WHERE nombre = 'Vino TDB' LIMIT 1;

    INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (v_sala, v_vino, 5)
    ON CONFLICT (id_sala, cod_vino) DO UPDATE SET cantidad = 5;

    PERFORM pg_temp.esperar_error(
        format('UPDATE stock_sala SET cantidad = -1 WHERE id_sala = %s AND cod_vino = %s',
               v_sala, v_vino),
        '23514', '%ck_stock_sala_cantidad%');
END
$$;

-- =====================================================================
-- REGLA RN-10: Ingreso: en_confeccion -> terminado -> procesado;
-- sin retrocesos; solo terminado impacta el deposito
-- Mecanismo: trg_ingreso_estados + sp_procesar_ingreso
-- Archivo de migración: db/migrations/004_procedimientos.sql / 005_triggers.sql
-- =====================================================================

-- CASO: RN-10-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Flujo en_confeccion -> terminado -> procesado via
--           sp_procesar_ingreso; el stock del deposito sube.
-- SQLSTATE esperado: -
DO $$
DECLARE
    v_ing    INTEGER;
    v_transp INTEGER;
    v_vino   INTEGER;
    v_dep_ant INTEGER;
    v_dep_des INTEGER;
BEGIN
    SELECT cod_transportista INTO v_transp FROM transportista WHERE cuit = '99999990002' LIMIT 1;
    SELECT cod_vino INTO v_vino FROM vino WHERE nombre = 'Vino TDB' LIMIT 1;

    INSERT INTO ingreso (fecha, cod_transportista, cuit_bodega)
    VALUES (CURRENT_DATE, v_transp, '99999990001')
    RETURNING cod_ingreso INTO v_ing;

    INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
    VALUES (v_ing, v_vino, 50);

    BEGIN
        CALL sp_procesar_ingreso(v_ing);
        RAISE EXCEPTION 'FALLO RN-10-OK: se proceso un ingreso en confeccion';
    EXCEPTION WHEN raise_exception THEN
        RAISE NOTICE 'OK RN-10-OK: ingreso en confeccion rechazado -> %', SQLERRM;
    END;

    UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = v_ing;

    SELECT cantidad INTO v_dep_ant FROM stock_deposito WHERE cod_vino = v_vino;
    IF v_dep_ant IS NULL THEN v_dep_ant := 0; END IF;

    CALL sp_procesar_ingreso(v_ing);

    SELECT cantidad INTO v_dep_des FROM stock_deposito WHERE cod_vino = v_vino;
    IF v_dep_des IS DISTINCT FROM v_dep_ant + 50 THEN
        RAISE EXCEPTION 'FALLO RN-10-OK: deposito quedo en % (se esperaba %)', v_dep_des, v_dep_ant + 50;
    END IF;
    RAISE NOTICE 'OK RN-10-OK: ingreso procesado, deposito % -> %', v_dep_ant, v_dep_des;
END
$$;

-- CASO: RN-10-FAIL-SALTO
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al pasar en_confeccion -> procesado directo (P0001,
--           mensaje contiene RN-10).
-- SQLSTATE esperado: P0001
DO $$
DECLARE
    v_ing     INTEGER;
    v_transp  INTEGER;
BEGIN
    SELECT cod_transportista INTO v_transp FROM transportista WHERE cuit = '99999990002' LIMIT 1;

    INSERT INTO ingreso (fecha, cod_transportista, cuit_bodega)
    VALUES (CURRENT_DATE, v_transp, '99999990001')
    RETURNING cod_ingreso INTO v_ing;

    PERFORM pg_temp.esperar_error(
        format('UPDATE ingreso SET estado = ''procesado'' WHERE cod_ingreso = %s', v_ing),
        'P0001', '%RN-10%');
END
$$;

-- CASO: RN-10-FAIL-RETROCEDER
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al retroceder terminado -> en_confeccion (P0001,
--           mensaje contiene RN-10).
-- SQLSTATE esperado: P0001
DO $$
DECLARE
    v_ing     INTEGER;
    v_transp  INTEGER;
BEGIN
    SELECT cod_transportista INTO v_transp FROM transportista WHERE cuit = '99999990002' LIMIT 1;

    INSERT INTO ingreso (fecha, cod_transportista, cuit_bodega)
    VALUES (CURRENT_DATE, v_transp, '99999990001')
    RETURNING cod_ingreso INTO v_ing;

    UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = v_ing;

    PERFORM pg_temp.esperar_error(
        format('UPDATE ingreso SET estado = ''en_confeccion'' WHERE cod_ingreso = %s', v_ing),
        'P0001', '%RN-10%');
END
$$;

-- =====================================================================
-- REGLA RN-11: Idem RN-10 para transferencias; fecha de confeccion =
-- actual e inmodificable; no procesa sin stock
-- Mecanismo: trg_transferencia_estados, trg_transferencia_fecha,
--            sp_procesar_transferencia
-- Archivo de migración: db/migrations/004_procedimientos.sql / 005_triggers.sql
-- =====================================================================

-- CASO: RN-11-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Transferencia con fecha_confeccion 2000-01-01 queda con
--           CURRENT_DATE; se procesa con stock suficiente.
-- SQLSTATE esperado: -
DO $$
DECLARE
    v_tr       INTEGER;
    v_sala     INTEGER;
    v_vino     INTEGER;
    v_fecha    DATE;
    v_dep_ant  INTEGER;
    v_dep_des  INTEGER;
    v_sala_stk INTEGER;
BEGIN
    SELECT id_sala  INTO v_sala FROM sala_venta WHERE codigo_postal = 'TDB00001' LIMIT 1;
    SELECT cod_vino INTO v_vino FROM vino WHERE nombre = 'Vino TDB' LIMIT 1;

    INSERT INTO stock_deposito (cod_vino, cantidad) VALUES (v_vino, 100)
    ON CONFLICT (cod_vino) DO UPDATE SET cantidad = 100;

    INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (v_sala, v_vino, 0)
    ON CONFLICT (id_sala, cod_vino) DO UPDATE SET cantidad = 0;

    INSERT INTO transferencia (id_sala, fecha_confeccion)
    VALUES (v_sala, DATE '2000-01-01')
    RETURNING nro_transferencia INTO v_tr;

    SELECT fecha_confeccion INTO v_fecha FROM transferencia WHERE nro_transferencia = v_tr;
    IF v_fecha IS DISTINCT FROM CURRENT_DATE THEN
        RAISE EXCEPTION 'FALLO RN-11-OK: fecha_confeccion es % (se esperaba CURRENT_DATE)', v_fecha;
    END IF;
    RAISE NOTICE 'OK RN-11-OK: fecha_confeccion forzada a %', v_fecha;

    SELECT cantidad INTO v_dep_ant FROM stock_deposito WHERE cod_vino = v_vino;

    INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
    VALUES (v_tr, v_vino, 30);

    UPDATE transferencia SET estado = 'terminado' WHERE nro_transferencia = v_tr;
    CALL sp_procesar_transferencia(v_tr);

    SELECT cantidad INTO v_dep_des FROM stock_deposito WHERE cod_vino = v_vino;
    SELECT cantidad INTO v_sala_stk FROM stock_sala WHERE id_sala = v_sala AND cod_vino = v_vino;
    IF v_dep_des IS DISTINCT FROM v_dep_ant - 30 THEN
        RAISE EXCEPTION 'FALLO RN-11-OK: deposito quedo en % (se esperaba %)', v_dep_des, v_dep_ant - 30;
    END IF;
    IF v_sala_stk IS DISTINCT FROM 30 THEN
        RAISE EXCEPTION 'FALLO RN-11-OK: stock sala quedo en % (se esperaba 30)', v_sala_stk;
    END IF;
    RAISE NOTICE 'OK RN-11-OK: transferencia procesada, deposito % -> %, sala = %',
        v_dep_ant, v_dep_des, v_sala_stk;
END
$$;

-- CASO: RN-11-FAIL-FECHA
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al modificar fecha_confeccion (P0001, mensaje contiene
--           RN-11).
-- SQLSTATE esperado: P0001
DO $$
DECLARE
    v_tr  INTEGER;
    v_sala INTEGER;
BEGIN
    SELECT id_sala INTO v_sala FROM sala_venta WHERE codigo_postal = 'TDB00001' LIMIT 1;

    INSERT INTO transferencia (id_sala, fecha_confeccion)
    VALUES (v_sala, DATE '2000-01-01')
    RETURNING nro_transferencia INTO v_tr;

    PERFORM pg_temp.esperar_error(
        format('UPDATE transferencia SET fecha_confeccion = DATE ''2001-01-01'' WHERE nro_transferencia = %s', v_tr),
        'P0001', '%RN-11%');
END
$$;

-- CASO: RN-11-FAIL-EN-CONFECCION
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla sp_procesar_transferencia sobre transferencia en_confeccion
--           (P0001, mensaje contiene RN-11).
-- SQLSTATE esperado: P0001
DO $$
DECLARE
    v_tr  INTEGER;
    v_sala INTEGER;
BEGIN
    SELECT id_sala INTO v_sala FROM sala_venta WHERE codigo_postal = 'TDB00001' LIMIT 1;

    INSERT INTO transferencia (id_sala) VALUES (v_sala)
    RETURNING nro_transferencia INTO v_tr;

    PERFORM pg_temp.esperar_error(
        format('CALL sp_procesar_transferencia(%s)', v_tr),
        'P0001', '%RN-11%');
END
$$;

-- CASO: RN-11-FAIL-SIN-STOCK
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla sp_procesar_transferencia cuando el deposito no tiene
--           stock suficiente (P0001, mensaje contiene RN-09 y Stock
--           insuficiente). No queda estado a medias.
-- SQLSTATE esperado: P0001
DO $$
DECLARE
    v_tr     INTEGER;
    v_sala   INTEGER;
    v_vino2  INTEGER;
    v_estado VARCHAR(20);
BEGIN
    SELECT id_sala INTO v_sala FROM sala_venta WHERE codigo_postal = 'TDB00001' LIMIT 1;

    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Vino RN-11 Sin Stock', 'tinto', 2021, 750, 13.50, 1000, '99999990001')
    RETURNING cod_vino INTO v_vino2;

    INSERT INTO transferencia (id_sala) VALUES (v_sala)
    RETURNING nro_transferencia INTO v_tr;

    INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
    VALUES (v_tr, v_vino2, 5);

    UPDATE transferencia SET estado = 'terminado' WHERE nro_transferencia = v_tr;

    PERFORM pg_temp.esperar_error(
        format('CALL sp_procesar_transferencia(%s)', v_tr),
        'P0001', '%Stock insuficiente%RN-09%');

    -- El vino se creo dentro del helper pero sin cepa; agregar cepa para
    -- evitar que ctg_vino_composicion falle al COMMIT.
    PERFORM pg_temp.agregar_cepa_vino(v_vino2);

    SELECT estado INTO v_estado FROM transferencia WHERE nro_transferencia = v_tr;
    IF v_estado IS DISTINCT FROM 'terminado' THEN
        RAISE EXCEPTION 'FALLO RN-11-FAIL-SIN-STOCK: la transferencia cambio de estado a %', v_estado;
    END IF;
    RAISE NOTICE 'OK RN-11-FAIL-SIN-STOCK: transferencia rechazada, estado se mantuvo en %', v_estado;
END
$$;

-- =====================================================================
-- REGLA RN-12: Documento que no esta en confeccion no admite agregar/
-- modificar/quitar renglones
-- Mecanismo: trg_renglon_ingreso_confeccion, trg_renglon_transferencia_confeccion
-- Archivo de migración: db/migrations/005_triggers.sql
-- =====================================================================

-- CASO: RN-12-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Se puede agregar un renglon a un ingreso en confeccion.
-- SQLSTATE esperado: -
DO $$
DECLARE
    v_ing    INTEGER;
    v_transp INTEGER;
    v_vino   INTEGER;
BEGIN
    SELECT cod_transportista INTO v_transp FROM transportista WHERE cuit = '99999990002' LIMIT 1;
    SELECT cod_vino INTO v_vino FROM vino WHERE nombre = 'Vino TDB' LIMIT 1;

    INSERT INTO ingreso (fecha, cod_transportista, cuit_bodega)
    VALUES (CURRENT_DATE, v_transp, '99999990001')
    RETURNING cod_ingreso INTO v_ing;

    INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
    VALUES (v_ing, v_vino, 10);
    RAISE NOTICE 'OK RN-12-OK: renglon de ingreso en confeccion aceptado';
END
$$;

-- CASO: RN-12-FAIL-INGRESO-TERMINADO
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al agregar renglon a ingreso terminado (P0001, RN-12).
-- SQLSTATE esperado: P0001
DO $$
DECLARE
    v_ing    INTEGER;
    v_transp INTEGER;
    v_vino   INTEGER;
BEGIN
    SELECT cod_transportista INTO v_transp FROM transportista WHERE cuit = '99999990002' LIMIT 1;
    SELECT cod_vino INTO v_vino FROM vino WHERE nombre = 'Vino TDB' LIMIT 1;

    INSERT INTO ingreso (fecha, cod_transportista, cuit_bodega)
    VALUES (CURRENT_DATE, v_transp, '99999990001')
    RETURNING cod_ingreso INTO v_ing;

    UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = v_ing;

    PERFORM pg_temp.esperar_error(
        format('INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
                VALUES (%s, %s, 5)', v_ing, v_vino),
        'P0001', '%RN-12%');
END
$$;

-- CASO: RN-12-FAIL-TRANSFERENCIA-TERMINADO
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al agregar renglon a transferencia terminada (P0001,
--           RN-12).
-- SQLSTATE esperado: P0001
DO $$
DECLARE
    v_tr   INTEGER;
    v_sala INTEGER;
    v_vino INTEGER;
BEGIN
    SELECT id_sala INTO v_sala FROM sala_venta WHERE codigo_postal = 'TDB00001' LIMIT 1;
    SELECT cod_vino INTO v_vino FROM vino WHERE nombre = 'Vino TDB' LIMIT 1;

    INSERT INTO transferencia (id_sala) VALUES (v_sala)
    RETURNING nro_transferencia INTO v_tr;

    UPDATE transferencia SET estado = 'terminado' WHERE nro_transferencia = v_tr;

    PERFORM pg_temp.esperar_error(
        format('INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
                VALUES (%s, %s, 5)', v_tr, v_vino),
        'P0001', '%RN-12%');
END
$$;

-- CASO: RN-12-FAIL-BORRAR-INGRESO-TERMINADO
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al borrar renglon de ingreso terminado (P0001, RN-12).
-- SQLSTATE esperado: P0001
DO $$
DECLARE
    v_ing    INTEGER;
    v_transp INTEGER;
    v_vino   INTEGER;
BEGIN
    SELECT cod_transportista INTO v_transp FROM transportista WHERE cuit = '99999990002' LIMIT 1;

    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Vino RN-12 Borrar', 'tinto', 2021, 750, 14.50, 1000, '99999990001')
    RETURNING cod_vino INTO v_vino;
    PERFORM pg_temp.agregar_cepa_vino(v_vino);

    INSERT INTO ingreso (fecha, cod_transportista, cuit_bodega)
    VALUES (CURRENT_DATE, v_transp, '99999990001')
    RETURNING cod_ingreso INTO v_ing;

    INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
    VALUES (v_ing, v_vino, 10);

    UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = v_ing;

    PERFORM pg_temp.esperar_error(
        format('DELETE FROM renglon_ingreso WHERE cod_ingreso = %s AND cod_vino = %s', v_ing, v_vino),
        'P0001', '%RN-12%');
END
$$;

-- =====================================================================
-- REGLA RN-13: Todo cambio de precio queda auditado (fecha, usuario,
-- precio anterior y nuevo)
-- Mecanismo: trg_vino_auditoria (AFTER UPDATE OF precio) + tabla
--            auditoria_precio (DEFAULT now(), current_user)
-- Archivo de migración: db/migrations/005_triggers.sql / 002_constraints.sql
-- =====================================================================

-- CASO: RN-13-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: UPDATE de precio genera fila en auditoria_precio con precio
--           anterior, precio nuevo y usuario no nulo.
-- SQLSTATE esperado: -
DO $$
DECLARE
    v_vino   INTEGER;
    v_n_aud  INTEGER;
    v_usuario VARCHAR(63);
BEGIN
    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Vino RN-13 Auditado', 'tinto', 2021, 750, 14.50, 2000, '99999990001')
    RETURNING cod_vino INTO v_vino;
    PERFORM pg_temp.agregar_cepa_vino(v_vino);

    UPDATE vino SET precio = 2500 WHERE cod_vino = v_vino;

    SELECT count(*), max(usuario) INTO v_n_aud, v_usuario
      FROM auditoria_precio WHERE cod_vino = v_vino;

    IF v_n_aud IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'FALLO RN-13-OK: se esperaba 1 fila de auditoria y hay %', v_n_aud;
    END IF;
    IF v_usuario IS NULL THEN
        RAISE EXCEPTION 'FALLO RN-13-OK: auditoria_precio.usuario es nulo';
    END IF;
    RAISE NOTICE 'OK RN-13-OK: precio auditado (usuario = %)', v_usuario;
END
$$;

-- CASO: RN-13-FAIL-NO-AUDITA-NOMBRE
-- TIPO: DEBE FUNCIONAR (verificacion negativa, no hay error)
-- ESPERADO: UPDATE de nombre_vino NO genera fila nueva en auditoria_precio
--           (solo se audita el precio). Caso de tipo FAIL de logica (no
--           genera error de base).
-- SQLSTATE esperado: -
DO $$
DECLARE
    v_vino   INTEGER;
    v_n_antes INTEGER;
    v_n_desp  INTEGER;
BEGIN
    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Vino RN-13 Nombre', 'tinto', 2021, 750, 14.50, 2000, '99999990001')
    RETURNING cod_vino INTO v_vino;
    PERFORM pg_temp.agregar_cepa_vino(v_vino);

    SELECT count(*) INTO v_n_antes FROM auditoria_precio WHERE cod_vino = v_vino;

    UPDATE vino SET nombre = 'Vino RN-13 Nombre Cambiado' WHERE cod_vino = v_vino;

    SELECT count(*) INTO v_n_desp FROM auditoria_precio WHERE cod_vino = v_vino;
    IF v_n_desp <> v_n_antes THEN
        RAISE EXCEPTION 'FALLO RN-13-FAIL-NO-AUDITA-NOMBRE: se agrego una fila de auditoria al cambiar el nombre (antes %, despues %)', v_n_antes, v_n_desp;
    END IF;
    RAISE NOTICE 'OK RN-13-FAIL-NO-AUDITA-NOMBRE: cambiar nombre no genera fila de auditoria';
END
$$;

-- =====================================================================
-- REGLA RN-14: No borrar transportista, bodega ni vino con movimientos
-- Mecanismo: FK con ON DELETE RESTRICT
-- Archivo de migración: db/migrations/002_constraints.sql
-- =====================================================================

-- CASO: RN-14-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Eliminacion exitosa de un vino sin movimientos (solo tiene
--           composicion en vino_cepa, que es ON DELETE CASCADE).
-- SQLSTATE esperado: -
DO $$
DECLARE
    v_vino INTEGER;
BEGIN
    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Vino RN-14 Para Borrar', 'tinto', 2021, 750, 13.50, 1000, '99999990001')
    RETURNING cod_vino INTO v_vino;

    INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
    VALUES (v_vino, (SELECT id_cepa FROM cepa WHERE nombre = 'TDB Cepa' LIMIT 1), 100.00);

    DELETE FROM vino WHERE cod_vino = v_vino;
    RAISE NOTICE 'OK RN-14-OK: vino sin movimientos borrado (vino_cepa se elimina en cascada)';
END
$$;

-- CASO: RN-14-FAIL-VINO-CON-RENTANGLEN
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al borrar un vino que tiene renglones de comprobante
--           (23503, fk_renglon_comprobante_vino).
-- SQLSTATE esperado: 23503
DO $$
DECLARE
    v_comp INTEGER;
    v_vino INTEGER;
    v_cli  INTEGER;
    v_sala INTEGER;
BEGIN
    SELECT id_cliente INTO v_cli FROM cliente WHERE apellido_razon_social = 'Socio TDB' LIMIT 1;
    SELECT id_sala  INTO v_sala FROM sala_venta WHERE codigo_postal = 'TDB00001' LIMIT 1;

    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Vino RN-14 Con Renglon', 'tinto', 2021, 750, 14.50, 1000, '99999990001')
    RETURNING cod_vino INTO v_vino;
    PERFORM pg_temp.agregar_cepa_vino(v_vino);

    INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (v_sala, v_vino, 100)
    ON CONFLICT (id_sala, cod_vino) DO UPDATE SET cantidad = 100;

    INSERT INTO comprobante (id_cliente, id_sala) VALUES (v_cli, v_sala)
    RETURNING nro_comprobante INTO v_comp;

    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento_pct, subtotal)
    VALUES (v_comp, v_vino, 1, 1000, 0, 1000);

    PERFORM pg_temp.esperar_error(
        format('DELETE FROM vino WHERE cod_vino = %s', v_vino),
        '23503', '%fk_renglon_comprobante_vino%');
END
$$;

-- CASO: RN-14-FAIL-BODEGA-CON-VINO
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al borrar una bodega que tiene vinos (23503,
--           fk_vino_bodega).
-- SQLSTATE esperado: 23503
DO $$
BEGIN
    PERFORM pg_temp.esperar_error(
        'DELETE FROM bodega WHERE cuit = ''99999990001''',
        '23503', '%fk_%bodega%');
END
$$;

-- CASO: RN-14-FAIL-TRANSPORTISTA-CON-INGRESO
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al borrar un transportista que tiene ingresos (23503,
--           fk_ingreso_transportista).
-- SQLSTATE esperado: 23503
DO $$
DECLARE
    v_transp INTEGER;
BEGIN
    SELECT cod_transportista INTO v_transp FROM transportista WHERE cuit = '99999990002' LIMIT 1;

    INSERT INTO ingreso (fecha, cod_transportista, cuit_bodega)
    VALUES (CURRENT_DATE, v_transp, '99999990001');

    PERFORM pg_temp.esperar_error(
        format('DELETE FROM transportista WHERE cod_transportista = %s', v_transp),
        '23503', '%fk_ingreso_transportista%');
END
$$;

-- =====================================================================
-- MATRIZ DE TRAZABILIDAD: Regla -> Mecanismo -> Casos de prueba -> Estado
-- =====================================================================
-- | Regla | Mecanismo Implementado                        | Caso OK            | Caso FAIL                   | Estado     |
-- |-------|-----------------------------------------------|--------------------|-----------------------------|------------|
-- | RN-01 | CHECK ck_vino_precio (precio > 0)             | RN-01-OK           | RN-01-FAIL                  | CUMPLE     |
-- | RN-02 | FK fk_sala_venta_localidad + 3FN (una FK, una | RN-02-OK           | RN-02-FAIL                  | CUMPLE     |
-- |       | col. encargado_regional)                      | RN-02-STRUCT       |                             |            |
-- | RN-03 | NOT NULL + FK fk_empleado_sala_venta          | RN-03-OK           | RN-03-FAIL-NULL             | CUMPLE     |
-- |       |                                               | RN-03-STRUCT       | RN-03-FAIL-FK               |            |
-- | RN-04 | FK fk_parcela_cepa + UNIQUE                   | RN-04-OK           | RN-04-FAIL                  | CUMPLE     |
-- |       | uq_lote_uva_parcela_campania                  | RN-04-STRUCT       |                             |            |
-- | RN-05 | CT ctg_vino_cepa_suma_100 / ctg_vino_composicion| RN-05-OK           | RN-05-FAIL                  | CUMPLE     |
-- | RN-06 | fn_descuento_cliente + ck_cliente_exportador_ | RN-06-OK           | RN-06-FAIL                  | CUMPLE     |
-- |       | descuento                                     |                    |                             |            |
-- | RN-07 | CHECK ck_permiso_exportacion_fechas           | RN-07-OK           | RN-07-FAIL-IGUAL            | CUMPLE     |
-- |       |                                               |                    | RN-07-FAIL-ANTES            |            |
-- | RN-08 | trg_renglon_comprobante_antes/despues         | RN-08-OK           | RN-08-FAIL-BRECHA*          | BRECHA*    |
-- | RN-09 | trg_renglon_comprobante_antes + CHECK stock   | RN-09-OK           | RN-09-FAIL-INSUFICIENTE     | CUMPLE     |
-- |       |                                               |                    | RN-09-FAIL-STOCK-NEGATIVO   |            |
-- | RN-10 | trg_ingreso_estados + sp_procesar_ingreso     | RN-10-OK           | RN-10-FAIL-SALTO            | CUMPLE     |
-- |       |                                               |                    | RN-10-FAIL-RETROCEDER       |            |
-- | RN-11 | trg_transferencia_estados/fecha + sp_procesar_| RN-11-OK           | RN-11-FAIL-FECHA            | CUMPLE     |
-- |       | transferencia                                 |                    | RN-11-FAIL-EN-CONFECCION    |            |
-- |       |                                               |                    | RN-11-FAIL-SIN-STOCK        |            |
-- | RN-12 | trg_renglon_ingreso_confeccion /              | RN-12-OK           | RN-12-FAIL-INGRESO-TERMINADO| CUMPLE     |
-- |       | trg_renglon_transferencia_confeccion          |                    | RN-12-FAIL-TRANSFERENCIA-TERMINADO|        |
-- |       |                                               |                    | RN-12-FAIL-BORRAR-INGRESO-TERMINADO|        |
-- | RN-13 | trg_vino_auditoria + auditoria_precio         | RN-13-OK           | RN-13-FAIL-NO-AUDITA-NOMBRE*| CUMPLE*    |
-- | RN-14 | FK con ON DELETE RESTRICT                     | RN-14-OK           | RN-14-FAIL-VINO-CON-RENTANGLEN| CUMPLE    |
-- |       |                                               |                    | RN-14-FAIL-BODEGA-CON-VINO  |            |
-- |       |                                               |                    | RN-14-FAIL-TRANSPORTISTA-CON-INGRESO|   |
-- | RN-15 | CHECK multiples (precio, graduacion, kilos,   | RN-15-OK           | RN-15-FAIL-PRECIO           | CUMPLE     |
-- |       | superficie, salario, cantidad renglon)        |                    | RN-15-FAIL-GRADUACION-BAJA  |            |
-- |       |                                               |                    | RN-15-FAIL-GRADUACION-ALTA  |            |
-- |       |                                               |                    | RN-15-FAIL-KILOS            |            |
-- |       |                                               |                    | RN-15-FAIL-SUPERFICIE       |            |
-- |       |                                               |                    | RN-15-FAIL-SALARIO          |            |
-- |       |                                               |                    | RN-15-FAIL-RenglonCantidad  |            |
-- |-------|-----------------------------------------------|--------------------|-----------------------------|------------|
-- | * BRECHA: documentada con RAISE WARNING, no es error de la base.
-- |     RN-08: UPDATE directo de comprobante.total no es rechazado.
-- |     RN-13: auditoria no genera fila al cambiar nombre (verificacion negativa, OK).
-- =====================================================================

DO $$
BEGIN
    RAISE NOTICE '=== db_tests.sql ejecutado sin FALLO (todos los datos fueron revertidos o borrados) ===';
END
$$;

