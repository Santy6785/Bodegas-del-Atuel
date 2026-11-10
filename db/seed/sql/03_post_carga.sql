-- 03_post_carga.sql – Re-habilitar triggers y validar después de la carga histórica
-- Espejo de 01_pre_carga.sql: vuelve a ENABLE TRIGGER USER en las 5 tablas,
-- valida que ningún trigger de usuario quede deshabilitado, realinea las
-- secuencias IDENTITY, refresca la vista materializada y ejecuta ANALYZE.
-- Diseñado para ejecutarse dentro de la misma transacción que 01_pre_carga y
-- 02_controles.sql (ver docs/carga-triggers.md, sección 2).

-- 1. Re-habilitar triggers de usuario (espejo exacto de 01_pre_carga.sql)
ALTER TABLE public.renglon_comprobante ENABLE TRIGGER USER;   -- RN-09, RN-06, RN-08
ALTER TABLE public.ingreso ENABLE TRIGGER USER;               -- RN-10
ALTER TABLE public.transferencia ENABLE TRIGGER USER;         -- RN-11 + fecha
ALTER TABLE public.renglon_ingreso ENABLE TRIGGER USER;       -- RN-12
ALTER TABLE public.renglon_transferencia ENABLE TRIGGER USER; -- RN-12

-- 2. Validación: ningún trigger de usuario puede quedar deshabilitado
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

-- 3. Realinear secuencias IDENTITY al máximo ID existente de cada tabla
-- (setval(seq, max, true) hace que el próximo nextval sea max+1; si la tabla
-- está vacía, max=0 y el próximo nextval es 1).
SELECT setval(pg_get_serial_sequence('public.sala_venta', 'id_sala'), COALESCE((SELECT MAX(id_sala) FROM public.sala_venta), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('public.departamento', 'id_departamento'), COALESCE((SELECT MAX(id_departamento) FROM public.departamento), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('public.finca', 'id_finca'), COALESCE((SELECT MAX(id_finca) FROM public.finca), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('public.cepa', 'id_cepa'), COALESCE((SELECT MAX(id_cepa) FROM public.cepa), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('public.lote_uva', 'id_lote'), COALESCE((SELECT MAX(id_lote) FROM public.lote_uva), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('public.vino', 'cod_vino'), COALESCE((SELECT MAX(cod_vino) FROM public.vino), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('public.maridaje', 'id_maridaje'), COALESCE((SELECT MAX(id_maridaje) FROM public.maridaje), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('public.cliente', 'id_cliente'), COALESCE((SELECT MAX(id_cliente) FROM public.cliente), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('public.comprobante', 'nro_comprobante'), COALESCE((SELECT MAX(nro_comprobante) FROM public.comprobante), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('public.transportista', 'cod_transportista'), COALESCE((SELECT MAX(cod_transportista) FROM public.transportista), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('public.ingreso', 'cod_ingreso'), COALESCE((SELECT MAX(cod_ingreso) FROM public.ingreso), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('public.transferencia', 'nro_transferencia'), COALESCE((SELECT MAX(nro_transferencia) FROM public.transferencia), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('public.auditoria_precio', 'id_auditoria'), COALESCE((SELECT MAX(id_auditoria) FROM public.auditoria_precio), 0) + 1, false);

-- 4. Refrescar la vista materializada (nombre real definido en 006_vistas.sql)
REFRESH MATERIALIZED VIEW public.vw_ventas_mensuales_sala;

-- 5. Estadísticas del optimizador
ANALYZE;
