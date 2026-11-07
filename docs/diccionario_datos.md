# Diccionario de datos: Bodegas del Atuel

Diccionario de las 30 tablas del modelo relacional. Los tipos, nulos, claves primarias (PK) y claves foráneas (FK) se generaron desde `db/migrations/001_esquema.sql`, así que coinciden con el esquema creado. Las restricciones marcadas como `*002:*` todavía no existen en la base: se agregan en `002_constraints.sql`.

## Convenciones

- **Nulo:** `NO` = `NOT NULL`; `SÍ` = admite NULL. Hoy sólo `cliente.nombre` admite NULL (razón social, no aplicable).
- **Restricción:** `PK` clave primaria; `FK → tabla.columna` clave foránea; `*002:*` restricción pendiente.
- **Tipo `cuit_dom`:** dominio CHAR(11) con 11 dígitos.
- **Tipos enumerados:** `tipo_cepa`, `tipo_vino`, `dia_semana`, `tipo_cliente`, `tipo_documento`, `estado_documento`.
- **(identity):** columna autoincremental (`GENERATED ALWAYS AS IDENTITY`).
- **Importes:** `NUMERIC`, nunca `FLOAT`. Precios y montos en pesos.

## localidad

Localidad donde se ubican las salas y residen los clientes. Cada una tiene un único encargado regional.

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| codigo_postal | VARCHAR(8) | NO | PK | Código postal argentino (alfanumérico, ej. M5600). Clave natural. |
| nombre | VARCHAR(100) | NO | — | Nombre de la localidad. |
| provincia | VARCHAR(60) | NO | — | Provincia a la que pertenece la localidad. |
| encargado_regional | VARCHAR(120) | NO | — | Encargado comercial regional. Único por localidad (RN-02). |

## sala_venta

Sala de venta física. Pertenece a una localidad y es el punto de venta de comprobantes y transferencias.

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| id_sala | INTEGER (identity) | NO | PK | Identificador de la sala de venta. |
| calle | VARCHAR(100) | NO | — | Calle de la dirección de la sala. |
| numero | VARCHAR(10) | NO | — | Número de la dirección. Texto, para admitir valores como S/N. |
| dia_cierre | dia_semana | NO | — | Día de cierre semanal de la sala. |
| codigo_postal | VARCHAR(8) | NO | FK → localidad.codigo_postal | Localidad donde está ubicada la sala (RN-02). |

## empleado

Empleado que trabaja en una única sala.

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| cuit | cuit_dom | NO | PK | CUIT del empleado. Clave natural. |
| nombre | VARCHAR(120) | NO | — | Nombre completo del empleado. |
| fecha_ingreso | DATE | NO | — | Fecha de ingreso laboral. Base para calcular la antigüedad. |
| salario | NUMERIC(12,2) | NO | *002:* CHECK > 0 (RN-15) | Salario del empleado. |
| id_sala | INTEGER | NO | FK → sala_venta.id_sala | Sala donde trabaja el empleado. Una sola (RN-03). |

## departamento

Departamento y provincia donde se ubica una finca (catálogo).

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| id_departamento | INTEGER (identity) | NO | PK | Identificador subrogado del departamento. |
| nombre | VARCHAR(60) | NO | — | Nombre del departamento. |
| provincia | VARCHAR(60) | NO | — | Provincia del departamento. |

**Restricciones de tabla pendientes (002):** UNIQUE (nombre, provincia).

## finca

Finca productora de uva. Se ubica en un departamento y se divide en parcelas.

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| id_finca | INTEGER (identity) | NO | PK | Identificador de la finca. |
| nombre | VARCHAR(100) | NO | — | Nombre de la finca. |
| superficie_ha | NUMERIC(10,2) | NO | *002:* CHECK > 0 (RN-15) | Superficie total de la finca, en hectáreas. |
| id_departamento | INTEGER | NO | FK → departamento.id_departamento | Departamento donde se ubica la finca. |

## cepa

