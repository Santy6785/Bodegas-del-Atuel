# Modelo relacional: Bodegas del Atuel

Modelo relacional lógico derivado del DER conceptual ([`../DER/readme.md`](../DER/readme.md)). Es la base de las migraciones de `db/migrations/` (etapa 2) y del diccionario de datos.

- **Fuente DBML:** `modelo_relacional.dbml` (pegable en dbdiagram.io).
- **Esquema relacional escrito:** `esquema relacional/esquema_relacional.md` (sólo PK y FK).
- **Decisiones:** [`../decisiones.md`](../decisiones.md), Parte 2.
- **Motor:** PostgreSQL 14 o superior (TPI). El `docker-compose` del repositorio usa PostgreSQL 16.

## Qué tiene y qué no tiene este nivel

Este nivel agrega lo que el DER no expresa:

- Claves subrogadas (identity) donde el negocio no tiene una clave corta.
- Tipos de datos: `NUMERIC` para dinero, `DATE` y `TIMESTAMP` para fechas, `ENUM` para estados y tipos cerrados, `DOMAIN` para el CUIT.
- Restricciones: `NOT NULL`, `UNIQUE`, `CHECK`, `DEFAULT`.
- Acciones referenciales (`ON DELETE` / `ON UPDATE`).
- Atributos derivados que se guardan como snapshot (precio y descuento históricos, totales del comprobante).
- Triggers, procedimientos y funciones que protegen las reglas RN-01 a RN-15.

## Convenciones

| Tema | Convención |
|---|---|
| Nombres | `snake_case`, en español, sin tildes ni eñes. Ejemplo: `anio_plantacion`, `campania`. |
| Tablas | Singular o descriptivo: `vino`, `renglon_comprobante`, `permiso_exportacion`. |
| PK | Nombrar con `PRIMARY KEY` en la definición. Las compuestas se listan en el orden de la entidad fuerte primero. |
| FK | Nombradas con `CONSTRAINT fk_<tabla>_<destino>` (ej. `fk_vino_bodega`). |
| Dinero | `NUMERIC(10,2)` para precios, `NUMERIC(12,2)` para importes de comprobante. Nunca `FLOAT`. |
| Porcentajes | `NUMERIC(5,2)`. |
| CUIT | `DOMAIN cuit_dom AS CHAR(11)` con `CHECK (VALUE ~ '^[0-9]{11}$')`. |
| Códigos postales | `VARCHAR(8)`, porque el CP argentino es alfanumérico (ej. M5600). |
| Estados y tipos cerrados | `ENUM`: `tipo_cepa`, `tipo_vino`, `dia_semana`, `tipo_cliente`, `tipo_documento`, `estado_documento`. |
| Nulos | Sólo `cliente.nombre` admite `NULL` (razón social: no aplicable). Todo lo demás es `NOT NULL`. Nunca `''` como sustituto. |
| Fechas de sistema | `DEFAULT CURRENT_DATE` o `now()`. Ninguna regla de `CHECK` depende de la fecha actual (TPI: se rompe al restaurar un backup). Esas reglas van en triggers. |

## Tablas (30)

Agrupadas por área. La definición completa de cada una (PK y FK) está en `esquema relacional/esquema_relacional.md`.

| Área | Tablas |
|---|---|
| Localidades y salas | `localidad`, `sala_venta`, `empleado` |
| Producción de uva | `departamento`, `finca`, `cepa`, `parcela`, `lote_uva`, `analisis_calidad` |
| Vinos | `bodega`, `vino`, `vino_cepa`, `maridaje`, `vino_maridaje`, `vino_lote` |
| Clientes | `cliente`, `cliente_distribuidor`, `cliente_exportador`, `permiso_exportacion` |
| Ventas | `comprobante`, `renglon_comprobante` |
| Transportistas e ingresos | `transportista`, `transportista_localidad`, `ingreso`, `renglon_ingreso` |
| Transferencias y stock | `transferencia`, `renglon_transferencia`, `stock_sala`, `stock_deposito` |
| Auditoría | `auditoria_precio` |

