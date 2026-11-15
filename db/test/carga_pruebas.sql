-- =====================================================================
-- db/test/carga_pruebas.sql – Pruebas de carga masiva sin disparar triggers
-- =====================================================================

-- Guarda inicial: aborta si no estamos en bodegas_atuel_bench
SELECT current_database() = 'bodegas_atuel_bench' AS ok \gset
\if :ok
\else
  \echo 'Abortado: no es la base bench'
  \quit
\endif

\set ON_ERROR_STOP off

-- ---------------------------------------------------------------------
-- a) Mostrar contenido de 01_pre_carga.sql sin ejecutarlo
-- ---------------------------------------------------------------------
\echo '===== (a) Contenido de 01_pre_carga.sql ====='
\! cat /tmp/sql/01_pre_carga.sql
\echo '----- fin de 01_pre_carga.sql -----'

-- ---------------------------------------------------------------------
-- b) Negativa realista: 01 + solo 4 de 5 ENABLE + DO de verificación
--    Se espera: 0 triggers en D antes del BEGIN; excepción por 2 triggers
--    deshabilitados; y los 15 triggers en O después del ROLLBACK.
-- ---------------------------------------------------------------------
\echo '===== (b) Prueba negativa: 4 de 5 ENABLE + DO de verificación ====='
\echo '----- Triggers en D antes del BEGIN (debe dar 0) -----'
SELECT COUNT(*) AS triggers_en_d
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
WHERE NOT t.tgisinternal
  AND c.relnamespace = 'public'::regnamespace
  AND t.tgenabled = 'D';

BEGIN;
\i /tmp/sql/01_pre_carga.sql

-- Habilitar solo 4 de las 5 tablas (se omite renglon_comprobante a propósito)
ALTER TABLE public.ingreso ENABLE TRIGGER USER;
ALTER TABLE public.transferencia ENABLE TRIGGER USER;
ALTER TABLE public.renglon_ingreso ENABLE TRIGGER USER;
ALTER TABLE public.renglon_transferencia ENABLE TRIGGER USER;

DO $$
DECLARE
    v_disabled INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_disabled
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    WHERE NOT t.tgisinternal
      AND c.relnamespace = 'public'::regnamespace
      AND t.tgenabled <> 'O';
    IF v_disabled > 0 THEN
        RAISE EXCEPTION 'Quedan % trigger(s) de usuario deshabilitado(s) tras la carga. La transacción se revierte.', v_disabled
            USING ERRCODE = 'check_violation';
    END IF;
END;
$$;

ROLLBACK;

\echo '----- Triggers después del ROLLBACK (deben ser los 15 en O) -----'
SELECT c.relname AS tabla, t.tgname AS trigger, t.tgenabled AS habilitado
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
WHERE NOT t.tgisinternal
  AND c.relnamespace = 'public'::regnamespace
ORDER BY 1, 2;

-- ---------------------------------------------------------------------
-- c) Flujo completo sano: 01 -> carga mínima coherente -> 03 ->
--    SET CONSTRAINTS ALL IMMEDIATE -> 02 y 02b (deben dar 0 filas / sin error)
-- ---------------------------------------------------------------------
\echo '===== (c) Flujo completo con datos mínimos coherentes ====='
BEGIN;
\i /tmp/sql/01_pre_carga.sql

INSERT INTO transportista (cod_transportista, razon_social, cuit, email, telefono, domicilio)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Transportista Test', '20123456782', 'test@trans.com', '2601234567', 'Calle Trans 1');

INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
VALUES ('5500', 'Mendoza', 'Mendoza', 'Encargado Test');

INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('20123456781', 'Bodega Test', 'Calle Falsa 123');

INSERT INTO cepa (id_cepa, nombre, tipo)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Malbec', 'tinta'), (2, 'Cabernet Sauvignon', 'tinta');

INSERT INTO vino (cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Vino Tinto Test', 'tinto', 2020, 750, 13.5, 1000.00, '20123456781'),
       (2, 'Vino Blanco Test', 'blanco', 2021, 750, 11.5, 1200.00, '20123456781');

INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
VALUES (1, 1, 70.00), (1, 2, 30.00),
       (2, 1, 60.00), (2, 2, 40.00);

INSERT INTO sala_venta (id_sala, calle, numero, dia_cierre, codigo_postal)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Calle Test', '123', 'lunes', '5500');

INSERT INTO cliente (id_cliente, apellido_razon_social, nombre, tipo_documento,
                     nro_documento, direccion, codigo_postal, fecha_alta, tipo_cliente)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Pérez', 'Juan', 'DNI', '12345678', 'Calle Cliente 1', '5500',
        '2020-01-01', 'socio');

