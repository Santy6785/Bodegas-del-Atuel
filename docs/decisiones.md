# Decisiones de diseño: Bodegas del Atuel

Este archivo registra **por qué** se tomó cada decisión. Para la descripción de cada nivel ver los READMEs: [`DER/readme.md`](DER/readme.md) (conceptual) y [`modelo_relacional/readme.md`](modelo_relacional/readme.md) (relacional, con el detalle de tablas, claves, restricciones, triggers y discrepancias).

Este documento tiene dos niveles, en el orden en que se construye el modelo:

1. **Nivel conceptual (MER-E):** entidades, atributos, relaciones, cardinalidades y jerarquías. Sin claves técnicas ni tipos de datos. Los identificadores son los del TPI (ID de sala, CUIT, código postal, código de vino, etc.).
2. **Nivel relacional:** tablas, claves subrogadas, tipos, dominios, restricciones y acciones referenciales. Parte de la transformación del nivel conceptual según las reglas del apunte MR.

Referencias de la cátedra usadas:

- **[MER]**: Modelo Entidad-Relación (entidades, atributos, relaciones, cardinalidades, claves).
- **[MR]**: Modelo relacional (reglas de derivación E-R a relacional).
- **[ERE]**: Modelo Entidad-Relación Extendido (especialización, total/parcial, solapada/exclusiva).
- **[NORM]**: Normalización (1FN, 2FN, 3FN).
- **[INT]**: Reglas de integridad.
- **[TRIG]**: Funciones, procedimientos y triggers.
- **[IDX]**: Índices en PostgreSQL.

---

# Parte 1: Nivel conceptual (MER-E)

## 1.1 Convenciones de notación

- **Entidad:** rectángulo. Entidad débil: rectángulo con doble contorno.
- **Atributo:** óvalo unido a su entidad o relación. La clave va subrayada. Los derivados van con contorno punteado. Los atributos compuestos se representan con un óvalo que se abre en sub-óvalos (ej. `direccion` → `calle`, `numero`).
- **Relación:** rombo con nombre verbal. Las N:M pueden tener atributos en óvalos unidos al rombo.
- **Cardinalidad (min,max):** se escribe junto a cada entidad y expresa cuántas veces esa entidad participa en la relación. Por ejemplo, `VINO (1,N) — (0,N) CEPA` significa que un vino tiene entre 1 y N cepas, y una cepa aparece en 0 a N vinos.
- **Especialización (IS-A):** triángulo invertido que une la superclase con sus subclases. Se marca como total o parcial, y como solapada o exclusiva [ERE].

## 1.2 Entidades y atributos