Variedad de uva (catálogo) con su tipo, tinta o blanca.

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| id_cepa | INTEGER (identity) | NO | PK | Identificador de la cepa. |
| nombre | VARCHAR(60) | NO | *002:* UNIQUE | Nombre de la cepa (ej. Malbec, Cabernet Sauvignon). |
| tipo | tipo_cepa | NO | — | Tipo de uva: tinta o blanca. |

## parcela

Parcela de una finca (entidad débil). Tiene una sola cepa plantada.

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| id_finca | INTEGER | NO | PK; FK → finca.id_finca | Finca a la que pertenece la parcela. Parte de la clave. |
| nro_parcela | INTEGER | NO | PK | Número de la parcela dentro de la finca. Parte de la clave. |
| superficie_ha | NUMERIC(10,2) | NO | *002:* CHECK > 0 (RN-15) | Superficie de la parcela, en hectáreas. |
| anio_plantacion | SMALLINT | NO | — | Año de plantación de la parcela. |
| id_cepa | INTEGER | NO | FK → cepa.id_cepa | Cepa plantada en la parcela. Una sola por parcela. |

## bodega

Bodega del grupo que elabora vinos y recibe lotes de uva.

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| cuit | cuit_dom | NO | PK | CUIT de la bodega. Clave natural. |
| razon_social | VARCHAR(150) | NO | — | Razón social de la bodega. |
| domicilio | VARCHAR(200) | NO | — | Domicilio de la bodega. |

## lote_uva

Lote de uva cosechado de una parcela en una campaña y entregado a una bodega.

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| id_lote | INTEGER (identity) | NO | PK | Identificador subrogado del lote de uva. |
| id_finca | INTEGER | NO | FK → parcela(id_finca, nro_parcela) | Finca de la parcela cosechada. Forma parte de la FK compuesta a parcela. |
| nro_parcela | INTEGER | NO | FK → parcela(id_finca, nro_parcela) | Parcela cosechada. Forma parte de la FK compuesta a parcela. |
| campania | SMALLINT | NO | — | Año de cosecha (campaña). |
| nro_lote | INTEGER | NO | *002:* UNIQUE | Número de lote asignado por la empresa. |
| fecha_cosecha | DATE | NO | — | Fecha de cosecha. |
| kilos | NUMERIC(12,2) | NO | *002:* CHECK > 0 (RN-15) | Kilos de uva cosechados. |
| cuit_bodega | cuit_dom | NO | FK → bodega.cuit | Bodega a la que se entregó el lote. |

**Restricciones de tabla pendientes (002):** UNIQUE (id_finca, nro_parcela, campania) (RN-04).

## analisis_calidad

Análisis de calidad practicado a un lote (entidad débil de lote_uva).

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| id_lote | INTEGER | NO | PK; FK → lote_uva.id_lote | Lote analizado. Parte de la clave (entidad débil). |
| fecha | DATE | NO | PK | Fecha del análisis. Parte de la clave. |
| hora | TIME | NO | PK | Hora del análisis. Parte de la clave. |
| brix | NUMERIC(4,2) | NO | — | Grado Brix de la uva (azúcar). |
| ph | NUMERIC(3,2) | NO | — | pH de la uva. |
| acidez_total | NUMERIC(6,2) | NO | — | Acidez total, en g/L. |

## vino

Vino comercial. Su precio de venta es único para toda la red.

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| cod_vino | INTEGER (identity) | NO | PK | Código del vino. Clave subrogada. |
| nombre | VARCHAR(80) | NO | — | Nombre comercial del vino. |
| tipo | tipo_vino | NO | — | Tipo de vino: tinto, blanco, rosado o espumante. |
| anada | SMALLINT | NO | — | Año de la añada del vino. |
| volumen_ml | INTEGER | NO | *002:* CHECK > 0 (RN-15) | Volumen de la botella, en ml (ej. 187, 375, 750, 1500, 3000). |
| graduacion | NUMERIC(4,2) | NO | *002:* CHECK BETWEEN 5 AND 20 (RN-15) | Graduación alcohólica, en % vol. Entre 5 y 20 (RN-15). |
| precio | NUMERIC(10,2) | NO | *002:* CHECK > 0 (RN-01, RN-15) | Precio de venta, único para toda la red (RN-01). |
| cuit_bodega | cuit_dom | NO | FK → bodega.cuit | Bodega que elabora el vino. |

