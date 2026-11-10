BEGIN;
-- 1. UNIQUE (claves candidatas)
-- Departamento: la clave de negocio es (nombre, provincia) (D1).
ALTER TABLE departamento
    ADD CONSTRAINT uq_departamento_nombre_provincia UNIQUE (nombre, provincia);

-- Cepa: el nombre identifica la variedad.
ALTER TABLE cepa
    ADD CONSTRAINT uq_cepa_nombre UNIQUE (nombre);

-- Lote de uva: numero de lote unico (D2).
ALTER TABLE lote_uva
    ADD CONSTRAINT uq_lote_uva_nro_lote UNIQUE (nro_lote);

-- RN-04: una parcela se cosecha como maximo una vez por campania.
ALTER TABLE lote_uva
    ADD CONSTRAINT uq_lote_uva_parcela_campania UNIQUE (id_finca, nro_parcela, campania);

-- Maridaje: el nombre es unico (D2). Un maridaje se reutiliza en varios vinos.
ALTER TABLE maridaje
    ADD CONSTRAINT uq_maridaje_nombre UNIQUE (nombre);

-- Vino: clave alternativa (nombre comercial, anada, presentacion).
ALTER TABLE vino
    ADD CONSTRAINT uq_vino_nombre_anada_volumen UNIQUE (nombre, anada, volumen_ml);

-- Transportista: un CUIT por empresa de transporte.
ALTER TABLE transportista
    ADD CONSTRAINT uq_transportista_cuit UNIQUE (cuit);

-- Cliente: el mismo numero puede repetirse con distinto tipo de documento.
ALTER TABLE cliente
    ADD CONSTRAINT uq_cliente_documento UNIQUE (tipo_documento, nro_documento);

-- Distribuidor: numero de habilitacion unico.
ALTER TABLE cliente_distribuidor
    ADD CONSTRAINT uq_cliente_distribuidor_habilitacion UNIQUE (nro_habilitacion);

-- 2. CHECK

-- empleado 
-- RN-15: el salario es positivo.
ALTER TABLE empleado
    ADD CONSTRAINT ck_empleado_salario CHECK (salario > 0);

-- finca / parcela / lote_uva
-- RN-15: superficies y kilos positivos.
ALTER TABLE finca
    ADD CONSTRAINT ck_finca_superficie CHECK (superficie_ha > 0);

ALTER TABLE parcela
    ADD CONSTRAINT ck_parcela_superficie CHECK (superficie_ha > 0);

ALTER TABLE lote_uva
    ADD CONSTRAINT ck_lote_uva_kilos CHECK (kilos > 0);

-- vino 
-- RN-01 y RN-15: el precio es siempre mayor que cero.
ALTER TABLE vino
    ADD CONSTRAINT ck_vino_precio CHECK (precio > 0);

-- RN-15: la graduacion alcoholica esta entre 5 y 20.
ALTER TABLE vino
    ADD CONSTRAINT ck_vino_graduacion CHECK (graduacion BETWEEN 5 AND 20);

-- RN-15: el volumen de la presentacion es positivo.
ALTER TABLE vino
    ADD CONSTRAINT ck_vino_volumen CHECK (volumen_ml > 0);

-- ---- vino_cepa -----------------------------------------------------
-- RN-05 (parte por fila): cada porcentaje esta entre 0 (excluido) y 100.
-- La suma exacta de 100 por vino se controla con un constraint trigger
-- diferido en 005_triggers.sql, porque un CHECK ve una sola fila.
ALTER TABLE vino_cepa
    ADD CONSTRAINT ck_vino_cepa_porcentaje CHECK (porcentaje > 0 AND porcentaje <= 100);

-- ---- maridaje ------------------------------------------------------
-- Dominio: temperatura de servicio orientativa, en grados Celsius.
ALTER TABLE maridaje
    ADD CONSTRAINT ck_maridaje_temperatura CHECK (temperatura_servicio BETWEEN 0 AND 30);

-- ---- permiso_exportacion -------------------------------------------
-- RN-07: CHECK ENTRE COLUMNAS. El vencimiento es posterior a la emision.
ALTER TABLE permiso_exportacion
    ADD CONSTRAINT ck_permiso_exportacion_fechas CHECK (fecha_vencimiento > fecha_emision);