INSERT INTO stock_deposito (cod_vino, cantidad)
VALUES (1, 300), (2, 200);

INSERT INTO ingreso (cod_ingreso, fecha, estado, cod_transportista, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (1, '2024-01-15', 'procesado', 1, '20123456781');

INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
VALUES (1, 1, 500), (1, 2, 300);

INSERT INTO transferencia (nro_transferencia, id_sala, fecha_confeccion, estado)
OVERRIDING SYSTEM VALUE
VALUES (1, 1, '2024-01-16', 'procesado');

INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
VALUES (1, 1, 200), (1, 2, 100);

INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
VALUES (1, 1, 190), (1, 2, 95);

INSERT INTO comprobante (nro_comprobante, fecha, id_cliente, id_sala, subtotal, descuento, total)
OVERRIDING SYSTEM VALUE
VALUES (1, '2024-01-20', 1, 1, 16000.00, 1600.00, 14400.00);

INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento_pct, subtotal)
VALUES (1, 1, 10, 1000.00, 10.00, 9000.00),
       (1, 2, 5, 1200.00, 10.00, 5400.00);

\i /tmp/sql/03_post_carga.sql
SET CONSTRAINTS ALL IMMEDIATE;

\echo '----- Resultado de 02_controles.sql (debe ser cero filas en todo) -----'
\i /tmp/sql/02_controles.sql

\echo '----- Resultado de 02b_gate.sql (no debe lanzar excepción) -----'
\i /tmp/sql/02b_gate.sql

\echo '----- Flujo completo OK: todos los controles pasaron -----'
ROLLBACK;

-- ---------------------------------------------------------------------
-- d) Prueba negativa: total mal calculado y stock_sala inconsistente
--    Se espera: C5a y C7 devuelven filas; el gate aborta en C5a.
-- ---------------------------------------------------------------------
\echo '===== (d) Prueba negativa: total mal calculado y stock inconsistente ====='
BEGIN;
\i /tmp/sql/01_pre_carga.sql

INSERT INTO transportista (cod_transportista, razon_social, cuit, email, telefono, domicilio)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Transportista Test', '20123456782', 'test@trans.com', '2601234567', 'Calle Trans 1');

INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
VALUES ('5500', 'Mendoza', 'Mendoza', 'Encargado Test');

INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('20123456781', 'Bodega Test', 'Calle Falsa 123');

INSERT INTO cepa (id_cepa, nombre, tipo)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Malbec', 'tinta'), (2, 'Cabernet Sauvignon', 'tinta');

INSERT INTO vino (cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Vino Tinto Test', 'tinto', 2020, 750, 13.5, 1000.00, '20123456781'),
       (2, 'Vino Blanco Test', 'blanco', 2021, 750, 11.5, 1200.00, '20123456781');

INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
VALUES (1, 1, 70.00), (1, 2, 30.00),
       (2, 1, 60.00), (2, 2, 40.00);

INSERT INTO sala_venta (id_sala, calle, numero, dia_cierre, codigo_postal)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Calle Test', '123', 'lunes', '5500');

INSERT INTO cliente (id_cliente, apellido_razon_social, nombre, tipo_documento,
                     nro_documento, direccion, codigo_postal, fecha_alta, tipo_cliente)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Pérez', 'Juan', 'DNI', '12345678', 'Calle Cliente 1', '5500',
        '2020-01-01', 'socio');

INSERT INTO stock_deposito (cod_vino, cantidad)
VALUES (1, 300), (2, 200);

INSERT INTO ingreso (cod_ingreso, fecha, estado, cod_transportista, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (1, '2024-01-15', 'procesado', 1, '20123456781');

INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
VALUES (1, 1, 500), (1, 2, 300);

INSERT INTO transferencia (nro_transferencia, id_sala, fecha_confeccion, estado)
OVERRIDING SYSTEM VALUE
VALUES (1, 1, '2024-01-16', 'procesado');

INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
VALUES (1, 1, 200), (1, 2, 100);

INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
VALUES (1, 1, 999999), (1, 2, 999999);

INSERT INTO comprobante (nro_comprobante, fecha, id_cliente, id_sala, subtotal, descuento, total)
OVERRIDING SYSTEM VALUE
VALUES (1, '2024-01-20', 1, 1, 16000.00, 1600.00, 999999.00);

INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento_pct, subtotal)
VALUES (1, 1, 10, 1000.00, 10.00, 9000.00),
       (1, 2, 5, 1200.00, 10.00, 5400.00);