| Entidad | Clave | Atributos | Notas |
|---|---|---|---|
| LOCALIDAD | `codigo_postal` | nombre, provincia, encargado_regional | El código postal es alfanumérico desde 2016. |
| SALA_VENTA | `id_sala` | dia_cierre, direccion (compuesto: calle, numero) | |
| EMPLEADO | `cuit` | nombre, fecha_ingreso, salario, antigüedad (derivado) | `antigüedad` se calcula desde `fecha_ingreso`. |
| DEPARTAMENTO | `nombre` + `provincia` | | Catálogo (Anexo B.3 del TPI). Ver 1.5. |
| FINCA | `id_finca` | nombre, superficie_ha | |
| PARCELA (débil) | `nro_parcela` (parcial) + FINCA | superficie_ha, anio_plantacion | Clave parcial dentro de la finca. |
| CEPA | `id_cepa` | nombre, tipo (tinta / blanca) | `tipo` es un dominio cerrado. |
| LOTE_UVA | `nro_lote` | campania, fecha_cosecha, kilos | Una parcela se cosecha como máximo una vez por campaña (RN-04). |
| ANALISIS_CALIDAD (débil) | `fecha` (parcial) + LOTE | brix, ph, acidez_total | Varios análisis por lote. |
| BODEGA | `cuit` | razon_social, domicilio | |
| VINO | `cod_vino` | nombre_comercial, tipo, anada, volumen_ml, graduacion, precio | Clave alternativa: (nombre, anada, volumen_ml). |
| MARIDAJE | `nombre` | temperatura_servicio | |
| CLIENTE | `id_cliente` | apellido_razon_social, nombre (opcional), tipo_documento, nro_documento, direccion, fecha_alta, descuento (derivado) | Superclase IS-A (ver 1.6). |
| SOCIO | | (sin atributos propios) | Subclase de CLIENTE. |
| DISTRIBUIDOR | | zona_cobertura, nro_habilitacion | Subclase de CLIENTE. |
| EXPORTADOR | | pais_destino_principal | Subclase de CLIENTE. |
| PERMISO_EXPORTACION (débil) | `codigo` (parcial) + EXPORTADOR | fecha_emision, fecha_vencimiento | RN-07. |
| COMPROBANTE | `nro_comprobante` | fecha, subtotal (derivado), descuento (derivado), total (derivado) | Documento de venta. |
| TRANSPORTISTA | `cod_transportista` | razon_social, cuit, email, telefono, domicilio | |
| INGRESO | `cod_ingreso` | fecha, estado | Estado: en_confeccion, terminado, procesado (RN-10). |
| TRANSFERENCIA | `nro_solicitud` | fecha_confeccion, estado | `fecha_confeccion` no se puede modificar (RN-11). |
| AUDITORIA_PRECIO | `id_auditoria` | precio_anterior, precio_nuevo, fecha_hora, usuario | La completa un trigger (RN-13). |
| DEPOSITO_CENTRAL | `nombre` | | Instancia única: el TPI define un solo depósito. |

## 1.3 Relaciones y cardinalidades

Las cardinalidades son propuestas y pendientes de validación (ver 1.8).

| Relación | Entidades (min,max) | Atributos de la relación | Observación |
|---|---|---|---|
| ubica | LOCALIDAD (0,N) — SALA_VENTA (1,1) | | Cada sala está en una sola localidad (RN-02). |
| trabaja en | SALA_VENTA (1,N) — EMPLEADO (1,1) | | Cada empleado trabaja en una sola sala (RN-03). |
| se ubica en | FINCA (1,1) — DEPARTAMENTO (0,N) | | |
| se divide en | FINCA (1,N) — PARCELA (1,1) | | Identificadora de la entidad débil. |
| tiene plantada | PARCELA (1,1) — CEPA (0,N) | | Una sola cepa por parcela. |
| se cosecha en | PARCELA (0,N) — LOTE_UVA (1,1) | | RN-04 se valida con la clave candidata (parcela, campaña). |
| se practica | LOTE_UVA (1,N) — ANALISIS_CALIDAD (1,1) | | Identificadora de la entidad débil. |
| se entrega a | LOTE_UVA (1,1) — BODEGA (0,N) | | Bodega destino del lote. |
| elabora | BODEGA (1,N) — VINO (1,1) | | Un vino lo elabora una bodega. |
| compuesto por | VINO (1,N) — CEPA (0,N) | **porcentaje** | N:M con atributo (RN-05: suma 100 por vino). |
| se recomienda con | VINO (1,N) — MARIDAJE (0,N) | | N:M sin atributos. |
| se elabora con | VINO (1,N) — LOTE_UVA (0,N) | | Trazabilidad (TPI, endpoint de trazabilidad). |
| realiza | CLIENTE (0,N) — COMPROBANTE (1,1) | | |
| se emite en | SALA_VENTA (0,N) — COMPROBANTE (1,1) | | Sala donde se hizo la venta. |
| incluye | COMPROBANTE (1,N) — VINO (0,N) | **cantidad, precio_unitario, descuento_pct, subtotal** | N:M con atributos. Renglón de comprobante. |
| de origen / traslada | BODEGA (0,N) — INGRESO (1,1); TRANSPORTISTA (0,N) — INGRESO (1,1) | | RN-14 impide borrar bodegas y transportistas con movimientos. |
| contiene (ingreso) | INGRESO (1,N) — VINO (0,N) | **cantidad** | N:M con atributo. |
| solicita | SALA_VENTA (0,N) — TRANSFERENCIA (1,1) | | |
| contiene (transferencia) | TRANSFERENCIA (1,N) — VINO (0,N) | **cantidad** | N:M con atributo. |
| tiene stock | SALA_VENTA (1,N) — VINO (0,N) | **cantidad** | Stock por sala. RN-09. |
| almacena | DEPOSITO_CENTRAL (1,N) — VINO (0,N) | **cantidad** | Stock del depósito. |
| registra cambios de precio | VINO (0,N) — AUDITORIA_PRECIO (1,1) | | RN-13. |
| cubre | LOCALIDAD (0,N) — TRANSPORTISTA (1,N) | | N:M sin atributos. |
| posee | EXPORTADOR (0,N) — PERMISO_EXPORTACION (1,1) | | Identificadora de la entidad débil. |

