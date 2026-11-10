-- 01_pre_carga.sql – Deshabilitar triggers críticos para carga histórica

-- Deshabilitamos TODOS los triggers de usuario en las tablas donde solo existen triggers que deben desactivarse.
-- Tabla: renglon_comprobante (triggers trg_renglon_comprobante_antes y trg_renglon_comprobante_despues)
ALTER TABLE public.renglon_comprobante DISABLE TRIGGER USER; -- RN-09, RN-06, RN-08

-- Tabla: ingreso (trigger trg_ingreso_estados)
ALTER TABLE public.ingreso DISABLE TRIGGER USER; -- RN-10 (control de estados)

-- Tabla: transferencia (triggers trg_transferencia_estados y trg_transferencia_fecha)
ALTER TABLE public.transferencia DISABLE TRIGGER USER; -- RN-11 y fuerza de fecha

-- Tabla: renglon_ingreso (trigger trg_renglon_ingreso_confeccion)
ALTER TABLE public.renglon_ingreso DISABLE TRIGGER USER; -- RN-12 bloqueo de renglones de ingreso

-- Tabla: renglon_transferencia (trigger trg_renglon_transferencia_confeccion)
ALTER TABLE public.renglon_transferencia DISABLE TRIGGER USER; -- RN-12 bloqueo de renglones de transferencia