\i /tmp/sql/03_post_carga.sql
SET CONSTRAINTS ALL IMMEDIATE;

\echo '----- Resultado de 02_controles.sql (C5 y C7 deben devolver filas) -----'
\i /tmp/sql/02_controles.sql

\echo '----- Resultado de 02b_gate.sql (debe abortar en C5a) -----'
\i /tmp/sql/02b_gate.sql

DO $$
BEGIN
    RAISE EXCEPTION 'ERROR: El gate no abortó como se esperaba en (d)';
END;
$$;

ROLLBACK;

-- ---------------------------------------------------------------------
-- i) Composición mal: vino_cepa 60 + 30 = 90
--    Se espera: falla el constraint trigger de composición al ejecutar
--    SET CONSTRAINTS ALL IMMEDIATE.
-- ---------------------------------------------------------------------
\echo '===== (i) Caso nuevo: composición mal (60 + 30) -> debe fallar constraint trigger ====='
BEGIN;
\i /tmp/sql/01_pre_carga.sql

INSERT INTO transportista (cod_transportista, razon_social, cuit, email, telefono, domicilio)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Transportista Test', '20123456782', 'test@trans.com', '2601234567', 'Calle Trans 1');

INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
VALUES ('5500', 'Mendoza', 'Mendoza', 'Encargado Test');

INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('20123456781', 'Bodega Test', 'Calle Falsa 123');

INSERT INTO cepa (id_cepa, nombre, tipo)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Malbec', 'tinta'), (2, 'Cabernet Sauvignon', 'tinta');

INSERT INTO vino (cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Vino Tinto Test', 'tinto', 2020, 750, 13.5, 1000.00, '20123456781'),
       (2, 'Vino Blanco Test', 'blanco', 2021, 750, 11.5, 1200.00, '20123456781');

INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
VALUES (1, 1, 60.00), (1, 2, 30.00),
       (2, 1, 60.00), (2, 2, 40.00);

INSERT INTO sala_venta (id_sala, calle, numero, dia_cierre, codigo_postal)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Calle Test', '123', 'lunes', '5500');

INSERT INTO cliente (id_cliente, apellido_razon_social, nombre, tipo_documento,
                     nro_documento, direccion, codigo_postal, fecha_alta, tipo_cliente)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Pérez', 'Juan', 'DNI', '12345678', 'Calle Cliente 1', '5500',
        '2020-01-01', 'socio');

INSERT INTO stock_deposito (cod_vino, cantidad)
VALUES (1, 300), (2, 200);

INSERT INTO ingreso (cod_ingreso, fecha, estado, cod_transportista, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (1, '2024-01-15', 'procesado', 1, '20123456781');

INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
VALUES (1, 1, 500), (1, 2, 300);

INSERT INTO transferencia (nro_transferencia, id_sala, fecha_confeccion, estado)
OVERRIDING SYSTEM VALUE
VALUES (1, 1, '2024-01-16', 'procesado');

INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
VALUES (1, 1, 200), (1, 2, 100);

INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
VALUES (1, 1, 190), (1, 2, 95);

INSERT INTO comprobante (nro_comprobante, fecha, id_cliente, id_sala, subtotal, descuento, total)
OVERRIDING SYSTEM VALUE
VALUES (1, '2024-01-20', 1, 1, 16000.00, 1600.00, 14400.00);

INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento_pct, subtotal)
VALUES (1, 1, 10, 1000.00, 10.00, 9000.00),
       (1, 2, 5, 1200.00, 10.00, 5400.00);

\i /tmp/sql/03_post_carga.sql
SET CONSTRAINTS ALL IMMEDIATE;

DO $$
BEGIN
    RAISE EXCEPTION 'ERROR: el constraint trigger de composición no falló como se esperaba en (i)';
END;
$$;

ROLLBACK;

-- ---------------------------------------------------------------------
-- ii) Cliente tipo 'distribuidor' sin fila en cliente_distribuidor
--     Se espera: falla ctg_cliente_tipo al ejecutar SET CONSTRAINTS ALL IMMEDIATE.
-- ---------------------------------------------------------------------
\echo '===== (ii) Caso nuevo: distribuidor sin subtipo -> debe fallar ctg_cliente_tipo ====='
BEGIN;
\i /tmp/sql/01_pre_carga.sql