## 1.4 Por qué los renglones son relaciones y no entidades

El apunte MER dice que cuando una relación tiene atributos, debajo puede haber una entidad asociada que todavía no se definió. El TPI, en cambio, describe la relación comprobante–vino y ingreso–vino como renglones con cantidades y precios. En este modelo elegimos representarlos como **relaciones N:M con atributos** (rombo con óvalos), tal como el apunte permite: la combinación (comprobante, vino) identifica un único renglón, y no hay atributos propios de un renglón que justifiquen una entidad aparte.

Esto deja la estructura conceptual más simple y coincide con la transformación relacional: una N:M con atributos se convierte en una tabla con las claves de los participantes y sus atributos [MR, regla 2b].

## 1.5 Departamento como entidad

La finca tiene `departamento` y `provincia`. Si esos atributos quedaran en la finca, `provincia` dependería del departamento y no de la finca: una dependencia transitiva que viola 3FN [NORM]. Por eso `DEPARTAMENTO` es una entidad con clave `(nombre, provincia)`, y FINCA se relaciona con ella mediante "se ubica en".

## 1.6 Jerarquía de clientes (MER-E)

- **Superclase:** CLIENTE.
- **Subclases:** SOCIO, DISTRIBUIDOR, EXPORTADOR.
- **Restricciones:**
  - **Total:** el TPI dice "existen tres tipos de cliente", así que todo cliente pertenece a alguna subclase.
  - **Exclusiva:** un cliente pertenece a una sola subclase.
- **SOCIO sin atributos propios:** se mantiene como subclase porque tiene reglas propias (descuento del 10 %). El ERE lo permite.
- **Descuento:** atributo derivado de la subclase (10 %, 20 %, 30 %). No se guarda en el nivel conceptual.
- **PERMISO_EXPORTACION** es entidad débil de EXPORTADOR, porque no existe sin su exportador (MER, dependencia de existencia).

## 1.7 Atributos derivados (nivel conceptual)

Se marcan con contorno punteado: `antigüedad` (EMPLEADO), `descuento` (CLIENTE), `subtotal`, `descuento` y `total` (COMPROBANTE). En el nivel relacional algunos se almacenan por razones de negocio (ver Parte 2, sección 2.6).

## 1.8 Cardinalidades propuestas (a validar)

Estas cardinalidades son decisiones mías a partir del enunciado. Conviene confirmarlas con la cátedra o con el grupo:

- SALA_VENTA (1,N) con EMPLEADO: cada sala tiene al menos un empleado.
- BODEGA (1,N) con VINO: cada bodega elabora al menos un vino.
- VINO (1,N) con LOTE_UVA: cada vino usa al menos un lote. LOTE_UVA (0,N): un lote puede no usarse todavía.
- LOCALIDAD (0,N) con SALA_VENTA: una localidad puede no tener salas.
- LOCALIDAD (0,N) con TRANSPORTISTA y TRANSPORTISTA (1,N): cada transportista cubre al menos una localidad.
- EXPORTADOR (0,N) con PERMISO_EXPORTACION: un exportador puede no tener permisos.
- VINO (0,N) con DEPOSITO_CENTRAL: cada vino puede no tener stock en el depósito.

