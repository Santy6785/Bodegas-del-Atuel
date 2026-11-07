-- =====================================================================
-- 001_esquema.sql
-- Bodegas del Atuel - Esquema físico base
--
-- Contenido:
--   * Tipos ENUM y DOMAIN
--   * Tablas (30), con PRIMARY KEY, FOREIGN KEY y NOT NULL
--
-- Fuera de este archivo (ver 002_constraints.sql):
--   * UNIQUE, CHECK, DEFAULT
--   * Acciones referenciales (ON DELETE / ON UPDATE). Las FK se crean
--     aquí con nombre; 002 las reemplaza con sus acciones.
--
-- Orden de creación: tipos -> tablas sin dependencias -> tablas que
-- dependen de otras. Ejecutar sobre una base vacía.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- Tipos enumerados
-- ---------------------------------------------------------------------
CREATE TYPE tipo_cepa        AS ENUM ('tinta', 'blanca');
CREATE TYPE tipo_vino        AS ENUM ('tinto', 'blanco', 'rosado', 'espumante');
CREATE TYPE dia_semana       AS ENUM ('lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado', 'domingo');
CREATE TYPE tipo_cliente     AS ENUM ('socio', 'distribuidor', 'exportador');
CREATE TYPE tipo_documento   AS ENUM ('DNI', 'CUIT', 'CUIL', 'PASAPORTE');
CREATE TYPE estado_documento AS ENUM ('en_confeccion', 'terminado', 'procesado');

-- ---------------------------------------------------------------------
-- Dominio CUIT: 11 dígitos
-- ---------------------------------------------------------------------
CREATE DOMAIN cuit_dom AS CHAR(11)
    CHECK (VALUE ~ '^[0-9]{11}$');

-- =====================================================================
-- Localidades y salas
-- =====================================================================

CREATE TABLE localidad (
    codigo_postal      VARCHAR(8)   NOT NULL,
    nombre             VARCHAR(100) NOT NULL,
    provincia          VARCHAR(60)  NOT NULL,
    encargado_regional VARCHAR(120) NOT NULL,
    CONSTRAINT pk_localidad PRIMARY KEY (codigo_postal)
);

CREATE TABLE sala_venta (
    id_sala       INTEGER      GENERATED ALWAYS AS IDENTITY,
    calle         VARCHAR(100) NOT NULL,
    numero        VARCHAR(10)  NOT NULL,
    dia_cierre    dia_semana   NOT NULL,
    codigo_postal VARCHAR(8)   NOT NULL,
    CONSTRAINT pk_sala_venta PRIMARY KEY (id_sala),
    CONSTRAINT fk_sala_venta_localidad FOREIGN KEY (codigo_postal)
        REFERENCES localidad (codigo_postal)
);

CREATE TABLE empleado (
    cuit          cuit_dom     NOT NULL,
    nombre        VARCHAR(120) NOT NULL,
    fecha_ingreso DATE         NOT NULL,
    salario       NUMERIC(12,2) NOT NULL,
    id_sala       INTEGER      NOT NULL,
    CONSTRAINT pk_empleado PRIMARY KEY (cuit),
    CONSTRAINT fk_empleado_sala_venta FOREIGN KEY (id_sala)
        REFERENCES sala_venta (id_sala)
);

-- =====================================================================
-- Producción de uva
-- =====================================================================

CREATE TABLE departamento (
    id_departamento INTEGER     GENERATED ALWAYS AS IDENTITY,
    nombre          VARCHAR(60) NOT NULL,
    provincia       VARCHAR(60) NOT NULL,
    CONSTRAINT pk_departamento PRIMARY KEY (id_departamento)
);

CREATE TABLE finca (
    id_finca        INTEGER      GENERATED ALWAYS AS IDENTITY,
    nombre          VARCHAR(100) NOT NULL,
    superficie_ha   NUMERIC(10,2) NOT NULL,
    id_departamento INTEGER      NOT NULL,
    CONSTRAINT pk_finca PRIMARY KEY (id_finca),
    CONSTRAINT fk_finca_departamento FOREIGN KEY (id_departamento)
        REFERENCES departamento (id_departamento)
);

CREATE TABLE cepa (
    id_cepa INTEGER     GENERATED ALWAYS AS IDENTITY,
    nombre  VARCHAR(60) NOT NULL,
    tipo    tipo_cepa   NOT NULL,
    CONSTRAINT pk_cepa PRIMARY KEY (id_cepa)
);