-- ---- comprobante / renglon_comprobante ----------------------------
-- Los importes de la cabecera nunca son negativos. Los calcula un trigger (RN-08).
ALTER TABLE comprobante
    ADD CONSTRAINT ck_comprobante_importes
    CHECK (subtotal >= 0 AND descuento >= 0 AND total >= 0);

-- RN-15: cantidades y precios positivos.
ALTER TABLE renglon_comprobante
    ADD CONSTRAINT ck_renglon_comprobante_cantidad CHECK (cantidad > 0);

ALTER TABLE renglon_comprobante
    ADD CONSTRAINT ck_renglon_comprobante_precio CHECK (precio_unitario > 0);

-- RN-06: CHECK de rango. El descuento aplicado es un porcentaje valido.
-- El valor concreto (10/20/30) lo da fn_descuento_cliente (003).
ALTER TABLE renglon_comprobante
    ADD CONSTRAINT ck_renglon_comprobante_descuento CHECK (descuento_pct BETWEEN 0 AND 100);

-- ---- renglones de ingreso y transferencia -------------------------
-- RN-15: cantidades positivas.
ALTER TABLE renglon_ingreso
    ADD CONSTRAINT ck_renglon_ingreso_cantidad CHECK (cantidad > 0);

ALTER TABLE renglon_transferencia
    ADD CONSTRAINT ck_renglon_transferencia_cantidad CHECK (cantidad > 0);

-- ---- stock ---------------------------------------------------------
-- RN-09: el stock nunca es negativo.
ALTER TABLE stock_sala
    ADD CONSTRAINT ck_stock_sala_cantidad CHECK (cantidad >= 0);

ALTER TABLE stock_deposito
    ADD CONSTRAINT ck_stock_deposito_cantidad CHECK (cantidad >= 0);

-- ---- auditoria_precio ----------------------------------------------
-- RN-15: los precios auditados son positivos.
ALTER TABLE auditoria_precio
    ADD CONSTRAINT ck_auditoria_precio_anterior CHECK (precio_anterior > 0);

ALTER TABLE auditoria_precio
    ADD CONSTRAINT ck_auditoria_precio_nuevo CHECK (precio_nuevo > 0);

-- 3. DEFAULT

-- Alta del cliente: fecha actual.
ALTER TABLE cliente
    ALTER COLUMN fecha_alta SET DEFAULT CURRENT_DATE;

-- Estado inicial de los documentos (RN-10, RN-11).
ALTER TABLE ingreso
    ALTER COLUMN estado SET DEFAULT 'en_confeccion';

ALTER TABLE transferencia
    ALTER COLUMN estado SET DEFAULT 'en_confeccion';

-- RN-11: la fecha de confeccion es la actual. Un trigger (005) la fuerza
-- al insertar y prohibe modificarla.
ALTER TABLE transferencia
    ALTER COLUMN fecha_confeccion SET DEFAULT CURRENT_DATE;

-- Stock inicial en cero.
ALTER TABLE stock_sala
    ALTER COLUMN cantidad SET DEFAULT 0;

ALTER TABLE stock_deposito
    ALTER COLUMN cantidad SET DEFAULT 0;

-- Auditoria de precio (RN-13): fecha y usuario los completa la base.
ALTER TABLE auditoria_precio
    ALTER COLUMN fecha_hora SET DEFAULT now();

ALTER TABLE auditoria_precio
    ALTER COLUMN usuario SET DEFAULT current_user;

-- Comprobante: fecha actual.
ALTER TABLE comprobante
    ALTER COLUMN fecha SET DEFAULT CURRENT_DATE;

-- DECISION A CONFIRMAR (api-contrato.md, pregunta 4): la API no puede enviar
-- subtotal, descuento ni total (RN-08). Con DEFAULT 0 la cabecera se crea en
-- cero y el trigger sobre renglon_comprobante la recalcula.
ALTER TABLE comprobante
    ALTER COLUMN subtotal  SET DEFAULT 0,
    ALTER COLUMN descuento SET DEFAULT 0,
    ALTER COLUMN total     SET DEFAULT 0;