**Restricciones de tabla pendientes (002):** UNIQUE (nombre, anada, volumen_ml).

## vino_cepa

Composición del vino: cepas que lo integran y su porcentaje de corte.

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| cod_vino | INTEGER | NO | PK; FK → vino.cod_vino | Vino compuesto. Parte de la clave. |
| id_cepa | INTEGER | NO | PK; FK → cepa.id_cepa | Cepa que integra el vino. Parte de la clave. |
| porcentaje | NUMERIC(5,2) | NO | *002:* CHECK > 0 AND <= 100 (RN-05) | Porcentaje de la cepa en el corte del vino. La suma por vino es 100 (RN-05). |

**Restricciones de tabla pendientes (002):** Trigger diferido: suma de porcentaje = 100 por vino (RN-05).

## maridaje

Maridaje recomendado (catálogo) con su temperatura de servicio.

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| id_maridaje | INTEGER (identity) | NO | PK | Identificador del maridaje. |
| nombre | VARCHAR(60) | NO | *002:* UNIQUE | Nombre del maridaje (ej. carnes rojas). |
| temperatura_servicio | SMALLINT | NO | *002:* CHECK BETWEEN 0 AND 30 (orientativo) | Temperatura de servicio sugerida, en °C. |

## vino_maridaje

Maridajes recomendados para cada vino.

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| cod_vino | INTEGER | NO | PK; FK → vino.cod_vino | Vino al que se recomienda el maridaje. Parte de la clave. |
| id_maridaje | INTEGER | NO | PK; FK → maridaje.id_maridaje | Maridaje recomendado. Parte de la clave. |

## vino_lote

Trazabilidad: lotes de uva utilizados en cada vino.

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| cod_vino | INTEGER | NO | PK; FK → vino.cod_vino | Vino elaborado con el lote. Parte de la clave. |
| id_lote | INTEGER | NO | PK; FK → lote_uva.id_lote | Lote de uva utilizado en el vino. Parte de la clave. |

**Restricciones de tabla pendientes (002):** Trigger: el lote fue entregado a la bodega que elabora el vino.

## cliente

Cliente (superclase): socio, distribuidor o exportador.

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| id_cliente | INTEGER (identity) | NO | PK | Identificador del cliente. |
| apellido_razon_social | VARCHAR(150) | NO | — | Apellido de la persona, o razón social de la empresa. |
| nombre | VARCHAR(100) | SÍ | — | Nombre de la persona. NULL si el cliente es razón social (no aplicable). |
| tipo_documento | tipo_documento | NO | — | Tipo de documento del cliente. |
| nro_documento | VARCHAR(11) | NO | — | Número de documento del cliente. |
| direccion | VARCHAR(200) | NO | — | Domicilio del cliente. |
| codigo_postal | VARCHAR(8) | NO | FK → localidad.codigo_postal | Localidad de residencia del cliente. |
| fecha_alta | DATE | NO | *002:* DEFAULT CURRENT_DATE | Fecha de alta del cliente. |
| tipo_cliente | tipo_cliente | NO | — | Subtipo del cliente: socio, distribuidor o exportador. Discriminador de la especialización. |

**Restricciones de tabla pendientes (002):** Trigger: nombre NULL solo si es razón social.

## cliente_distribuidor

Datos propios de un cliente distribuidor (subtipo 1:1 de cliente).

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| id_cliente | INTEGER | NO | PK; FK → cliente.id_cliente | Cliente distribuidor. Clave y FK a cliente. |
| zona_cobertura | VARCHAR(120) | NO | — | Zona de cobertura del distribuidor. |
| nro_habilitacion | VARCHAR(30) | NO | *002:* UNIQUE | Número de habilitación del distribuidor. |

**Restricciones de tabla pendientes (002):** Trigger de coherencia con tipo_cliente.

## cliente_exportador