INSERT INTO transportista (cod_transportista, razon_social, cuit, email, telefono, domicilio)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Transportista Test', '20123456782', 'test@trans.com', '2601234567', 'Calle Trans 1');

INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
VALUES ('5500', 'Mendoza', 'Mendoza', 'Encargado Test');

INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('20123456781', 'Bodega Test', 'Calle Falsa 123');

INSERT INTO cepa (id_cepa, nombre, tipo)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Malbec', 'tinta'), (2, 'Cabernet Sauvignon', 'tinta');

INSERT INTO vino (cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Vino Tinto Test', 'tinto', 2020, 750, 13.5, 1000.00, '20123456781'),
       (2, 'Vino Blanco Test', 'blanco', 2021, 750, 11.5, 1200.00, '20123456781');

INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
VALUES (1, 1, 70.00), (1, 2, 30.00),
       (2, 1, 60.00), (2, 2, 40.00);

INSERT INTO sala_venta (id_sala, calle, numero, dia_cierre, codigo_postal)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Calle Test', '123', 'lunes', '5500');

INSERT INTO cliente (id_cliente, apellido_razon_social, nombre, tipo_documento,
                     nro_documento, direccion, codigo_postal, fecha_alta, tipo_cliente)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Pérez', 'Juan', 'DNI', '12345678', 'Calle Cliente 1', '5500',
        '2020-01-01', 'distribuidor');

INSERT INTO stock_deposito (cod_vino, cantidad)
VALUES (1, 300), (2, 200);

INSERT INTO ingreso (cod_ingreso, fecha, estado, cod_transportista, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (1, '2024-01-15', 'procesado', 1, '20123456781');

INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
VALUES (1, 1, 500), (1, 2, 300);

INSERT INTO transferencia (nro_transferencia, id_sala, fecha_confeccion, estado)
OVERRIDING SYSTEM VALUE
VALUES (1, 1, '2024-01-16', 'procesado');

INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
VALUES (1, 1, 200), (1, 2, 100);

INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
VALUES (1, 1, 190), (1, 2, 95);

INSERT INTO comprobante (nro_comprobante, fecha, id_cliente, id_sala, subtotal, descuento, total)
OVERRIDING SYSTEM VALUE
VALUES (1, '2024-01-20', 1, 1, 16000.00, 3200.00, 12800.00);

INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento_pct, subtotal)
VALUES (1, 1, 10, 1000.00, 20.00, 8000.00),
       (1, 2, 5, 1200.00, 20.00, 4800.00);

\i /tmp/sql/03_post_carga.sql
SET CONSTRAINTS ALL IMMEDIATE;

DO $$
BEGIN
    RAISE EXCEPTION 'ERROR: ctg_cliente_tipo no falló como se esperaba en (ii)';
END;
$$;

ROLLBACK;

-- ---------------------------------------------------------------------
-- iii) Stock negativo en el tiempo: comprobante (2024-01-10) anterior a
--      transferencia (2024-01-16), con stock_sala final consistente (190, 95).
--      Se espera: C7 = 0 filas, C9 devuelve filas, gate aborta en C9.
-- ---------------------------------------------------------------------
\echo '===== (iii) Caso nuevo: venta anterior a transferencia -> C7=0, C9 devuelve filas, gate aborta en C9 ====='
BEGIN;
\i /tmp/sql/01_pre_carga.sql

INSERT INTO transportista (cod_transportista, razon_social, cuit, email, telefono, domicilio)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Transportista Test', '20123456782', 'test@trans.com', '2601234567', 'Calle Trans 1');

INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
VALUES ('5500', 'Mendoza', 'Mendoza', 'Encargado Test');

INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('20123456781', 'Bodega Test', 'Calle Falsa 123');

INSERT INTO cepa (id_cepa, nombre, tipo)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Malbec', 'tinta'), (2, 'Cabernet Sauvignon', 'tinta');

INSERT INTO vino (cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Vino Tinto Test', 'tinto', 2020, 750, 13.5, 1000.00, '20123456781'),
       (2, 'Vino Blanco Test', 'blanco', 2021, 750, 11.5, 1200.00, '20123456781');

INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
VALUES (1, 1, 70.00), (1, 2, 30.00),
       (2, 1, 60.00), (2, 2, 40.00);

INSERT INTO sala_venta (id_sala, calle, numero, dia_cierre, codigo_postal)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Calle Test', '123', 'lunes', '5500');

INSERT INTO cliente (id_cliente, apellido_razon_social, nombre, tipo_documento,
                     nro_documento, direccion, codigo_postal, fecha_alta, tipo_cliente)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Pérez', 'Juan', 'DNI', '12345678', 'Calle Cliente 1', '5500',
        '2020-01-01', 'socio');