-- Entidad débil de finca: su clave incluye la de finca.
CREATE TABLE parcela (
    id_finca       INTEGER      NOT NULL,
    nro_parcela    INTEGER      NOT NULL,
    superficie_ha  NUMERIC(10,2) NOT NULL,
    anio_plantacion SMALLINT    NOT NULL,
    id_cepa        INTEGER      NOT NULL,
    CONSTRAINT pk_parcela PRIMARY KEY (id_finca, nro_parcela),
    CONSTRAINT fk_parcela_finca FOREIGN KEY (id_finca)
        REFERENCES finca (id_finca),
    CONSTRAINT fk_parcela_cepa FOREIGN KEY (id_cepa)
        REFERENCES cepa (id_cepa)
);

CREATE TABLE bodega (
    cuit        cuit_dom     NOT NULL,
    razon_social VARCHAR(150) NOT NULL,
    domicilio   VARCHAR(200) NOT NULL,
    CONSTRAINT pk_bodega PRIMARY KEY (cuit)
);

CREATE TABLE lote_uva (
    id_lote       INTEGER       GENERATED ALWAYS AS IDENTITY,
    id_finca      INTEGER       NOT NULL,
    nro_parcela   INTEGER       NOT NULL,
    campania      SMALLINT      NOT NULL,
    nro_lote      INTEGER       NOT NULL,
    fecha_cosecha DATE          NOT NULL,
    kilos         NUMERIC(12,2) NOT NULL,
    cuit_bodega   cuit_dom      NOT NULL,
    CONSTRAINT pk_lote_uva PRIMARY KEY (id_lote),
    CONSTRAINT fk_lote_uva_parcela FOREIGN KEY (id_finca, nro_parcela)
        REFERENCES parcela (id_finca, nro_parcela),
    CONSTRAINT fk_lote_uva_bodega FOREIGN KEY (cuit_bodega)
        REFERENCES bodega (cuit)
);

-- Entidad débil de lote_uva: clave (id_lote, fecha, hora).
CREATE TABLE analisis_calidad (
    id_lote      INTEGER      NOT NULL,
    fecha        DATE         NOT NULL,
    hora         TIME         NOT NULL,
    brix         NUMERIC(4,2) NOT NULL,
    ph           NUMERIC(3,2) NOT NULL,
    acidez_total NUMERIC(6,2) NOT NULL,
    CONSTRAINT pk_analisis_calidad PRIMARY KEY (id_lote, fecha, hora),
    CONSTRAINT fk_analisis_calidad_lote FOREIGN KEY (id_lote)
        REFERENCES lote_uva (id_lote)
);

-- =====================================================================
-- Bodegas y vinos
-- =====================================================================

CREATE TABLE vino (
    cod_vino    INTEGER       GENERATED ALWAYS AS IDENTITY,
    nombre      VARCHAR(80)   NOT NULL,
    tipo        tipo_vino     NOT NULL,
    anada       SMALLINT      NOT NULL,
    volumen_ml  INTEGER       NOT NULL,
    graduacion  NUMERIC(4,2)  NOT NULL,
    precio      NUMERIC(10,2) NOT NULL,
    cuit_bodega cuit_dom      NOT NULL,
    CONSTRAINT pk_vino PRIMARY KEY (cod_vino),
    CONSTRAINT fk_vino_bodega FOREIGN KEY (cuit_bodega)
        REFERENCES bodega (cuit)
);

-- N:M vino-cepa con atributo porcentaje (suma 100 por vino: RN-05, trigger).
CREATE TABLE vino_cepa (
    cod_vino   INTEGER      NOT NULL,
    id_cepa    INTEGER      NOT NULL,
    porcentaje NUMERIC(5,2) NOT NULL,
    CONSTRAINT pk_vino_cepa PRIMARY KEY (cod_vino, id_cepa),
    CONSTRAINT fk_vino_cepa_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino),
    CONSTRAINT fk_vino_cepa_cepa FOREIGN KEY (id_cepa)
        REFERENCES cepa (id_cepa)
);

CREATE TABLE maridaje (
    id_maridaje          INTEGER     GENERATED ALWAYS AS IDENTITY,
    nombre               VARCHAR(60) NOT NULL,
    temperatura_servicio SMALLINT    NOT NULL,
    CONSTRAINT pk_maridaje PRIMARY KEY (id_maridaje)
);

-- N:M vino-maridaje sin atributos.
CREATE TABLE vino_maridaje (
    cod_vino    INTEGER NOT NULL,
    id_maridaje INTEGER NOT NULL,
    CONSTRAINT pk_vino_maridaje PRIMARY KEY (cod_vino, id_maridaje),
    CONSTRAINT fk_vino_maridaje_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino),
    CONSTRAINT fk_vino_maridaje_maridaje FOREIGN KEY (id_maridaje)
        REFERENCES maridaje (id_maridaje)
);