-- 4. Acciones referenciales

-- 001_esquema.sql creo las FK con nombre y sin acciones (NO ACTION).
-- Aqui se reemplazan: DROP + ADD en una sola sentencia por FK.
-- RESTRICT se usa en lugar de NO ACTION porque falla de inmediato y no
-- al final de la sentencia.

-- Localidades y salas 
-- El codigo postal puede corregirse: ON UPDATE CASCADE.
ALTER TABLE sala_venta
    DROP CONSTRAINT fk_sala_venta_localidad,
    ADD CONSTRAINT fk_sala_venta_localidad FOREIGN KEY (codigo_postal)
        REFERENCES localidad (codigo_postal) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE empleado
    DROP CONSTRAINT fk_empleado_sala_venta,
    ADD CONSTRAINT fk_empleado_sala_venta FOREIGN KEY (id_sala)
        REFERENCES sala_venta (id_sala) ON DELETE RESTRICT ON UPDATE RESTRICT;

-- Produccion de uva
ALTER TABLE finca
    DROP CONSTRAINT fk_finca_departamento,
    ADD CONSTRAINT fk_finca_departamento FOREIGN KEY (id_departamento)
        REFERENCES departamento (id_departamento) ON DELETE RESTRICT ON UPDATE RESTRICT;

-- Entidad debil: la parcela no existe sin su finca.
ALTER TABLE parcela
    DROP CONSTRAINT fk_parcela_finca,
    ADD CONSTRAINT fk_parcela_finca FOREIGN KEY (id_finca)
        REFERENCES finca (id_finca) ON DELETE CASCADE ON UPDATE RESTRICT;

-- Una cepa plantada no se borra.
ALTER TABLE parcela
    DROP CONSTRAINT fk_parcela_cepa,
    ADD CONSTRAINT fk_parcela_cepa FOREIGN KEY (id_cepa)
        REFERENCES cepa (id_cepa) ON DELETE RESTRICT ON UPDATE RESTRICT;

-- Registro de produccion: preserva la trazabilidad.
ALTER TABLE lote_uva
    DROP CONSTRAINT fk_lote_uva_parcela,
    ADD CONSTRAINT fk_lote_uva_parcela FOREIGN KEY (id_finca, nro_parcela)
        REFERENCES parcela (id_finca, nro_parcela) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE lote_uva
    DROP CONSTRAINT fk_lote_uva_bodega,
    ADD CONSTRAINT fk_lote_uva_bodega FOREIGN KEY (cuit_bodega)
        REFERENCES bodega (cuit) ON DELETE RESTRICT ON UPDATE CASCADE;

-- Entidad debil: el analisis no existe sin su lote.
ALTER TABLE analisis_calidad
    DROP CONSTRAINT fk_analisis_calidad_lote,
    ADD CONSTRAINT fk_analisis_calidad_lote FOREIGN KEY (id_lote)
        REFERENCES lote_uva (id_lote) ON DELETE CASCADE ON UPDATE RESTRICT;

-- Vinos 
-- RN-14: no se borra una bodega con vinos.
ALTER TABLE vino
    DROP CONSTRAINT fk_vino_bodega,
    ADD CONSTRAINT fk_vino_bodega FOREIGN KEY (cuit_bodega)
        REFERENCES bodega (cuit) ON DELETE RESTRICT ON UPDATE CASCADE;

-- La composicion no existe sin el vino; una cepa en uso no se borra.
ALTER TABLE vino_cepa
    DROP CONSTRAINT fk_vino_cepa_vino,
    ADD CONSTRAINT fk_vino_cepa_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE CASCADE ON UPDATE RESTRICT;

ALTER TABLE vino_cepa
    DROP CONSTRAINT fk_vino_cepa_cepa,
    ADD CONSTRAINT fk_vino_cepa_cepa FOREIGN KEY (id_cepa)
        REFERENCES cepa (id_cepa) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE vino_maridaje
    DROP CONSTRAINT fk_vino_maridaje_vino,
    ADD CONSTRAINT fk_vino_maridaje_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE CASCADE ON UPDATE RESTRICT;