Datos propios de un cliente exportador (subtipo 1:1 de cliente).

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| id_cliente | INTEGER | NO | PK; FK → cliente.id_cliente | Cliente exportador. Clave y FK a cliente. |
| pais_destino | VARCHAR(60) | NO | — | País de destino principal de las exportaciones. |
| porcentaje_descuento | NUMERIC(5,2) | NO | *002:* DEFAULT 30.00; CHECK (0..100) | Porcentaje de descuento asignado (RN-06 base 30 %, modificable a 35 % por U6). |

**Restricciones de tabla pendientes (002):** CHECK (porcentaje_descuento BETWEEN 0 AND 100); trigger de coherencia con tipo_cliente.

## permiso_exportacion

Permiso de exportación de un exportador (entidad débil).

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| id_cliente | INTEGER | NO | PK; FK → cliente_exportador.id_cliente | Exportador titular del permiso. Parte de la clave. |
| codigo | VARCHAR(20) | NO | PK | Código del permiso de exportación. Parte de la clave. |
| fecha_emision | DATE | NO | — | Fecha de emisión del permiso. |
| fecha_vencimiento | DATE | NO | — | Fecha de vencimiento. Posterior a la emisión (RN-07). |

**Restricciones de tabla pendientes (002):** CHECK fecha_vencimiento > fecha_emision (RN-07).

## comprobante

Documento de venta emitido en una sala a un cliente.

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| nro_comprobante | INTEGER (identity) | NO | PK | Número del comprobante. Clave subrogada. |
| fecha | DATE | NO | — | Fecha de la venta. |
| id_cliente | INTEGER | NO | FK → cliente.id_cliente | Cliente comprador. |
| id_sala | INTEGER | NO | FK → sala_venta.id_sala | Sala donde se realizó la venta. |
| subtotal | NUMERIC(12,2) | NO | — | Suma de los subtotales de los renglones, antes del descuento. Lo calcula el trigger (RN-08). |
| descuento | NUMERIC(12,2) | NO | — | Suma de los descuentos de los renglones. Lo calcula el trigger (RN-08). |
| total | NUMERIC(12,2) | NO | — | Subtotal menos descuento. Lo calcula el trigger (RN-08). |

## renglon_comprobante

Renglón de un comprobante: vino vendido, cantidad y precios aplicados.

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| nro_comprobante | INTEGER | NO | PK; FK → comprobante.nro_comprobante | Comprobante al que pertenece el renglón. Parte de la clave. |
| cod_vino | INTEGER | NO | PK; FK → vino.cod_vino | Vino vendido. Parte de la clave. |
| cantidad | INTEGER | NO | *002:* CHECK > 0 (RN-15) | Botellas vendidas. |
| precio_unitario | NUMERIC(10,2) | NO | *002:* CHECK > 0 (RN-15) | Precio del vino al momento de la venta (snapshot). |
| descuento_pct | NUMERIC(5,2) | NO | — | Porcentaje de descuento según el tipo de cliente, al momento de la venta (snapshot, RN-06). |
| subtotal | NUMERIC(12,2) | NO | — | cantidad × precio_unitario × (1 − descuento_pct/100). Lo calcula el trigger (RN-08). |

## transportista

Empresa de transporte que traslada los ingresos al depósito.

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| cod_transportista | INTEGER (identity) | NO | PK | Identificador del transportista. |
| razon_social | VARCHAR(150) | NO | — | Razón social de la empresa de transporte. |
| cuit | cuit_dom | NO | *002:* UNIQUE | CUIT del transportista. |
| email | VARCHAR(120) | NO | — | Correo electrónico de contacto. |
| telefono | VARCHAR(30) | NO | — | Teléfono de contacto. |
| domicilio | VARCHAR(200) | NO | — | Domicilio del transportista. |

## transportista_localidad

Localidades que cubre cada transportista.

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| cod_transportista | INTEGER | NO | PK; FK → transportista.cod_transportista | Transportista. Parte de la clave. |
| codigo_postal | VARCHAR(8) | NO | PK; FK → localidad.codigo_postal | Localidad cubierta por el transportista. Parte de la clave. |