---

# Parte 2: Nivel relacional

## 2.1 Transformación del nivel conceptual

Siguiendo [MR]:

- Cada entidad fuerte es una tabla, con su clave como PK (regla 1a y 1c).
- Cada entidad débil es una tabla que incluye la PK de la entidad fuerte (regla 1d): `parcela`, `analisis_calidad`, `permiso_exportacion`.
- Cada relación 1:N se resuelve poniendo la FK en el lado N (regla 2a).
- Cada relación N:M se resuelve con una tabla intermedia que tiene las claves de ambos lados y los atributos de la relación (regla 2b): `vino_cepa`, `vino_maridaje`, `vino_lote`, `renglon_comprobante`, `renglon_ingreso`, `renglon_transferencia`, `stock_sala`, `transportista_localidad`.
- La jerarquía de clientes se resuelve con la opción c de [ERE]: supertipo más subtipos 1:1 (ver 2.3).

## 2.2 Claves: naturales y subrogadas

| Tabla | Clave | Tipo | Justificación |
|---|---|---|---|
| `localidad` | `codigo_postal` | Natural | Identificador oficial. `ON UPDATE CASCADE`, porque el CP puede cambiar. |
| `bodega` | `cuit` | Natural | Identificador fiscal. `ON UPDATE CASCADE`. |
| `transportista` | `cod_transportista` + `cuit UNIQUE` | Subrogada + natural | El código lo usan las FK. |
| `empleado` | `cuit` | Natural | No lo referencia ninguna tabla. |
| `cliente` | `id_cliente` + `UNIQUE(tipo_documento, nro_documento)` | Subrogada + natural | El mismo número puede existir con distintos tipos de documento. |
| `vino` | `cod_vino` + `UNIQUE(nombre, anada, volumen_ml)` | Subrogada + natural | La clave natural es larga y la referencian cinco tablas. |
| `parcela` | `(id_finca, nro_parcela)` | Natural compuesta | Entidad débil. |
| `lote_uva` | `id_lote` + `UNIQUE(nro_lote)` + `UNIQUE(id_finca, nro_parcela, campania)` | Subrogada + naturales | Ambas claves alternativas son de negocio. |
| `comprobante`, `transferencia`, `ingreso` | Número con identity | Subrogada | El número lo genera el sistema. Ver 2.8. |
| Renglones, `stock_*`, `vino_*`, `transportista_localidad` | Compuesta | Natural compuesta | Combinación única, sin ID propio. |

## 2.3 Jerarquía de clientes: transformación

Las tres opciones de [ERE, "Conversión de relaciones IS-A"]:

| Opción | Descripción | Ventajas | Desventajas | Decisión |
|---|---|---|---|---|
| a) Tabla única | `cliente` con todas las columnas | Un solo JOIN | Nulos para zona, habilitación y país | No |
| b) Una tabla por subtipo | `socio`, `distribuidor`, `exportador` completas | Sin nulos | `comprobante` necesitaría tres FK distintas, y la integridad referencial se pierde | No |
| c) Supertipo + subtipos 1:1 | `cliente` más `cliente_distribuidor` y `cliente_exportador` | Una sola FK desde comprobante. Permisos con FK al subtipo | Hay que garantizar la coherencia de `tipo_cliente` con la fila del subtipo | **Sí** |

Coherencia entre `tipo_cliente` y los subtipos: un trigger exige la fila del subtipo correspondiente al insertar o cambiar el tipo [INT, regla de usuario]. `permiso_exportacion` referencia a `cliente_exportador`, así que sólo los exportadores pueden tener permisos, sin trigger.

## 2.4 Relaciones N:M: tablas intermedias