INSERT INTO stock_deposito (cod_vino, cantidad)
VALUES (1, 300), (2, 200);

INSERT INTO ingreso (cod_ingreso, fecha, estado, cod_transportista, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (1, '2024-01-15', 'procesado', 1, '20123456781');

INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
VALUES (1, 1, 500), (1, 2, 300);

INSERT INTO transferencia (nro_transferencia, id_sala, fecha_confeccion, estado)
OVERRIDING SYSTEM VALUE
VALUES (1, 1, '2024-01-16', 'procesado');

INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
VALUES (1, 1, 200), (1, 2, 100);

INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
VALUES (1, 1, 190), (1, 2, 95);

INSERT INTO comprobante (nro_comprobante, fecha, id_cliente, id_sala, subtotal, descuento, total)
OVERRIDING SYSTEM VALUE
VALUES (1, '2024-01-10', 1, 1, 16000.00, 1600.00, 14400.00);

INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento_pct, subtotal)
VALUES (1, 1, 10, 1000.00, 10.00, 9000.00),
       (1, 2, 5, 1200.00, 10.00, 5400.00);

\i /tmp/sql/03_post_carga.sql
SET CONSTRAINTS ALL IMMEDIATE;

\echo '----- Resultado de 02_controles.sql (C7=0 filas, C9 devuelve filas) -----'
\i /tmp/sql/02_controles.sql

\echo '----- Resultado de 02b_gate.sql (debe abortar en C9) -----'
\i /tmp/sql/02b_gate.sql

DO $$
BEGIN
    RAISE EXCEPTION 'ERROR: El gate no abortó en C9 como se esperaba en (iii)';
END;
$$;

ROLLBACK;

-- ---------------------------------------------------------------------
-- iv) stock_sala inconsistente (999999) con totales correctos
--     Se espera: gate aborta en C7 (no en C5a).
-- ---------------------------------------------------------------------
\echo '===== (iv) Caso nuevo: stock_sala inconsistente y totales sanos -> gate aborta en C7 ====='
BEGIN;
\i /tmp/sql/01_pre_carga.sql

INSERT INTO transportista (cod_transportista, razon_social, cuit, email, telefono, domicilio)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Transportista Test', '20123456782', 'test@trans.com', '2601234567', 'Calle Trans 1');

INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
VALUES ('5500', 'Mendoza', 'Mendoza', 'Encargado Test');

INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('20123456781', 'Bodega Test', 'Calle Falsa 123');

INSERT INTO cepa (id_cepa, nombre, tipo)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Malbec', 'tinta'), (2, 'Cabernet Sauvignon', 'tinta');

INSERT INTO vino (cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Vino Tinto Test', 'tinto', 2020, 750, 13.5, 1000.00, '20123456781'),
       (2, 'Vino Blanco Test', 'blanco', 2021, 750, 11.5, 1200.00, '20123456781');

INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
VALUES (1, 1, 70.00), (1, 2, 30.00),
       (2, 1, 60.00), (2, 2, 40.00);

INSERT INTO sala_venta (id_sala, calle, numero, dia_cierre, codigo_postal)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Calle Test', '123', 'lunes', '5500');

INSERT INTO cliente (id_cliente, apellido_razon_social, nombre, tipo_documento,
                     nro_documento, direccion, codigo_postal, fecha_alta, tipo_cliente)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Pérez', 'Juan', 'DNI', '12345678', 'Calle Cliente 1', '5500',
        '2020-01-01', 'socio');

INSERT INTO stock_deposito (cod_vino, cantidad)
VALUES (1, 300), (2, 200);