## Claves

### Claves primarias

| Tabla | PK | Tipo |
|---|---|---|
| `localidad` | `codigo_postal` | Natural |
| `sala_venta` | `id_sala` | Subrogada |
| `empleado` | `cuit` | Natural |
| `departamento` | `id_departamento` | Subrogada (ver discrepancia D1) |
| `finca` | `id_finca` | Subrogada |
| `parcela` | `(id_finca, nro_parcela)` | Natural compuesta (débil) |
| `cepa` | `id_cepa` | Subrogada |
| `lote_uva` | `id_lote` | Subrogada (ver D2) |
| `analisis_calidad` | `(id_lote, fecha, hora)` | Natural compuesta (débil) |
| `bodega` | `cuit` | Natural |
| `vino` | `cod_vino` | Subrogada |
| `maridaje` | `id_maridaje` | Subrogada (ver D2) |
| `cliente` | `id_cliente` | Subrogada |
| `cliente_distribuidor`, `cliente_exportador` | `id_cliente` | FK a `cliente` (1:1) |
| `permiso_exportacion` | `(id_cliente, codigo)` | Natural compuesta (débil) |
| `comprobante` | `nro_comprobante` | Subrogada |
| `renglon_comprobante` | `(nro_comprobante, cod_vino)` | Compuesta |
| `transportista` | `cod_transportista` | Subrogada |
| `ingreso` | `cod_ingreso` | Subrogada |
| `renglon_ingreso` | `(cod_ingreso, cod_vino)` | Compuesta |
| `transferencia` | `nro_transferencia` | Subrogada |
| `renglon_transferencia` | `(nro_transferencia, cod_vino)` | Compuesta |
| `stock_sala` | `(id_sala, cod_vino)` | Compuesta |
| `stock_deposito` | `cod_vino` | Natural (una fila por vino) |
| `auditoria_precio` | `id_auditoria` | Subrogada |
| `vino_cepa`, `vino_maridaje`, `vino_lote`, `transportista_localidad` | Compuesta de sus FK | Tablas intermedias N:M |

### Claves candidatas (`UNIQUE`)

| Tabla | Clave candidata |
|---|---|
| `departamento` | `(nombre, provincia)` |
| `lote_uva` | `nro_lote`; `(id_finca, nro_parcela, campania)` |
| `maridaje` | `nombre` |
| `cepa` | `nombre` |
| `vino` | `(nombre, anada, volumen_ml)` |
| `bodega` | (la PK es el CUIT, sin alternativas) |
| `transportista` | `cuit` |
| `cliente` | `(tipo_documento, nro_documento)` |
| `cliente_distribuidor` | `nro_habilitacion` |

### Claves foráneas con acciones

Las acciones completas están en `decisiones.md`, sección 2.10. Resumen del criterio:

- **RESTRICT** en movimientos y catálogos (`vino`, `bodega`, `transportista`, `cliente` con compras, `sala_venta`): protege el historial (RN-14).
- **CASCADE** en renglones y entidades débiles que no existen sin su cabecera: `renglon_*`, `parcela` → `finca`, `analisis_calidad` → `lote_uva`, `permiso_exportacion` → `cliente_exportador`, `cliente_*` → `cliente`.
- **ON UPDATE CASCADE** sólo en claves naturales que pueden cambiar: `localidad.codigo_postal`, `bodega.cuit`.

## Mapeo desde el DER

Cada entidad o relación del DER se convierte en tabla según [MR]: entidad fuerte → tabla con su clave; entidad débil → tabla con la PK de la fuerte (regla 1d); relación 1:N → FK en el lado N (regla 2a); relación N:M → tabla intermedia con los atributos de la relación (regla 2b).