- **`vino_cepa`:** atributo `porcentaje`. La suma por vino debe ser 100 (RN-05). Como un `CHECK` evalúa cada fila por separado, se usa un constraint trigger `DEFERRABLE INITIALLY DEFERRED` [TRIG].
- **`vino_maridaje`:** sin atributos. La temperatura pertenece al maridaje, no a la combinación: si estuviera en la intermedia se repetiría en cada vino, lo que viola 3FN [NORM].
- **`vino_lote`:** sin atributos. La regla cruzada "el lote fue entregado a la bodega que elabora el vino" necesita otras tablas, así que va en un trigger [INT].
- **`renglon_comprobante`:** atributos `cantidad`, `precio_unitario`, `descuento_pct`, `subtotal`. `precio_unitario` es un snapshot (ver 2.6).
- **`renglon_ingreso` y `renglon_transferencia`:** atributo `cantidad`. RN-12 (no modificar renglones fuera de confección) se implementa con un trigger que consulta el estado de la cabecera, lo que exige que el renglón sea tabla propia.
- **`stock_sala`:** atributo `cantidad`, con `CHECK (cantidad >= 0)`. PK `(id_sala, cod_vino)` para usar `ON CONFLICT` en el procedimiento.
- **`transportista_localidad`:** sin atributos.

## 2.5 Cliente-sala a través del comprobante

No hay tabla `cliente_sala`. El vínculo entre cliente y sala se expresa en `comprobante`, que tiene FK a ambos.

- La compra tiene atributos (fecha, total, descuento). Esos atributos pertenecen a la compra y no a la pareja (cliente, sala) [MER].
- Una pareja cliente-sala puede tener muchas compras, así que una tabla `cliente_sala` no podría registrarlas una por una.
- Tener dos caminos para el mismo vínculo (directo y por comprobante) genera redundancia y riesgo de inconsistencia [NORM, INT].
- La consulta "qué clientes compraron en una sala" se resuelve con un JOIN sobre comprobante (S3).

## 2.6 Atributos derivados almacenados (excepciones)

[MR] establece que los derivados no se almacenan. Estas son las excepciones, con su justificación de negocio y cómo se garantiza su consistencia:

| Atributo | Dónde | Por qué se almacena | Cómo se garantiza |
|---|---|---|---|
| `subtotal` del renglón | `renglon_comprobante` | Es parte del documento. No debe cambiar si cambian reglas después. | Función de cálculo + trigger (RN-08) |
| `subtotal`, `descuento`, `total` | `comprobante` | Documento fiscal. El TPI pide el total como atributo. | Trigger que recalcula la cabecera (RN-08). Consulta de control: total = suma de renglones |
| `precio_unitario` | `renglon_comprobante` | Precio histórico. RN-13 audita cambios de precio, así que `cod_vino → precio` no es válido en el tiempo [NORM]. | Se toma de `vino.precio` al insertar |
| `descuento_pct` | `renglon_comprobante` | Descuento histórico. Depende de `tipo_cliente` a través de comprobante (dependencia transitiva en el tiempo). | Se toma de `fn_descuento_cliente` al insertar |
| Saldo de stock | `stock_sala`, `stock_deposito` | Verificar RN-09 en tiempo constante. | Se modifica sólo desde procedimientos y triggers. `CHECK (cantidad >= 0)` |

Derivados que no se almacenan: antigüedad (`fn_antiguedad_anios`), descuento de cliente (`fn_descuento_cliente`), rendimiento kg/ha (S10), stock total de un vino (vista).

## 2.7 Transferencia y stock

En el nivel conceptual, TRANSFERENCIA se relaciona con SALA_VENTA ("solicita") y con VINO ("contiene"). STOCK_SALA es una relación SALA-VINO con atributo cantidad. **No hay relación directa entre TRANSFERENCIA y el stock.**

Razones:

1. La transferencia es un movimiento (un documento). El stock es un saldo (un estado). Un documento no debe apuntar a un saldo.
2. La transferencia tiene varios vinos, así que no puede tener una FK única a una fila de stock.
3. La clave de `stock_sala` coincide con `(transferencia.id_sala, renglon_transferencia.cod_vino)`, así que el procedimiento actualiza el stock sin búsquedas adicionales.
4. El enlace entre transferencia y stock lo hace `sp_procesar_transferencia`, que descuenta del depósito y suma a la sala en una sola transacción.

## 2.8 Números de documento

Comprobante, transferencia e ingreso usan numeración global con identity. Por simplicidad, porque el TPI no especifica numeración por punto de venta. Si la cátedra lo pide, la clave cambia a `(id_sala, nro)`.

## 2.9 Valores nulos documentados

Según [MER, dominios], un nulo puede significar "no aplicable", "desconocido" o "perdido". En el modelo hay un único atributo opcional:

| Atributo | Significado del nulo | Regla |
|---|---|---|
| `cliente.nombre` | **No aplicable**: el cliente es razón social y no tiene nombre de pila. | Obligatorio si el tipo de documento es de persona humana. Nulo sólo si es razón social. Se valida con un trigger o un CHECK entre columnas. No se usa `''` como sustituto de nulo. |

## 2.10 Acciones referenciales

Criterio: **RESTRICT** para movimientos y catálogos (protege el historial, RN-14). **CASCADE** sólo en renglones y entidades débiles que no existen sin su cabecera. **ON UPDATE CASCADE** sólo para claves naturales que pueden cambiar.

| Relación | ON DELETE | ON UPDATE | Motivo |
|---|---|---|---|
| `sala_venta` → `localidad` | RESTRICT | CASCADE | El CP puede corregirse. |
| `empleado` → `sala_venta` | RESTRICT | RESTRICT | |
| `finca` → `departamento` | RESTRICT | RESTRICT | Catálogo. |
| `parcela` → `finca` | CASCADE | RESTRICT | Entidad débil. |
| `parcela` → `cepa` | RESTRICT | RESTRICT | Una cepa plantada no se borra (D2). |
| `lote_uva` → `parcela` | RESTRICT | RESTRICT | Registro de producción; preserva la trazabilidad. |
| `lote_uva` → `bodega` | RESTRICT | CASCADE | Clave natural que puede cambiar. |
| `analisis_calidad` → `lote_uva` | CASCADE | RESTRICT | Entidad débil. |
| `vino` → `bodega` | RESTRICT | CASCADE | RN-14. |
| `vino_cepa` → `vino` | CASCADE | RESTRICT | Composición sin cabecera. |
| `vino_cepa` → `cepa` | RESTRICT | RESTRICT | Una cepa en uso no se borra. |
| `vino_maridaje` → `vino` | CASCADE | RESTRICT | |
| `vino_maridaje` → `maridaje` | RESTRICT | RESTRICT | Catálogo. |
| `vino_lote` → `vino` | CASCADE | RESTRICT | Vínculo sin cabecera. RN-14 impide borrar vinos con movimientos. |
| `vino_lote` → `lote_uva` | RESTRICT | RESTRICT | Un lote usado en un vino no se borra: se perdería la trazabilidad. |
| `cliente` → `localidad` | RESTRICT | CASCADE | |
| `cliente_*` → `cliente` | CASCADE | RESTRICT | Subtipo sin supertipo no tiene sentido. |
| `permiso_exportacion` → `cliente_exportador` | CASCADE | RESTRICT | Entidad débil. |
| `comprobante` → `cliente` | RESTRICT | RESTRICT | Protege el historial de ventas. |
| `comprobante` → `sala_venta` | RESTRICT | RESTRICT | Historial. |
| `renglon_comprobante` → `comprobante` | CASCADE | RESTRICT | Renglón sin cabecera. Es lo que usa D1. |
| `renglon_comprobante` → `vino` | RESTRICT | CASCADE | RN-14. |
| `transportista_localidad` → `transportista` | CASCADE | RESTRICT | Vínculo de cobertura. |
| `transportista_localidad` → `localidad` | RESTRICT | CASCADE | |
| `ingreso` → `transportista` | RESTRICT | RESTRICT | RN-14. |
| `ingreso` → `bodega` | RESTRICT | CASCADE | RN-14. |
| `renglon_ingreso` → `ingreso` | CASCADE | RESTRICT | Renglón sin cabecera. |
| `renglon_ingreso` → `vino` | RESTRICT | CASCADE | RN-14. |
| `transferencia` → `sala_venta` | RESTRICT | RESTRICT | Historial. |
| `renglon_transferencia` → `transferencia` | CASCADE | RESTRICT | Renglón sin cabecera. |
| `renglon_transferencia` → `vino` | RESTRICT | CASCADE | RN-14. |
| `stock_sala` → `sala_venta` / `vino` | RESTRICT | RESTRICT | Un stock con saldo no se borra en silencio. |
| `stock_deposito` → `vino` | RESTRICT | RESTRICT | Idem. |
| `auditoria_precio` → `vino` | RESTRICT | RESTRICT | La auditoría es inmutable. |