INSERT INTO ingreso (cod_ingreso, fecha, estado, cod_transportista, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (1, '2024-01-15', 'procesado', 1, '20123456781');

INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
VALUES (1, 1, 500), (1, 2, 300);

INSERT INTO transferencia (nro_transferencia, id_sala, fecha_confeccion, estado)
OVERRIDING SYSTEM VALUE
VALUES (1, 1, '2024-01-16', 'procesado');

INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
VALUES (1, 1, 200), (1, 2, 100);

INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
VALUES (1, 1, 999999), (1, 2, 999999);

INSERT INTO comprobante (nro_comprobante, fecha, id_cliente, id_sala, subtotal, descuento, total)
OVERRIDING SYSTEM VALUE
VALUES (1, '2024-01-20', 1, 1, 16000.00, 1600.00, 14400.00);

INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento_pct, subtotal)
VALUES (1, 1, 10, 1000.00, 10.00, 9000.00),
       (1, 2, 5, 1200.00, 10.00, 5400.00);

\i /tmp/sql/03_post_carga.sql
SET CONSTRAINTS ALL IMMEDIATE;

\echo '----- Resultado de 02b_gate.sql (debe abortar en C7, no en C5a) -----'
\i /tmp/sql/02b_gate.sql

DO $$
BEGIN
    RAISE EXCEPTION 'ERROR: El gate no abortó en C7 como se esperaba en (iv)';
END;
$$;

ROLLBACK;

-- ---------------------------------------------------------------------
-- v) Descuento mal aplicado: descuento_pct=20 para cliente socio (10%),
--    con subtotales y totales coherentes entre sí (8000 y 5400; total 13400).
--    Se espera: C5 = 0 filas, C6 devuelve el renglón con 20%.
-- ---------------------------------------------------------------------
\echo '===== (v) Caso nuevo: descuento_pct=20 en socio -> C5=0 filas, C6 devuelve fila ====='
BEGIN;
\i /tmp/sql/01_pre_carga.sql

INSERT INTO transportista (cod_transportista, razon_social, cuit, email, telefono, domicilio)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Transportista Test', '20123456782', 'test@trans.com', '2601234567', 'Calle Trans 1');

INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
VALUES ('5500', 'Mendoza', 'Mendoza', 'Encargado Test');

INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('20123456781', 'Bodega Test', 'Calle Falsa 123');

INSERT INTO cepa (id_cepa, nombre, tipo)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Malbec', 'tinta'), (2, 'Cabernet Sauvignon', 'tinta');

INSERT INTO vino (cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Vino Tinto Test', 'tinto', 2020, 750, 13.5, 1000.00, '20123456781'),
       (2, 'Vino Blanco Test', 'blanco', 2021, 750, 11.5, 1200.00, '20123456781');

INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
VALUES (1, 1, 70.00), (1, 2, 30.00),
       (2, 1, 60.00), (2, 2, 40.00);

INSERT INTO sala_venta (id_sala, calle, numero, dia_cierre, codigo_postal)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Calle Test', '123', 'lunes', '5500');

INSERT INTO cliente (id_cliente, apellido_razon_social, nombre, tipo_documento,
                     nro_documento, direccion, codigo_postal, fecha_alta, tipo_cliente)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Pérez', 'Juan', 'DNI', '12345678', 'Calle Cliente 1', '5500',
        '2020-01-01', 'socio');

INSERT INTO stock_deposito (cod_vino, cantidad)
VALUES (1, 300), (2, 200);

INSERT INTO ingreso (cod_ingreso, fecha, estado, cod_transportista, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (1, '2024-01-15', 'procesado', 1, '20123456781');

INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
VALUES (1, 1, 500), (1, 2, 300);

INSERT INTO transferencia (nro_transferencia, id_sala, fecha_confeccion, estado)
OVERRIDING SYSTEM VALUE
VALUES (1, 1, '2024-01-16', 'procesado');

INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
VALUES (1, 1, 200), (1, 2, 100);

INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
VALUES (1, 1, 190), (1, 2, 95);

INSERT INTO comprobante (nro_comprobante, fecha, id_cliente, id_sala, subtotal, descuento, total)
OVERRIDING SYSTEM VALUE
VALUES (1, '2024-01-20', 1, 1, 16000.00, 2600.00, 13400.00);

INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento_pct, subtotal)
VALUES (1, 1, 10, 1000.00, 20.00, 8000.00),
       (1, 2, 5, 1200.00, 10.00, 5400.00);

\i /tmp/sql/03_post_carga.sql
SET CONSTRAINTS ALL IMMEDIATE;

\echo '----- Resultado de 02_controles.sql (C5=0 filas, C6 debe devolver el renglón con 20%) -----'
\i /tmp/sql/02_controles.sql

\echo '----- Resultado de 02b_gate.sql (debe abortar en C6) -----'
\i /tmp/sql/02b_gate.sql