ALTER TABLE vino_maridaje
    DROP CONSTRAINT fk_vino_maridaje_maridaje,
    ADD CONSTRAINT fk_vino_maridaje_maridaje FOREIGN KEY (id_maridaje)
        REFERENCES maridaje (id_maridaje) ON DELETE RESTRICT ON UPDATE RESTRICT;

-- Trazabilidad: un lote usado en un vino no se borra.
ALTER TABLE vino_lote
    DROP CONSTRAINT fk_vino_lote_vino,
    ADD CONSTRAINT fk_vino_lote_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE CASCADE ON UPDATE RESTRICT;

ALTER TABLE vino_lote
    DROP CONSTRAINT fk_vino_lote_lote,
    ADD CONSTRAINT fk_vino_lote_lote FOREIGN KEY (id_lote)
        REFERENCES lote_uva (id_lote) ON DELETE RESTRICT ON UPDATE RESTRICT;

-- Clientes (supertipo + subtipos)
ALTER TABLE cliente
    DROP CONSTRAINT fk_cliente_localidad,
    ADD CONSTRAINT fk_cliente_localidad FOREIGN KEY (codigo_postal)
        REFERENCES localidad (codigo_postal) ON DELETE RESTRICT ON UPDATE CASCADE;

-- Un subtipo sin supertipo no tiene sentido.
ALTER TABLE cliente_distribuidor
    DROP CONSTRAINT fk_cliente_distribuidor_cliente,
    ADD CONSTRAINT fk_cliente_distribuidor_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente) ON DELETE CASCADE ON UPDATE RESTRICT;

ALTER TABLE cliente_exportador
    ALTER COLUMN porcentaje_descuento SET DEFAULT 30.00;

ALTER TABLE cliente_exportador
    DROP CONSTRAINT IF EXISTS ck_cliente_exportador_descuento,
    ADD CONSTRAINT ck_cliente_exportador_descuento
    CHECK (porcentaje_descuento IN (30.00, 35.00));

-- Entidad debil de cliente_exportador.
ALTER TABLE permiso_exportacion
    DROP CONSTRAINT fk_permiso_exportacion_exportador,
    ADD CONSTRAINT fk_permiso_exportacion_exportador FOREIGN KEY (id_cliente)
        REFERENCES cliente_exportador (id_cliente) ON DELETE CASCADE ON UPDATE RESTRICT;

-- ---- Ventas ---------------------------------------------------------
-- Protege el historial de ventas.
ALTER TABLE comprobante
    DROP CONSTRAINT fk_comprobante_cliente,
    ADD CONSTRAINT fk_comprobante_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE comprobante
    DROP CONSTRAINT fk_comprobante_sala_venta,
    ADD CONSTRAINT fk_comprobante_sala_venta FOREIGN KEY (id_sala)
        REFERENCES sala_venta (id_sala) ON DELETE RESTRICT ON UPDATE RESTRICT;

-- Renglon sin cabecera no existe. RN-14: no se borra un vino con ventas.
ALTER TABLE renglon_comprobante
    DROP CONSTRAINT fk_renglon_comprobante_comprobante,
    ADD CONSTRAINT fk_renglon_comprobante_comprobante FOREIGN KEY (nro_comprobante)
        REFERENCES comprobante (nro_comprobante) ON DELETE CASCADE ON UPDATE RESTRICT;

ALTER TABLE renglon_comprobante
    DROP CONSTRAINT fk_renglon_comprobante_vino,
    ADD CONSTRAINT fk_renglon_comprobante_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE RESTRICT ON UPDATE CASCADE;

-- ---- Transportistas e ingresos -------------------------------------
ALTER TABLE transportista_localidad
    DROP CONSTRAINT fk_transportista_localidad_transportista,
    ADD CONSTRAINT fk_transportista_localidad_transportista FOREIGN KEY (cod_transportista)
        REFERENCES transportista (cod_transportista) ON DELETE CASCADE ON UPDATE RESTRICT;

ALTER TABLE transportista_localidad
    DROP CONSTRAINT fk_transportista_localidad_localidad,
    ADD CONSTRAINT fk_transportista_localidad_localidad FOREIGN KEY (codigo_postal)
        REFERENCES localidad (codigo_postal) ON DELETE RESTRICT ON UPDATE CASCADE;