-- N:M vino-lote (trazabilidad) sin atributos.
CREATE TABLE vino_lote (
    cod_vino INTEGER NOT NULL,
    id_lote  INTEGER NOT NULL,
    CONSTRAINT pk_vino_lote PRIMARY KEY (cod_vino, id_lote),
    CONSTRAINT fk_vino_lote_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino),
    CONSTRAINT fk_vino_lote_lote FOREIGN KEY (id_lote)
        REFERENCES lote_uva (id_lote)
);

-- =====================================================================
-- Clientes (supertipo + subtipos 1:1)
-- =====================================================================

CREATE TABLE cliente (
    id_cliente           INTEGER      GENERATED ALWAYS AS IDENTITY,
    apellido_razon_social VARCHAR(150) NOT NULL,
    nombre               VARCHAR(100),                 -- NULL si es razón social (ver 002)
    tipo_documento       tipo_documento NOT NULL,
    nro_documento        VARCHAR(11)  NOT NULL,
    direccion            VARCHAR(200) NOT NULL,
    codigo_postal        VARCHAR(8)   NOT NULL,
    fecha_alta           DATE         NOT NULL,
    tipo_cliente         tipo_cliente NOT NULL,
    CONSTRAINT pk_cliente PRIMARY KEY (id_cliente),
    CONSTRAINT fk_cliente_localidad FOREIGN KEY (codigo_postal)
        REFERENCES localidad (codigo_postal)
);

CREATE TABLE cliente_distribuidor (
    id_cliente       INTEGER      NOT NULL,
    zona_cobertura   VARCHAR(120) NOT NULL,
    nro_habilitacion VARCHAR(30)  NOT NULL,
    CONSTRAINT pk_cliente_distribuidor PRIMARY KEY (id_cliente),
    CONSTRAINT fk_cliente_distribuidor_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente)
);



CREATE TABLE cliente_exportador (
    id_cliente           INTEGER      NOT NULL,
    pais_destino         VARCHAR(60)  NOT NULL,
    porcentaje_descuento NUMERIC(5,2) NOT NULL,
    CONSTRAINT pk_cliente_exportador PRIMARY KEY (id_cliente),
    CONSTRAINT fk_cliente_exportador_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente)
);
-- Entidad débil de cliente_exportador. Referencia al subtipo, no al supertipo.
CREATE TABLE permiso_exportacion (
    id_cliente        INTEGER     NOT NULL,
    codigo            VARCHAR(20) NOT NULL,
    fecha_emision     DATE        NOT NULL,
    fecha_vencimiento DATE        NOT NULL,
    CONSTRAINT pk_permiso_exportacion PRIMARY KEY (id_cliente, codigo),
    CONSTRAINT fk_permiso_exportacion_exportador FOREIGN KEY (id_cliente)
        REFERENCES cliente_exportador (id_cliente)
);

-- =====================================================================
-- Ventas
-- =====================================================================

CREATE TABLE comprobante (
    nro_comprobante INTEGER       GENERATED ALWAYS AS IDENTITY,
    fecha           DATE          NOT NULL,
    id_cliente      INTEGER       NOT NULL,
    id_sala         INTEGER       NOT NULL,
    subtotal        NUMERIC(12,2) NOT NULL,
    descuento       NUMERIC(12,2) NOT NULL,
    total           NUMERIC(12,2) NOT NULL,
    CONSTRAINT pk_comprobante PRIMARY KEY (nro_comprobante),
    CONSTRAINT fk_comprobante_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente),
    CONSTRAINT fk_comprobante_sala_venta FOREIGN KEY (id_sala)
        REFERENCES sala_venta (id_sala)
);

-- N:M comprobante-vino con atributos (renglón de comprobante).
CREATE TABLE renglon_comprobante (
    nro_comprobante INTEGER       NOT NULL,
    cod_vino        INTEGER       NOT NULL,
    cantidad        INTEGER       NOT NULL,
    precio_unitario NUMERIC(10,2) NOT NULL,
    descuento_pct   NUMERIC(5,2)  NOT NULL,
    subtotal        NUMERIC(12,2) NOT NULL,
    CONSTRAINT pk_renglon_comprobante PRIMARY KEY (nro_comprobante, cod_vino),
    CONSTRAINT fk_renglon_comprobante_comprobante FOREIGN KEY (nro_comprobante)
        REFERENCES comprobante (nro_comprobante),
    CONSTRAINT fk_renglon_comprobante_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino)
);

-- =====================================================================
-- Transportistas e ingresos
-- =====================================================================

CREATE TABLE transportista (
    cod_transportista INTEGER      GENERATED ALWAYS AS IDENTITY,
    razon_social      VARCHAR(150) NOT NULL,
    cuit              cuit_dom     NOT NULL,
    email             VARCHAR(120) NOT NULL,
    telefono          VARCHAR(30)  NOT NULL,
    domicilio         VARCHAR(200) NOT NULL,
    CONSTRAINT pk_transportista PRIMARY KEY (cod_transportista)
);