DO $$
BEGIN
    RAISE EXCEPTION 'ERROR: El gate no abortó en C6 como se esperaba en (v)';
END;
$$;

ROLLBACK;

-- Verificar que después de todas las pruebas los 15 triggers siguen en 'O'
\echo '----- Triggers finales (deben ser los 15 en O) -----'
SELECT c.relname AS tabla, t.tgname AS trigger, t.tgenabled AS habilitado
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
WHERE NOT t.tgisinternal
  AND c.relnamespace = 'public'::regnamespace
ORDER BY 1, 2;

-- ---------------------------------------------------------------------
-- b2) Trigger olvidado: 01_pre_carga + vino DISABLE trg_vino_auditoria + 03_post_carga
--    Debe fallar con "Quedan 1 trigger(s)" en el DO de 03_post_carga.sql.
--    Después del ROLLBACK, listado de triggers con los 15 en O.
-- ---------------------------------------------------------------------
\echo '===== (b2) Trigger olvidado: 01 + vino DISABLE trg_vino_auditoria + 03 ====='
BEGIN;
\i /tmp/sql/01_pre_carga.sql
ALTER TABLE vino DISABLE TRIGGER trg_vino_auditoria;
\i /tmp/sql/03_post_carga.sql

ROLLBACK;

-- Verificar que después del ROLLBACK todos los triggers están en 'O'
\echo '----- Triggers después del ROLLBACK (deben ser todos O) ====='
SELECT c.relname AS tabla, t.tgname AS trigger, t.tgenabled AS habilitado
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
WHERE NOT t.tgisinternal
  AND c.relnamespace = 'public'::regnamespace
ORDER BY 1, 2;

-- ---------------------------------------------------------------------
-- c2) Flujo completo con COMMIT: igual que (c) pero COMMIT en vez de ROLLBACK.
--    Después del COMMIT: listado de triggers (15 en O), COUNT de comprobante
--    y renglon_comprobante, y \i /tmp/sql/02b_gate.sql otra vez (debe pasar).
--    Al final, limpieza: TRUNCATE ... RESTART IDENTITY CASCADE y
--    REFRESH MATERIALIZED VIEW public.vw_ventas_mensuales_sala.
-- ---------------------------------------------------------------------
\echo '===== (c2) Flujo completo con COMMIT ====='
BEGIN;
\i /tmp/sql/01_pre_carga.sql

-- Carga mínima de datos maestros (transportista ANTES que ingreso por FK)
INSERT INTO transportista (cod_transportista, razon_social, cuit, email, telefono, domicilio)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Transportista Test', '20123456782', 'test@trans.com', '2601234567', 'Calle Trans 1');

-- localidad
INSERT INTO localidad (codigo_postal, nombre, provincia, encargado_regional)
VALUES ('5500', 'Mendoza', 'Mendoza', 'Encargado Test');

-- bodega
INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('20123456781', 'Bodega Test', 'Calle Falsa 123');

-- cepa (2 cepas)
INSERT INTO cepa (id_cepa, nombre, tipo)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Malbec', 'tinta'), (2, 'Cabernet Sauvignon', 'tinta');

-- 2 vinos con vino_cepa sumando 100 (70% + 30%)
INSERT INTO vino (cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Vino Tinto Test', 'tinto', 2020, 750, 13.5, 1000.00, '20123456781'),
       (2, 'Vino Blanco Test', 'blanco', 2021, 750, 11.5, 1200.00, '20123456781');

INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
VALUES (1, 1, 70.00), (1, 2, 30.00),
       (2, 1, 60.00), (2, 2, 40.00);

-- sala
INSERT INTO sala_venta (id_sala, calle, numero, dia_cierre, codigo_postal)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Calle Test', '123', 'lunes', '5500');

-- cliente (socio -> descuento 10%)
INSERT INTO cliente (id_cliente, apellido_razon_social, nombre, tipo_documento,
                     nro_documento, direccion, codigo_postal, fecha_alta, tipo_cliente)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Pérez', 'Juan', 'DNI', '12345678', 'Calle Cliente 1', '5500',
        '2020-01-01', 'socio');

-- stock_deposito: ingresos (500 vino 1, 300 vino 2) - transferencias (200 vino 1, 100 vino 2)
-- = 300 vino 1, 200 vino 2
INSERT INTO stock_deposito (cod_vino, cantidad)
VALUES (1, 300), (2, 200);