| Elemento del DER | Tabla relacional | Diferencia |
|---|---|---|
| LOCALIDAD | `localidad` | Ninguna. |
| SALA_VENTA | `sala_venta` | Ninguna. `codigo_postal` es FK. |
| EMPLEADO | `empleado` | Ninguna. |
| DEPARTAMENTO | `departamento` | **D1**: clave subrogada con `UNIQUE(nombre, provincia)`. |
| FINCA | `finca` | Ninguna. |
| PARCELA (débil) | `parcela` | Ninguna. |
| CEPA | `cepa` | Ninguna. |
| LOTE_UVA | `lote_uva` | **D2**: clave subrogada con `UNIQUE(nro_lote)`. |
| ANALISIS_CALIDAD (débil) | `analisis_calidad` | **D3**: PK `(id_lote, fecha, hora)`, tal como indica el DER (clave parcial `fecha` + `hora`, más la clave de LOTE_UVA). |
| BODEGA | `bodega` | Ninguna. |
| VINO | `vino` | Ninguna. |
| MARIDAJE | `maridaje` | **D2**: clave subrogada con `UNIQUE(nombre)`. |
| CLIENTE | `cliente` | Se agrega `tipo_cliente` como discriminador de la especialización. No está en el DER. |
| SOCIO | (sin tabla) | Sin atributos propios. Se identifica con `tipo_cliente = 'socio'`. |
| DISTRIBUIDOR, EXPORTADOR | `cliente_distribuidor`, `cliente_exportador` | Subtipos 1:1 con `cliente`. |
| PERMISO_EXPORTACION (débil) | `permiso_exportacion` | FK al subtipo `cliente_exportador`, no al supertipo. |
| COMPROBANTE | `comprobante` | Se agregan `subtotal`, `descuento` y `total` como importes almacenados. |
| `incluye` (comprobante–vino) | `renglon_comprobante` | Atributos `cantidad`, `precio_unitario`, `descuento_pct`, `subtotal`. |
| TRANSPORTISTA | `transportista` | Ninguna. |
| `cubre` (localidad–transportista) | `transportista_localidad` | N:M sin atributos. |
| INGRESO | `ingreso` | `cuit_bodega` es FK a `bodega` (relación `de origen`). |
| `contiene` (ingreso–vino) | `renglon_ingreso` | Atributo `cantidad`. |
| TRANSFERENCIA | `transferencia` | Nombre de la clave: `nro_transferencia` (en el DER, `nro_solicitud`). |
| `contiene` (transferencia–vino) | `renglon_transferencia` | Atributo `cantidad`. |
| `tiene stock` (sala–vino) | `stock_sala` | Atributo `cantidad`, `CHECK (cantidad >= 0)`. |
| `almacena` (depósito–vino) | `stock_deposito` | **D4**: no hay tabla `deposito`. Ver D4. |
| `compuesto por` (vino–cepa) | `vino_cepa` | Atributo `porcentaje`. |
| `se recomienda con` (vino–maridaje) | `vino_maridaje` | N:M sin atributos. |
| `se elabora con` (vino–lote) | `vino_lote` | N:M sin atributos. Trazabilidad. |
| AUDITORIA_PRECIO | `auditoria_precio` | Ninguna. |
| `ubica`, `trabaja en`, `se entrega a`, `elabora`, `realiza`, `se emite en`, `solicita`, `registra precio`, `traslada`, `de origen` | FK en la tabla del lado N | Ninguna. |

## Discrepancias entre el DER y el relacional

Son decisiones conscientes, documentadas acá para que no se confundan al comparar los dos niveles.