-- N:M transportista-localidad (cobertura) sin atributos.
CREATE TABLE transportista_localidad (
    cod_transportista INTEGER     NOT NULL,
    codigo_postal     VARCHAR(8)  NOT NULL,
    CONSTRAINT pk_transportista_localidad PRIMARY KEY (cod_transportista, codigo_postal),
    CONSTRAINT fk_transportista_localidad_transportista FOREIGN KEY (cod_transportista)
        REFERENCES transportista (cod_transportista),
    CONSTRAINT fk_transportista_localidad_localidad FOREIGN KEY (codigo_postal)
        REFERENCES localidad (codigo_postal)
);

CREATE TABLE ingreso (
    cod_ingreso       INTEGER          GENERATED ALWAYS AS IDENTITY,
    fecha             DATE             NOT NULL,
    estado            estado_documento NOT NULL,
    cod_transportista INTEGER          NOT NULL,
    cuit_bodega       cuit_dom         NOT NULL,
    CONSTRAINT pk_ingreso PRIMARY KEY (cod_ingreso),
    CONSTRAINT fk_ingreso_transportista FOREIGN KEY (cod_transportista)
        REFERENCES transportista (cod_transportista),
    CONSTRAINT fk_ingreso_bodega FOREIGN KEY (cuit_bodega)
        REFERENCES bodega (cuit)
);

-- N:M ingreso-vino con atributo cantidad.
CREATE TABLE renglon_ingreso (
    cod_ingreso INTEGER NOT NULL,
    cod_vino    INTEGER NOT NULL,
    cantidad    INTEGER NOT NULL,
    CONSTRAINT pk_renglon_ingreso PRIMARY KEY (cod_ingreso, cod_vino),
    CONSTRAINT fk_renglon_ingreso_ingreso FOREIGN KEY (cod_ingreso)
        REFERENCES ingreso (cod_ingreso),
    CONSTRAINT fk_renglon_ingreso_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino)
);

-- =====================================================================
-- Transferencias y stock
-- =====================================================================

CREATE TABLE transferencia (
    nro_transferencia INTEGER          GENERATED ALWAYS AS IDENTITY,
    id_sala           INTEGER          NOT NULL,
    fecha_confeccion  DATE             NOT NULL,
    estado            estado_documento NOT NULL,
    CONSTRAINT pk_transferencia PRIMARY KEY (nro_transferencia),
    CONSTRAINT fk_transferencia_sala_venta FOREIGN KEY (id_sala)
        REFERENCES sala_venta (id_sala)
);

-- N:M transferencia-vino con atributo cantidad.
CREATE TABLE renglon_transferencia (
    nro_transferencia INTEGER NOT NULL,
    cod_vino          INTEGER NOT NULL,
    cantidad          INTEGER NOT NULL,
    CONSTRAINT pk_renglon_transferencia PRIMARY KEY (nro_transferencia, cod_vino),
    CONSTRAINT fk_renglon_transferencia_transferencia FOREIGN KEY (nro_transferencia)
        REFERENCES transferencia (nro_transferencia),
    CONSTRAINT fk_renglon_transferencia_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino)
);

-- N:M sala-vino con atributo cantidad (stock de sala).
CREATE TABLE stock_sala (
    id_sala  INTEGER NOT NULL,
    cod_vino INTEGER NOT NULL,
    cantidad INTEGER NOT NULL,
    CONSTRAINT pk_stock_sala PRIMARY KEY (id_sala, cod_vino),
    CONSTRAINT fk_stock_sala_sala_venta FOREIGN KEY (id_sala)
        REFERENCES sala_venta (id_sala),
    CONSTRAINT fk_stock_sala_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino)
);

-- Stock del depósito central (instancia única: sin tabla deposito, ver D4).
CREATE TABLE stock_deposito (
    cod_vino INTEGER NOT NULL,
    cantidad INTEGER NOT NULL,
    CONSTRAINT pk_stock_deposito PRIMARY KEY (cod_vino),
    CONSTRAINT fk_stock_deposito_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino)
);

-- =====================================================================
-- Auditoría
-- =====================================================================

CREATE TABLE auditoria_precio (
    id_auditoria    INTEGER       GENERATED ALWAYS AS IDENTITY,
    cod_vino        INTEGER       NOT NULL,
    precio_anterior NUMERIC(10,2) NOT NULL,
    precio_nuevo    NUMERIC(10,2) NOT NULL,
    fecha_hora      TIMESTAMP     NOT NULL,
    usuario         VARCHAR(63)   NOT NULL,
    CONSTRAINT pk_auditoria_precio PRIMARY KEY (id_auditoria),
    CONSTRAINT fk_auditoria_precio_vino FOREIGN KEY (cod_vino)
        REFERENCES vino (cod_vino)
);

COMMIT;