-- ingreso procesado con renglones
INSERT INTO ingreso (cod_ingreso, fecha, estado, cod_transportista, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (1, '2024-01-15', 'procesado', 1, '20123456781');

INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
VALUES (1, 1, 500), (1, 2, 300);

-- transferencia procesada con renglones
INSERT INTO transferencia (nro_transferencia, id_sala, fecha_confeccion, estado)
OVERRIDING SYSTEM VALUE
VALUES (1, 1, '2024-01-16', 'procesado');

INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
VALUES (1, 1, 200), (1, 2, 100);

-- stock_sala: transferencia entra (200, 100), ventas salen (10, 5).
-- Como triggers estaban deshabilitados, stock_sala no se auto-actualizó.
-- Debemos poner el valor correcto: 200-10=190, 100-5=95.
INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
VALUES (1, 1, 190), (1, 2, 95);

-- comprobante con renglones (totales calculados correctamente).
-- socio tiene descuento 10%.
-- Renglon 1: 10 * 1000 * (100-10)/100 = 9000.00
-- Renglon 2: 5 * 1200 * (100-10)/100 = 5400.00
-- subtotal bruto = 10000+6000 = 16000.00
-- total con descuento = 9000+5400 = 14400.00
INSERT INTO comprobante (nro_comprobante, fecha, id_cliente, id_sala, subtotal, descuento, total)
OVERRIDING SYSTEM VALUE
VALUES (1, '2024-01-20', 1, 1, 16000.00, 1600.00, 14400.00);

INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento_pct, subtotal)
VALUES (1, 1, 10, 1000.00, 10.00, 9000.00),
       (1, 2, 5, 1200.00, 10.00, 5400.00);

-- Ejecutar 03_post_carga.sql (habilita triggers, valida, setval, REFRESH MV, ANALYZE)
\i /tmp/sql/03_post_carga.sql

-- Ejecutar 02_controles.sql: debe devolver CERO filas en todas las consultas
\echo '----- Resultado de 02_controles.sql (debe ser cero filas en todo) ====='
SET CONSTRAINTS ALL IMMEDIATE;
\i /tmp/sql/02_controles.sql

-- Ejecutar 02b_gate.sql: no debe lanzar excepción
\echo '----- Resultado de 02b_gate.sql (no debe lanzar excepción) ====='
SET CONSTRAINTS ALL IMMEDIATE;
\i /tmp/sql/02b_gate.sql

\echo '----- Flujo completo OK: todos los controles pasaron ====='
COMMIT;

-- Después del COMMIT: listado de triggers (15 en O)
\echo '----- Triggers después del COMMIT (deben ser todos O) ====='
SELECT c.relname AS tabla, t.tgname AS trigger, t.tgenabled AS habilitado
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
WHERE NOT t.tgisinternal
  AND c.relnamespace = 'public'::regnamespace
ORDER BY 1, 2;

-- Conteos después del COMMIT
\echo '----- Conteos después del COMMIT ====='
SELECT 'comprobante', count(*) FROM comprobante UNION ALL SELECT 'renglon_comprobante', count(*) FROM renglon_comprobante;

-- Ejecutar 02b_gate.sql otra vez (debe pasar)
\echo '----- Ejecutar 02b_gate.sql de nuevo (debe pasar) ====='
\i /tmp/sql/02b_gate.sql

-- Limpieza: TRUNCATE ... RESTART IDENTITY CASCADE
TRUNCATE TABLE renglon_comprobante, comprobante, renglon_transferencia, transferencia,
         renglon_ingreso, ingreso, stock_sala, stock_deposito, vino_lote, vino_cepa,
         vino, sala_venta, cliente, cepa, bodega, localidad, transportista RESTART IDENTITY CASCADE;

REFRESH MATERIALIZED VIEW public.vw_ventas_mensuales_sala;

\echo '----- Conteos después de limpieza (deben ser 0) ====='
SELECT 'comprobante', count(*) FROM comprobante UNION ALL SELECT 'renglon_comprobante', count(*) FROM renglon_comprobante;

-- Limpiar datos de prueba (protegido por la guarda inicial de base de datos)
TRUNCATE TABLE renglon_comprobante, comprobante, renglon_transferencia, transferencia,
         renglon_ingreso, ingreso, stock_sala, stock_deposito, vino_lote, vino_cepa,
         vino, sala_venta, cliente, cepa, bodega, localidad, transportista RESTART IDENTITY CASCADE;

\echo '===== Todas las pruebas de carga_pruebas.sql completadas ====='