| Código | Discrepancia | Decisión | Estado |
|---|---|---|---|
| D1 | `departamento` con clave subrogada y no con `(nombre, provincia)`. | Clave subrogada, por consistencia con el resto de las tablas de catálogo. La clave de negocio queda como `UNIQUE`. | Decidido |
| D2 | `lote_uva` y `maridaje` con clave subrogada. El DER usa `nro_lote` y `nombre`. | Clave subrogada: las claves de negocio se referencian desde varias tablas y son más largas o más propensas a cambiar. Quedan como `UNIQUE`. | Decidido |
| D3 | `analisis_calidad` con PK `(id_lote, fecha, hora)`, según el DER (entidad débil, regla 1d). Se descarta la subrogada `id_analisis`. | Se asume que un lote tiene como máximo un análisis por fecha y hora. | Decidido |
| D4 | `stock_deposito` sin tabla `deposito`. El DER tiene `DEPOSITO_CENTRAL` como instancia única. | Se colapsa la entidad. Una tabla con una sola fila y sin atributos no aporta nada. Si el depósito tuviera atributos propios (dirección, responsable), se crearía la tabla. | Decidido |
| D5 | `cliente` tiene `tipo_cliente`, que no está en el DER. | Es el discriminador de la especialización. Sin él, la base no sabría qué subtipo corresponde a cada cliente. | Decidido |
| D6 | `comprobante`, `transferencia` e `ingreso` usan numeración global. | Por simplicidad. Si la cátedra pide numeración por sala, la PK cambia a `(id_sala, nro)`. | Pendiente de validación |

## Atributos derivados que se almacenan

El DER los marca como derivados. El relacional los guarda por razones de negocio, con garantía de consistencia en la base:

| Atributo | Tabla | Motivo | Garantía |
|---|---|---|---|
| `subtotal` | `renglon_comprobante` | Parte del documento fiscal. | Trigger al insertar o modificar (RN-08). |
| `subtotal`, `descuento`, `total` | `comprobante` | Idem. El TPI pide el total como atributo. | Trigger al cambiar renglones. Control: total = suma de renglones. |
| `precio_unitario` | `renglon_comprobante` | Precio de la venta. RN-13 audita cambios, así que el precio vigente no sirve. | Se copia de `vino.precio` al insertar. |
| `descuento_pct` | `renglon_comprobante` | Descuento del momento de la venta. | Se toma de `fn_descuento_cliente` al insertar. |
| `cantidad` (saldo) | `stock_sala`, `stock_deposito` | Verificar RN-09 sin recorrer movimientos. | Sólo lo modifican procedimientos y triggers. `CHECK (cantidad >= 0)`. |

Derivados que no se guardan: `antigüedad` (función `fn_antiguedad_anios`), `descuento` del cliente (`fn_descuento_cliente`), rendimiento por hectárea (consulta S10), stock total por vino (vista).

## Restricciones por implementar

Lista para armar los archivos de la etapa 2. Cada una se asocia a una regla del enunciado.

### Restricciones `CHECK` (mínimo 8 exigidas por el TPI)

| Tabla | Restricción | Regla |
|---|---|---|
| `vino` | `precio > 0` | RN-01, RN-15 |
| `vino` | `graduacion BETWEEN 5 AND 20` | RN-15 |
| `vino` | `tipo IN ('tinto','blanco','rosado','espumante')` (si no es ENUM) | RN-15 |
| `vino` | `volumen_ml > 0` | RN-15 |
| `vino_cepa` | `porcentaje > 0 AND porcentaje <= 100` | RN-05 |
| `renglon_comprobante` | `cantidad > 0` | RN-15 |
| `renglon_ingreso`, `renglon_transferencia` | `cantidad > 0` | RN-15 |
| `stock_sala`, `stock_deposito` | `cantidad >= 0` | RN-09 |
| `permiso_exportacion` | `fecha_vencimiento > fecha_emision` (entre columnas) | RN-07 |
| `empleado` | `salario > 0` | RN-15 |
| `lote_uva` | `kilos > 0` | RN-15 |
| `parcela` | `superficie_ha > 0` | RN-15 |
| `maridaje` | `temperatura_servicio BETWEEN 0 AND 30` (valor orientativo) | Dominio |
| `cliente` | Obligatoriedad de `nombre` según `tipo_documento`: no es un CHECK simple. Va en un trigger (ver tabla de triggers). | Nulo "no aplicable" |