## 2.11 Dónde va cada regla

| Tipo de regla [INT] | Mecanismo | Ejemplos |
|---|---|---|
| Dominio de una fila | `NOT NULL`, `CHECK`, `ENUM`, `DOMAIN` | RN-01, RN-15, tipos y estados |
| Entidad | `PRIMARY KEY`, `UNIQUE` | RN-04 |
| Referencial | `FOREIGN KEY` con acciones | RN-02, RN-03, RN-14 |
| Usuario (depende de otras filas, tablas o de la fecha actual) | Trigger o procedimiento | RN-05 (constraint trigger), RN-08, RN-09, RN-10, RN-11, RN-12, RN-13, regla de bodega en `vino_lote` |
| Cálculo reutilizable | Función | `fn_descuento_cliente`, `fn_total_comprobante`, `fn_stock_sala` |
| Operación de varios pasos | Procedimiento transaccional | `sp_procesar_ingreso`, `sp_procesar_transferencia` |

## 2.12 Índices (etapa 4)

PostgreSQL no indexa automáticamente las FK [IDX]. Las FK relevantes para la etapa 4 son:

- `comprobante(id_sala, fecha)`: compuesto, igualdad primero y rango después (S3, S8, S11).
- `renglon_comprobante(cod_vino)`: con `INCLUDE (cantidad, subtotal)` (S1, S2, S9).
- `transferencia(id_sala) WHERE estado <> 'procesado'`: parcial (S5).
- `comprobante(fecha)`: BRIN, sólo si la carga inserta por fecha (S8, S11).
- `renglon_transferencia(cod_vino)`, `stock_sala(cod_vino)`, `vino_lote(id_lote)`: FK y consultas por vino o lote.
- `empleado(id_sala)`: para D3.
- `parcela(id_cepa)`: para D2.
- `vino(cuit_bodega)`: para U3 y el RESTRICT al borrar bodegas.

Descartado como ejemplo: `vino(tipo)`, por baja selectividad (4 valores). Sirve para el caso de la etapa 4 en que el planificador no usa el índice.

---

# Parte 3: Pendientes

Estado de cada pendiente. La lista completa con detalle está en los READMEs.

- [ ] **Etapa 2:** implementar el trigger de regla cruzada de bodega en `vino_lote`.
- [ ] **Etapa 2:** implementar el trigger de coherencia entre `cliente.tipo_cliente` y los subtipos.
- [ ] **Etapa 2:** implementar la regla de obligatoriedad de `cliente.nombre` según tipo de documento.
- [ ] **Etapa 2:** escribir `002_constraints.sql` con las acciones de la sección 2.10.
- [ ] **Etapa 3:** ordenar la carga de `comprobante` por fecha (requisito de BRIN).
- [ ] **Etapa 4:** medir según el protocolo de IDX y elegir el caso de planificador que no usa índice.