-- RN-14: no se borra un transportista ni una bodega con ingresos.
ALTER TABLE ingreso
    DROP CONSTRAINT fk_ingreso_transportista,
    ADD CONSTRAINT fk_ingreso_transportista FOREIGN KEY (cod_transportista)
        REFERENCES transportista (cod_transportista) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE ingreso
    DROP CONSTRAINT fk_ingreso_bodega,
    ADD CONSTRAINT fk_ingreso_bodega FOREIGN KEY (cuit_bodega)
        REFERENCES bodega (cuit) ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE renglon_ingreso
    DROP CONSTRAINT fk_renglon_ingreso_ingreso,
    ADD CONSTRAINT fk_renglon_ingreso_ingreso FOREIGN KEY (cod_ingreso)
        REFERENCES ingreso (cod_ingreso) ON DELETE CASCADE ON UPDATE RESTRICT;

ALTER TABLE renglon_ingreso
    DROP CONSTRAINT fk_renglon_ingreso_vino,
    ADD CONSTRAINT fk_renglon_ingreso_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE RESTRICT ON UPDATE CASCADE;

-- Transferencias y stock
ALTER TABLE transferencia
    DROP CONSTRAINT fk_transferencia_sala_venta,
    ADD CONSTRAINT fk_transferencia_sala_venta FOREIGN KEY (id_sala)
        REFERENCES sala_venta (id_sala) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE renglon_transferencia
    DROP CONSTRAINT fk_renglon_transferencia_transferencia,
    ADD CONSTRAINT fk_renglon_transferencia_transferencia FOREIGN KEY (nro_transferencia)
        REFERENCES transferencia (nro_transferencia) ON DELETE CASCADE ON UPDATE RESTRICT;

ALTER TABLE renglon_transferencia
    DROP CONSTRAINT fk_renglon_transferencia_vino,
    ADD CONSTRAINT fk_renglon_transferencia_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE RESTRICT ON UPDATE CASCADE;

-- Un stock con saldo no se borra en silencio.
ALTER TABLE stock_sala
    DROP CONSTRAINT fk_stock_sala_sala_venta,
    ADD CONSTRAINT fk_stock_sala_sala_venta FOREIGN KEY (id_sala)
        REFERENCES sala_venta (id_sala) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE stock_sala
    DROP CONSTRAINT fk_stock_sala_vino,
    ADD CONSTRAINT fk_stock_sala_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE stock_deposito
    DROP CONSTRAINT fk_stock_deposito_vino,
    ADD CONSTRAINT fk_stock_deposito_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE RESTRICT ON UPDATE RESTRICT;

--  Auditoria 
-- La auditoria es inmutable: no se borra un vino con cambios de precio registrados.
ALTER TABLE auditoria_precio
    DROP CONSTRAINT fk_auditoria_precio_vino,
    ADD CONSTRAINT fk_auditoria_precio_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino) ON DELETE RESTRICT ON UPDATE RESTRICT;

COMMIT;

-- Verificacion (ejecutar a mano despues de aplicar la migracion)
--
-- Restricciones por tipo (u = UNIQUE, c = CHECK, f = FK):
--   SELECT contype, count(*)
--     FROM pg_constraint
--    WHERE connamespace = 'public'::regnamespace AND contype IN ('u','c','f')
--    GROUP BY contype;
--
-- Acciones de cada FK (a = NO ACTION, r = RESTRICT, c = CASCADE):
--   SELECT conrelid::regclass AS tabla, conname,
--          confdeltype AS on_delete, confupdtype AS on_update
--     FROM pg_constraint
--    WHERE contype = 'f' AND connamespace = 'public'::regnamespace
--    ORDER BY 1, 2;
--   -- Ninguna FK debe quedar con 'a'.
--
-- Defaults:
--   SELECT table_name, column_name, column_default
--     FROM information_schema.columns
--    WHERE table_schema = 'public' AND column_default IS NOT NULL
--      AND column_default NOT LIKE 'nextval%'
--    ORDER BY 1, 2;