### Valores por defecto (mínimo 3 exigidos por el TPI)

- `ingreso.estado DEFAULT 'en_confeccion'`
- `transferencia.estado DEFAULT 'en_confeccion'`
- `cliente.fecha_alta DEFAULT CURRENT_DATE`
- `transferencia.fecha_confeccion DEFAULT CURRENT_DATE` (inmodificable por trigger, RN-11)
- `stock_sala.cantidad DEFAULT 0`

### Triggers mínimos (TPI, etapa 2)

| Trigger | Tipo | Regla |
|---|---|---|
| Validar stock al vender | BEFORE INSERT en `renglon_comprobante` | RN-09 |
| Calcular totales de comprobante | AFTER INSERT/UPDATE/DELETE en `renglon_comprobante` | RN-08 |
| Control de estados de ingreso y transferencia | BEFORE UPDATE en `ingreso` y `transferencia` | RN-10, RN-11 |
| Bloquear renglones fuera de confección | BEFORE INSERT/UPDATE/DELETE en `renglon_ingreso` y `renglon_transferencia` | RN-12 |
| Fecha de confección inmodificable | BEFORE INSERT/UPDATE en `transferencia` | RN-11 |
| Auditoría de precio | AFTER UPDATE de `vino.precio` | RN-13 |
| Suma de porcentajes = 100 | CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED en `vino_cepa` | RN-05 |
| Coherencia de bodega del lote | BEFORE INSERT en `vino_lote` | Regla cruzada de trazabilidad |
| Coherencia de `tipo_cliente` con subtipos | BEFORE INSERT/UPDATE en `cliente` | Especialización total y exclusiva |
| Nombre obligatorio según tipo de documento | BEFORE INSERT/UPDATE en `cliente` | Nulo "no aplicable" |

### Funciones y procedimientos

| Objeto | Tipo | Archivo |
|---|---|---|
| `fn_descuento_cliente(tipo_cliente)` | STABLE | `003_funciones.sql` |
| `fn_total_comprobante(nro)` | STABLE | `003_funciones.sql` |
| `fn_stock_sala(id_sala, cod_vino)` | STABLE | `003_funciones.sql` |
| `fn_antiguedad_anios(fecha)` | STABLE | `003_funciones.sql` |
| `sp_procesar_ingreso(cod_ingreso)` | PROCEDURE, transaccional | `004_procedimientos.sql` |
| `sp_procesar_transferencia(nro)` | PROCEDURE, transaccional | `004_procedimientos.sql` |

Cada función tiene un comentario con su propósito, parámetros y si es `STABLE` o `IMMUTABLE`. Ninguna `CHECK` usa `CURRENT_DATE` ni funciones no determinísticas.

## Cómo validar el modelo

1. Levantar PostgreSQL en un contenedor vacío.
2. Aplicar `001_esquema.sql` a `008_indices.sql` en orden. Ningún archivo debe fallar.
3. Verificar que el diccionario de datos coincide con el catálogo (`information_schema.columns`).
4. Ejecutar `tests/db_tests.sql`: al menos un caso por regla RN-01 a RN-15.
5. Confirmar que no hay `FLOAT` en importes, que los estados son `ENUM` y que ninguna tabla queda sin PK.

## Pendientes

1. **Validar D6** con la cátedra: numeración de comprobantes.
2. **Completar el DER en Lucidchart** con las dos relaciones que faltan (`tiene plantada`, `se cosecha en`). Están en este modelo.
3. **Validar las cardinalidades** del DER. Afectan las restricciones `NOT NULL` y las FK obligatorias.
4. **Agregar `tipo_cliente` al DER** como atributo discriminador, o documentar que es un detalle de implementación (D5).
5. **Revisar `002_constraints.sql`** contra la tabla de acciones referenciales de `decisiones.md`.