## ingreso

Documento de ingreso de vinos al depósito central.

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| cod_ingreso | INTEGER (identity) | NO | PK | Identificador del ingreso. |
| fecha | DATE | NO | — | Fecha del ingreso. |
| estado | estado_documento | NO | *002:* DEFAULT 'en_confeccion' | Estado del documento: en_confeccion, terminado o procesado (RN-10). |
| cod_transportista | INTEGER | NO | FK → transportista.cod_transportista | Transportista que realizó el traslado. |
| cuit_bodega | cuit_dom | NO | FK → bodega.cuit | Bodega de origen de los vinos. |

## renglon_ingreso

Vino y cantidad de botellas de un ingreso.

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| cod_ingreso | INTEGER | NO | PK; FK → ingreso.cod_ingreso | Ingreso al que pertenece el renglón. Parte de la clave. |
| cod_vino | INTEGER | NO | PK; FK → vino.cod_vino | Vino ingresado. Parte de la clave. |
| cantidad | INTEGER | NO | *002:* CHECK > 0 (RN-15) | Botellas ingresadas. |

## transferencia

Solicitud de una sala al depósito central para reponer vinos.

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| nro_transferencia | INTEGER (identity) | NO | PK | Número de la solicitud de transferencia. Clave subrogada. |
| id_sala | INTEGER | NO | FK → sala_venta.id_sala | Sala solicitante. |
| fecha_confeccion | DATE | NO | *002:* DEFAULT CURRENT_DATE (inmodificable por trigger, RN-11) | Fecha de confección. Es la actual y no puede modificarse (RN-11). |
| estado | estado_documento | NO | *002:* DEFAULT 'en_confeccion' | Estado del documento: en_confeccion, terminado o procesado (RN-11). |

## renglon_transferencia

Vino y cantidad de botellas solicitados en una transferencia.

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| nro_transferencia | INTEGER | NO | PK; FK → transferencia.nro_transferencia | Transferencia a la que pertenece el renglón. Parte de la clave. |
| cod_vino | INTEGER | NO | PK; FK → vino.cod_vino | Vino solicitado. Parte de la clave. |
| cantidad | INTEGER | NO | *002:* CHECK > 0 (RN-15) | Botellas solicitadas. |

## stock_sala

Stock de cada vino en cada sala.

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| id_sala | INTEGER | NO | PK; FK → sala_venta.id_sala | Sala. Parte de la clave. |
| cod_vino | INTEGER | NO | PK; FK → vino.cod_vino | Vino. Parte de la clave. |
| cantidad | INTEGER | NO | *002:* CHECK >= 0 (RN-09); *002:* DEFAULT 0 | Botellas disponibles del vino en la sala. Nunca negativo (RN-09). |

## stock_deposito

Stock de cada vino en el depósito central.

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| cod_vino | INTEGER | NO | PK; FK → vino.cod_vino | Vino. Clave: hay un solo depósito central. |
| cantidad | INTEGER | NO | *002:* CHECK >= 0 (RN-09); *002:* DEFAULT 0 | Botellas disponibles del vino en el depósito central. Nunca negativo (RN-09). |

## auditoria_precio

Registro de cada cambio de precio de un vino (RN-13).

| Columna | Tipo | Nulo | Restricción | Descripción |
|---|---|---|---|---|
| id_auditoria | INTEGER (identity) | NO | PK | Identificador del registro de auditoría. |
| cod_vino | INTEGER | NO | FK → vino.cod_vino | Vino cuyo precio cambió. |
| precio_anterior | NUMERIC(10,2) | NO | *002:* CHECK > 0 (RN-15) | Precio antes del cambio. |
| precio_nuevo | NUMERIC(10,2) | NO | *002:* CHECK > 0 (RN-15) | Precio después del cambio. |
| fecha_hora | TIMESTAMP | NO | *002:* DEFAULT now() | Momento del cambio de precio. |
| usuario | VARCHAR(63) | NO | *002:* DEFAULT current_user | Usuario de base de datos que realizó el cambio. |

---

Total: 30 tablas, 129 columnas.

