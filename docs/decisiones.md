# Decisiones de diseño: Bodegas del Atuel

Este documento registra las decisiones tomadas al pasar del escenario (TPI, sección 3) al modelo entidad-relación (`bodegas_del_atuel_der.dbml`) y al esquema relacional. Para cada decisión se indica qué se cambió respecto de la tabla de **entidades mínimas (TPI, sección 5)** y la justificación teórica.

Referencias usadas:

- **[MER]**: Modelo Entidad-Relación (conceptual).
- **[MR]**: Modelo relacional, reglas de derivación E-R a relacional.
- **[ERE]**: Modelo Entidad-Relación Extendido (jerarquías IS-A).
- **[NORM]**: Normalización (1FN, 2FN, 3FN).
- **[INT]**: Reglas de integridad (entidad, referencial, dominio, usuario).
- **[TRIG]**: Funciones, procedimientos y triggers.
- **[IDX]**: Índices en PostgreSQL.

---

## 1. Criterios generales

1. **Se respetan las entidades mínimas.** Todo lo listado en la sección 5 del TPI está representado. Lo que se agrega (sección 2) se justifica caso por caso.
2. **Todo atributo tiene una única ubicación.** Cada hecho se guarda en la tabla que lo describe. Los atributos que sólo describen una relación van en la tabla intermedia, no en las entidades.
3. **Se almacena sólo lo que no se puede recalcular sin perder información.** Los derivados se calculan, salvo las excepciones documentadas en la sección 8.
4. **Las reglas que no pueden expresarse con un CHECK van en triggers o procedimientos** [INT] [TRIG].
5. **Ante la duda, la opción más simple**, siempre que no contradiga el TPI.

---

## 2. Cambios respecto de las entidades mínimas (TPI, sección 5)

| Entidad (TPI pág. 7) | En nuestro modelo | Cambio | Justificación |
|---|---|---|---|
| **Localidad** | Tabla `localidad`, PK `codigo_postal` | El encargado regional queda como atributo de la localidad, no como entidad. El código postal se tipa `VARCHAR(8)`. | El código postal es clave natural única. El encargado depende sólo de la localidad y no tiene atributos propios, así que no justifica una entidad. Si el encargado se guardara en la sala, habría una dependencia transitiva sala → localidad → encargado [NORM], y RN-02 podría romperse. El CP argentino es alfanumérico desde 2016 (ej. M5600), por eso no es numérico. |
| **Sala de venta** | Tabla `sala_venta` con `codigo_postal` FK | Sin cambios de fondo. La FK es `NOT NULL`. | Relación 1:N localidad → sala. Como la sala está en una sola localidad, la FK va del lado N [MR, regla 2a]. |
| **Empleado** | Tabla `empleado`, PK `cuit`, FK `id_sala` `NOT NULL` | PK natural (CUIT). FK obligatoria. | RN-03: cada empleado trabaja en una sola sala. Restricción de participación total [MR]. |
| **Finca** | Tabla `finca` con FK `id_departamento`. Nueva entidad `departamento` | **Cambio estructural.** `departamento` y `provincia` dejan de ser atributos de la finca y pasan a la entidad `departamento(nombre, provincia)`. | Sin esta separación, `finca → departamento → provincia` es una dependencia transitiva [NORM, 3FN]. El Anexo B.3 del TPI ya trata a los departamentos como catálogo. `departamento` tiene `UNIQUE(nombre, provincia)`. |
| **Parcela** | Tabla `parcela`, PK compuesta `(id_finca, nro_parcela)` | Sin cambios de fondo. | Entidad débil: depende de finca para existir [MER]. Según la regla 1d de [MR], su tabla incluye la PK de la entidad fuerte. La FK a `cepa` es `NOT NULL` (una parcela tiene una sola cepa). |
| **Cepa** | Tabla `cepa`, PK `id_cepa`, `nombre UNIQUE`, `tipo` ENUM | El tipo pasa a `ENUM tipo_cepa (tinta, blanca)`. | Es un catálogo. El tipo es un dominio cerrado, así que se modela con enumerado (el TPI pide que los estados y tipos no sean texto libre). |
| **Lote de uva** | Tabla `lote_uva`, PK `id_lote`, `nro_lote UNIQUE`, `UNIQUE(id_finca, nro_parcela, campania)`. FK compuesta a `parcela` | Se agrega `campania` a la unicidad. `nro_lote` es `UNIQUE` (corregido). La FK a parcela es compuesta. | RN-04: una parcela se cosecha como máximo una vez por campaña. Esa restricción es una clave candidata [MER], así que se declara `UNIQUE`. La FK compuesta refleja que el lote pertenece a una parcela concreta. |
| **Análisis de calidad** | Tabla `analisis_calidad`, FK `id_lote` | Sin cambios. | Relación 1:N: varios análisis por lote [MR, regla 2a]. |
| **Bodega** | Tabla `bodega`, PK `cuit` | Sin cambios. | El CUIT es clave natural única. Se referencia desde vino, lote e ingreso. |
| **Vino** | Tabla `vino`, PK `cod_vino` identity, `UNIQUE(nombre, anada, volumen_ml)` | `tipo` ENUM. `precio NUMERIC(10,2)`. `cuit_bodega` FK. | RN-01 (precio único y > 0) y RN-15. `NUMERIC` para dinero (TPI). La clave natural `(nombre, añada, volumen)` es larga y se referencia desde varias tablas, por eso se usa clave subrogada, conservando la natural como `UNIQUE`. |
| **Composición (vino-cepa)** | Tabla `vino_cepa`, PK `(cod_vino, id_cepa)`, atributo `porcentaje` | Relación N:M con atributo. Ver sección 3.1. | [MR, regla 2b]. |
| **Maridaje** | Tabla `maridaje`, PK `id_maridaje`, `nombre UNIQUE` | Sin cambios de fondo. | Catálogo. La temperatura es propiedad del maridaje (sección 3.2). |
| **Vino-maridaje** | Tabla `vino_maridaje`, PK compuesta | Sin cambios. | N:M sin atributos [MR, regla 2b]. |
| **Cliente** | Supertipo `cliente` con `tipo_cliente` discriminador, más subtipos | **Cambio importante.** Se agrega la columna discriminadora. El descuento no se guarda. La localidad es `codigo_postal`. El nombre puede ser nulo (sección 6.2). | Jerarquía IS-A [ERE]. Ver sección 6.1. |
| **Socio / Distribuidor / Exportador** | `cliente_distribuidor`, `cliente_exportador`. El socio no tiene tabla propia | Los subtipos se modelan como tablas 1:1 con el supertipo. | Ver sección 6.1. |
| **Permiso de exportación** | Tabla `permiso_exportacion`, PK `(id_cliente, codigo)`, FK a `cliente_exportador` | La FK apunta al subtipo, no al supertipo. | Garantiza por integridad referencial que sólo los exportadores tengan permisos, sin trigger. RN-07: `fecha_vencimiento > fecha_emision` como `CHECK` entre columnas. |
| **Comprobante** | Tabla `comprobante`, FK `id_cliente` e `id_sala`, `subtotal`, `descuento`, `total` | Se agregan las dos FK. Los importes se almacenan. | Ver secciones 3.3, 4 y 8. |
| **Renglón de comprobante** | Tabla `renglon_comprobante`, PK `(nro_comprobante, cod_vino)` | Agrega `precio_unitario`, `descuento_pct` y `subtotal` como snapshot. | Ver secciones 3.3 y 8. |
| **Transportista** | Tabla `transportista`, `cuit UNIQUE` | Email, teléfono y domicilio son `NOT NULL` (corregido). | El TPI dice "se conoce", por lo que son datos obligatorios. |
| **Transportista cubre localidad** | Tabla `transportista_localidad`, PK compuesta | Sin cambios de fondo. | N:M sin atributos [MR, regla 2b]. |
| **Ingreso / Renglón de ingreso** | Cabecera `ingreso` y renglón `renglon_ingreso` (PK `(cod_ingreso, cod_vino)`) | `estado` ENUM con default `en_confeccion`. | Ver sección 3.4. |
| **Transferencia / Renglón de transferencia** | Cabecera `transferencia` y renglón `renglon_transferencia` | `estado` ENUM. `fecha_confeccion DEFAULT CURRENT_DATE`. | RN-11: la fecha no se puede modificar. Se resuelve con trigger y no con `CHECK`, porque `CURRENT_DATE` no es determinístico y rompería un backup restaurado [TRIG]. |
| **Stock de sala** | Tabla `stock_sala`, PK `(id_sala, cod_vino)`, `CHECK (cantidad >= 0)` | Sin cambios de fondo. | N:M entre sala y vino con atributo `cantidad`. Ver sección 5. |
| **Stock de depósito** | Tabla `stock_deposito`, PK `cod_vino` | No se crea tabla `deposito`. | El TPI establece un único depósito central. Una tabla con una sola fila y sin atributos no aporta nada [MER: una entidad se justifica por sus atributos]. |
| **Auditoría de precio** | Tabla `auditoria_precio` | `usuario DEFAULT current_user`, `fecha_hora DEFAULT now()`. | RN-13, completada por un trigger AFTER UPDATE [TRIG]. |
| **Trazabilidad (no está en la lista)** | Tabla `vino_lote` | **Entidad nueva.** Ver sección 3.7. | Requerida por el endpoint `GET /reportes/trazabilidad/{cod}` del TPI. |

### Entidades que no están en la lista mínima

| Entidad nueva | Motivo |
|---|---|
| `departamento` | Evita la dependencia transitiva de la finca (ver tabla anterior). |
| `vino_lote` | Vincula lotes de uva con vinos, necesario para la trazabilidad. Incorporada al modelo (sección 3.7). |
| `cliente_distribuidor`, `cliente_exportador` | Subtipos de la jerarquía de clientes. |
| Tablas de renglones (`renglon_*`) | Son las tablas intermedias de las N:M con atributos. Ver sección 3. |

---

## 3. Relaciones N:M con tabla intermedia

La regla 2b de [MR] establece que una relación N:M se transforma en una tabla nueva, con las claves de las entidades participantes y los atributos propios de la relación. Cada tabla intermedia de este modelo cumple esa regla. Algunas, además, son entidades débiles de su cabecera (renglones).

### 3.1 Vino - Cepa (`vino_cepa`)

- **Por qué es N:M:** un vino puede estar compuesto por varias cepas (corte), y una cepa puede formar parte de varios vinos.
- **Por qué el porcentaje va en la intermedia:** el porcentaje describe la combinación vino-cepa, no a ninguno de los dos por separado. Si se guardara en `vino`, habría que repetir grupos de cepas y porcentajes, lo que viola 1FN [NORM]. Si se guardara en `cepa`, un mismo tipo de uva tendría un único porcentaje para todos los vinos, lo cual no tiene sentido.
- **Regla de suma 100 (RN-05):** no puede implementarse con `CHECK`, porque el `CHECK` evalúa cada fila por separado y la suma depende de varias filas insertadas en la misma transacción. Por eso se usa un **constraint trigger DEFERRABLE INITIALLY DEFERRED**, que verifica al hacer COMMIT [TRIG].
- **Acción referencial:** `vino → vino_cepa` es CASCADE, porque la composición no existe sin el vino. `cepa → vino_cepa` es RESTRICT, porque la cepa es catálogo y no puede borrarse si compone vinos (consigna D2).

### 3.2 Vino - Maridaje (`vino_maridaje`)

- **Por qué es N:M:** un vino admite varios maridajes, y un maridaje (ej. "carnes rojas") se repite en varios vinos. El TPI lo indica expresamente: "un maridaje puede repetirse para distintos vinos".
- **Por qué la temperatura no va en la intermedia:** la temperatura de servicio depende del maridaje, no de la combinación. Si estuviera en `vino_maridaje`, la temperatura de "carnes rojas" se repetiría en cada vino, con riesgo de inconsistencia. Es una dependencia que no respeta 3FN [NORM]. Por eso `temperatura_servicio` queda en `maridaje`.
- **Sin atributos propios:** es una N:M pura.

### 3.3 Comprobante - Vino (`renglon_comprobante`)

- **Por qué es N:M:** un comprobante contiene varios vinos, y un vino aparece en muchos comprobantes.
- **Por qué es también una entidad débil:** el renglón no existe sin su comprobante. Por eso su PK incluye la PK de la cabecera (`nro_comprobante`) y la del vino (`cod_vino`) [MR, regla 1d].
- **Atributos del renglón:**
  - `cantidad`: propiedad de la combinación.
  - `precio_unitario`: es el precio **al momento de la venta**. Si estuviera sólo en `vino.precio`, cada cambio de precio alteraría comprobantes ya emitidos. Como RN-13 audita los cambios, el precio vigente y el histórico son hechos distintos. En sentido estricto, `cod_vino → precio_unitario` deja de ser una dependencia funcional válida a lo largo del tiempo [NORM]. Por eso es un snapshot y se documenta como excepción (sección 8).
  - `descuento_pct` y `subtotal`: ver sección 8.

### 3.4 Ingreso - Vino (`renglon_ingreso`) y Transferencia - Vino (`renglon_transferencia`)

- Mismo patrón que el comprobante: cabecera más renglón, con PK compuesta y atributo `cantidad`.
- **Por qué cabecera y renglón son tablas separadas:** RN-12 (no agregar ni quitar renglones si el documento no está en confección) se implementa con un trigger sobre el renglón que consulta el estado de la cabecera. Eso sólo es posible si los renglones son una tabla propia [TRIG].
- **Acción referencial:** cabecera → renglón es CASCADE (un renglón sin documento no tiene sentido). `vino → renglón` es RESTRICT, porque un vino con movimientos no puede borrarse (RN-14).

### 3.5 Transportista - Localidad (`transportista_localidad`)

- **Por qué es N:M:** un transportista cubre varias localidades, y una localidad es cubierta por varios transportistas. El TPI lo indica como "transportista cubre localidad N:M".
- **Sin atributos propios:** es una tabla de cobertura pura.

### 3.6 Sala - Vino (`stock_sala`)

- **Por qué es N:M:** cada sala tiene stock de varios vinos, y cada vino está en varias salas.
- **Por qué `cantidad` está ahí:** el stock es un atributo de la combinación sala-vino.
- **Por qué la PK es `(id_sala, cod_vino)`:** permite usar `INSERT ... ON CONFLICT (id_sala, cod_vino) DO UPDATE` en `sp_procesar_transferencia`, que suma al stock de la sala de forma atómica (sección 5).

### 3.7 Vino - Lote de uva (`vino_lote`) *(incorporada)*

- **Por qué es N:M:** un vino puede elaborarse con uvas de varios lotes (distintas parcelas o campañas), y un lote puede destinarse a varios vinos.
- **Por qué existe:** el TPI pide `GET /reportes/trazabilidad/{cod}`. Sin esta tabla, ninguna entidad mínima conecta una cosecha con el vino que la usa. Es la única forma de responder "de qué parcelas viene este vino".
- **Sin atributos propios:** la versión actual no guarda cuántos kilos de cada lote entraron al vino. Si la cátedra lo pide, se agrega `kilos_utilizados` sin cambiar la estructura.
- **Regla de consistencia cruzada:** el lote usado en un vino debe haber sido entregado a la bodega que elabora ese vino, es decir, `lote_uva.cuit_bodega = vino.cuit_bodega`. Esa regla cruza tablas, así que no puede ser un `CHECK`. Se implementa con un trigger BEFORE INSERT sobre `vino_lote` [INT, regla de usuario; TRIG].
- **Acciones referenciales:** `vino → vino_lote` es CASCADE, porque el vínculo no tiene sentido sin el vino (si el vino tiene movimientos, RN-14 ya impide borrarlo). `lote_uva → vino_lote` es RESTRICT, porque un lote usado en un vino no puede borrarse: se perdería la trazabilidad.

---

## 4. Relación cliente - sala a través del comprobante

**Decisión:** no existe una relación directa cliente - sala. La relación se expresa a través de la entidad **comprobante**, que tiene FK a ambos.

**Por qué:**

1. **La compra tiene atributos.** Un cliente compra en una sala en una fecha, por un total, con un descuento. Esa información pertenece a la compra y no a la pareja (cliente, sala). Según [MER], "cuando surge una relación con atributos significa que debajo hay una entidad que aún no se ha definido": esa entidad es el comprobante.
2. **Una pareja cliente-sala puede tener muchas compras.** Si la relación fuera una tabla `cliente_sala(id_cliente, id_sala)`, no podría registrar cuántas compras hizo el cliente ni cuándo. Para distinguirlas haría falta una PK por compra, y en ese caso esa tabla ya sería el comprobante.
3. **Evitar dos caminos para la misma información.** Si existiera `cliente_sala` además de `comprobante`, el vínculo cliente-sala podría estar en dos lugares con valores distintos. Es la redundancia que [NORM] e [INT] buscan evitar. Con el modelo actual, "qué clientes compraron en una sala" se obtiene con un JOIN sobre comprobante (consigna S3).
4. **La sala es un atributo de la venta.** El comprobante guarda `id_sala` porque la venta ocurre en una sala determinada. Esa sala es la que descuenta stock (RN-09) y la que aparece en los reportes de ventas por sala (S8).

**Resultado:** la relación cliente-sala es N:M, realizada por comprobante. Cliente y vino también quedan relacionados a través del comprobante (con `renglon_comprobante`).

```
cliente 1 ──< comprobante >── 1 sala_venta
                  │
                  ╎ (renglon_comprobante, N:M con vino)
                  ▼
                vino
```

---

## 5. Transferencia, stock y sala

**Decisión:** `transferencia` no tiene FK a `stock_sala` ni a `stock_deposito`. Se relaciona con el stock de forma indirecta: la transferencia indica la **sala** solicitante (`id_sala`) y sus renglones indican los **vinos** y las cantidades. Al procesarla, `sp_procesar_transferencia` descuenta de `stock_deposito` y suma a `stock_sala(id_sala, cod_vino)`.

**Por qué:**

1. **Transferencia es un movimiento; stock es un saldo.** La transferencia es un documento que registra un hecho ("la sala X pidió N botellas del vino Y"). El stock es el estado resultante de todos los hechos. Un documento no debe apuntar a un saldo: el saldo se actualiza como efecto del procesamiento.
2. **La cardinalidad no permite una FK directa.** Una transferencia tiene varios vinos, por lo que tendría varias filas de stock. Una FK en la cabecera no podría expresarlo. Una FK en el renglón apuntaría a un par (sala, vino) que ya es clave de `stock_sala`, pero el renglón no debe crear ni modificar esa fila por sí mismo: eso lo hace el procedimiento.
3. **La clave de `stock_sala` coincide con los datos de la transferencia.** `(id_sala, cod_vino)` es exactamente `(transferencia.id_sala, renglon_transferencia.cod_vino)`. Por eso el procedimiento puede hacer el UPSERT sin buscar nada adicional.
4. **El depósito es único.** `stock_deposito` tiene PK `cod_vino`, sin `id_deposito`, porque el TPI define un solo depósito central.
5. **Atributo derivado almacenado (excepción).** Según [MR], los atributos derivados no se almacenan. El stock de sala es derivable de ingresos, transferencias y ventas. Sin embargo, RN-09 exige verificar stock al vender, y el TPI pide `stock >= 0` como `CHECK`. Por eso se almacena el saldo y se mantiene con procedimientos y triggers. El costo: si algún camino de código modifica el stock sin pasar por el procedimiento, el saldo puede desincronizarse. Se mitiga con `fn_stock_sala` y con las consultas de control de la etapa 3.

**Flujo al procesar una transferencia:**

1. Se valida que el estado sea `terminado` (RN-11).
2. Se bloquean las filas con `FOR UPDATE`.
3. Se verifica que `stock_deposito` alcance para cada vino (RN-09).
4. Se descuenta del depósito y se suma a `stock_sala`.
5. Se cambia el estado a `procesado`. Todo ocurre en una sola transacción.

---

## 6. Clientes: jerarquía y valores nulos

### 6.1 Jerarquía (IS-A)

**Restricciones semánticas** [ERE]: la jerarquía es **total** (todo cliente es socio, distribuidor o exportador) y **disjunta/exclusiva** (un cliente pertenece a un solo subtipo).

**Alternativas evaluadas** [ERE, "Conversión de relaciones IS-A"]:

| Opción | Descripción | Ventajas | Desventajas | Decisión |
|---|---|---|---|---|
| a) Tabla única | `cliente` con todas las columnas de los subtipos | Una sola tabla, un solo JOIN | Columnas nulas para los socios (zona, habilitación, país). Nulos por "no aplicable" [MER] | No |
| b) Una tabla por subtipo | `socio`, `distribuidor`, `exportador` completas | Sin nulos | `comprobante` necesitaría tres FK distintas o una unión, lo que impide la integridad referencial simple. Se duplica el ID y la lógica común | No |
| c) Supertipo + subtipos | `cliente` (común) más `cliente_distribuidor` y `cliente_exportador` 1:1 | Una sola FK desde comprobante. Atributos comunes sin repetir. Permisos con FK al subtipo | Hay que mantener coherente `tipo_cliente` con la fila del subtipo | **Sí** |

**Consistencia entre `tipo_cliente` y los subtipos.** La base no puede garantizarla sólo con FK: el discriminador es una columna y la existencia de la fila del subtipo es otra cosa. Se resuelve con un trigger que, al insertar o cambiar `tipo_cliente`, exige la fila correspondiente en el subtipo [INT, regla de usuario].

**El socio no tiene tabla propia** porque no tiene atributos propios. Si la cátedra exige uniformidad, puede crearse `cliente_socio` vacía sin alterar el modelo.

**El descuento no se almacena.** RN-06 define el descuento por tipo de cliente. Se calcula con `fn_descuento_cliente(tipo)` [TRIG]. Guardarlo en `cliente` sería un atributo derivado de `tipo_cliente`: una dependencia transitiva que viola 3FN.

### 6.2 Valores nulos documentados

Según [MER, dominios], un nulo puede significar "no aplicable", "desconocido" o "perdido". En este modelo sólo hay un atributo nulable, y su significado está documentado:

| Tabla.columna | Nulo permitido | Significado | Justificación |
|---|---|---|---|
| `cliente.nombre` | Sí | **No aplicable.** Para un cliente que es razón social (persona jurídica), el nombre de pila no existe. | El TPI dice "apellido y nombre **o razón social**". Se guarda la razón social en `apellido_razon_social` y `nombre` queda nulo. |

**Reglas asociadas:**

- `nombre` es obligatorio cuando `tipo_documento` es DNI, CUIL, PASAPORTE o CUIT de persona humana, y nulo sólo cuando es razón social. Esta validación depende de otra columna, así que va en un trigger o en un `CHECK` entre columnas que use sólo valores de la misma fila (no se usa `CURRENT_DATE`).
- Se evita `''` (cadena vacía) como sustituto de nulo, porque `''` es un valor real y rompe comparaciones y reportes.
- Todas las demás columnas son `NOT NULL`, porque el TPI las pide como datos conocidos.

---

## 7. Claves: naturales vs. subrogadas

| Tabla | Clave | Tipo | Justificación |
|---|---|---|---|
| `localidad` | `codigo_postal` | Natural | Identificador oficial, único y estable. Se referencia desde sala, cliente y transportista. `ON UPDATE CASCADE`, porque el CP puede cambiar. |
| `bodega` | `cuit` | Natural | Identificador fiscal único. Se referencia desde vino, lote e ingreso. `ON UPDATE CASCADE`. |
| `transportista` | `cod_transportista` + `cuit UNIQUE` | Subrogada + natural | El código lo usan las FK. El CUIT se mantiene único por negocio. |
| `empleado` | `cuit` | Natural | No es referenciado por ninguna tabla, así que cambiar la PK no tiene efectos en cascada. |
| `cliente` | `id_cliente` + `UNIQUE(tipo_documento, nro_documento)` | Subrogada + natural | El documento puede repetirse entre tipos distintos. La subrogada es la que referencian comprobantes y subtipos. |
| `vino` | `cod_vino` + `UNIQUE(nombre, anada, volumen_ml)` | Subrogada + natural | Clave natural larga y referenciada desde varias tablas. |
| `parcela` | `(id_finca, nro_parcela)` | Natural compuesta | Entidad débil. El número es único dentro de la finca [MER]. |
| `lote_uva` | `id_lote` + `nro_lote UNIQUE` + `UNIQUE(id_finca, nro_parcela, campania)` | Subrogada + naturales | Se referencia desde análisis de calidad y `vino_lote`. |
| `comprobante`, `transferencia`, `ingreso` | Número con identity | Subrogada | El número lo genera el sistema. Ver sección 10.1. |
| `stock_sala`, `stock_deposito`, renglones, `vino_lote`, `vino_cepa` | Compuesta o `cod_vino` | Natural compuesta | Representan una combinación única, sin necesidad de ID propio. |

---

## 8. Atributos derivados almacenados (excepciones documentadas)

El apunte [MR] dice que los derivados no se almacenan. Este modelo tiene las excepciones que siguen. En todos los casos, la justificación es de negocio, y la consistencia se garantiza en la base.

| Atributo | Dónde | Por qué se almacena | Cómo se garantiza |
|---|---|---|---|
| `subtotal` del renglón | `renglon_comprobante` | Es parte del documento. No debe cambiar si cambian reglas o precios después. | Función de cálculo + trigger BEFORE INSERT/UPDATE (RN-08) |
| `subtotal`, `descuento`, `total` del comprobante | `comprobante` | Igual que arriba. El TPI pide el total como atributo del comprobante. | Trigger AFTER INSERT en renglón recalcula la cabecera (RN-08). Consulta de control: total = suma de renglones |
| `precio_unitario` del renglón | `renglon_comprobante` | Precio histórico (sección 3.3). | Se toma de `vino.precio` en el momento de la venta, dentro del trigger o procedimiento |
| `descuento_pct` del renglón | `renglon_comprobante` | Descuento histórico: el tipo de cliente puede cambiar después, y el cobro debe seguir siendo verificable. | Se toma de `fn_descuento_cliente` al insertar |
| Saldo de stock (`stock_sala`, `stock_deposito`) | Tablas de stock | Permite verificar RN-09 en tiempo constante. | Se modifica sólo desde procedimientos y triggers. `CHECK (cantidad >= 0)` |

**Derivados que no se almacenan** (se calculan con funciones o consultas): antigüedad de empleados (`fn_antiguedad_anios`, consignas U2 y D3), descuento por tipo de cliente, rendimiento en kg/ha (S10), stock total de un vino (S9, vista) y la suma de porcentajes de un vino (se valida con el trigger diferido, no se guarda).

---

## 9. Acciones referenciales (ON DELETE / ON UPDATE)

Criterio: **RESTRICT** para movimientos y catálogos (protege el historial, RN-14). **CASCADE** sólo en renglones y entidades débiles que no existen sin su cabecera [MER]. **CASCADE en ON UPDATE** sólo para claves naturales que pueden cambiar.

| Relación | ON DELETE | ON UPDATE | Motivo |
|---|---|---|---|
| `sala_venta` → `localidad` | RESTRICT | CASCADE | Una localidad con salas no se borra. El CP puede corregirse. |
| `empleado` → `sala_venta` | RESTRICT | RESTRICT | Una sala con empleados no se borra sin reasignarlos. |
| `finca` → `departamento` | RESTRICT | RESTRICT | Catálogo. |
| `parcela` → `finca` | CASCADE | RESTRICT | Entidad débil: una parcela no existe sin su finca [MER]. |
| `parcela` → `cepa` | RESTRICT | RESTRICT | Catálogo. Una cepa plantada no se borra (D2). |
| `lote_uva` → `parcela` | RESTRICT | RESTRICT | Un lote es registro de producción. No se borra con la parcela, para preservar la trazabilidad. |
| `lote_uva` → `bodega` | RESTRICT | CASCADE | Trazabilidad. Se actualiza el CUIT en cascada si cambia. |
| `analisis_calidad` → `lote_uva` | CASCADE | RESTRICT | Un análisis no existe sin su lote. |
| `vino` → `bodega` | RESTRICT | CASCADE | RN-14. |
| `vino_cepa` → `vino` | CASCADE | RESTRICT | Renglón de composición sin cabecera. |
| `vino_cepa` → `cepa` | RESTRICT | RESTRICT | Una cepa en uso no se borra. |
| `vino_maridaje` → `vino` | CASCADE | RESTRICT | Vínculo sin cabecera. |
| `vino_maridaje` → `maridaje` | RESTRICT | RESTRICT | Catálogo. |
| `vino_lote` → `vino` | CASCADE | RESTRICT | Vínculo de trazabilidad sin vino (RN-14 impide borrar vinos con movimientos). |
| `vino_lote` → `lote_uva` | RESTRICT | RESTRICT | Un lote usado en un vino no se borra: se perdería la trazabilidad. |
| `cliente` → `localidad` | RESTRICT | CASCADE | |
| `cliente_*` → `cliente` | CASCADE | RESTRICT | Subtipo sin supertipo no tiene sentido. |
| `permiso_exportacion` → `cliente_exportador` | CASCADE | RESTRICT | Permiso sin exportador. |
| `comprobante` → `cliente` | RESTRICT | RESTRICT | Un cliente con ventas no se borra. Protege el historial (D4 y D6 sólo borran clientes sin compras). |
| `comprobante` → `sala_venta` | RESTRICT | RESTRICT | Historial. |
| `renglon_comprobante` → `comprobante` | CASCADE | RESTRICT | Renglón sin cabecera. Es lo que usa D1. |
| `renglon_comprobante` → `vino` | RESTRICT | CASCADE | RN-14. |
| `transportista_localidad` → `transportista` | CASCADE | RESTRICT | Vínculo de cobertura, sin atributos propios. |
| `transportista_localidad` → `localidad` | RESTRICT | CASCADE | Idem. |
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

**Nota sobre D1 y D4.** Como `comprobante → cliente` es RESTRICT, el borrado de socios con compras (D1 borra comprobantes antes que los clientes) sigue el orden correcto: primero comprobantes (en cascada a renglones) y después clientes. D4 y D6 sólo borran socios sin compras, así que RESTRICT no las bloquea.

---

## 10. Decisiones resueltas, correcciones y pendientes

### Índices para la etapa 4: explicación en profundidad

Esta sección explica cómo decidir los índices. La lista final se confirma recién con los planes de ejecución de la etapa 4.

**Qué es un índice y qué problema resuelve.** Sin índice, una condición como `WHERE id_sala = 3` obliga a PostgreSQL a leer todas las filas de la tabla (Seq Scan). Un índice B-tree (el tipo por defecto) es un árbol balanceado que ordena los valores de una columna y permite llegar a una fila en unas pocas lecturas de página, en lugar de recorrer toda la tabla [IDX]. Con 500.000 renglones, la diferencia puede ser de decenas de miles de páginas leídas contra unas pocas.

**El costo.** Cada índice ocupa espacio y se debe actualizar en cada INSERT, UPDATE y DELETE sobre la tabla. Por eso no conviene indexar todo: un índice que nadie usa sólo le cuesta al sistema [IDX, "Equilibrio"].

**Por qué las claves foráneas necesitan índice.** PostgreSQL crea índices automáticamente para PRIMARY KEY y UNIQUE, pero **no** para las FK [TPI, etapa 4]. Eso tiene tres consecuencias prácticas en este modelo:

1. **JOIN.** Consultas como S1 o S9 unen `renglon_comprobante` con `vino`. Si la FK del lado hijo no tiene índice, el planificador tiende a hash join o a nested loop con escaneo completo.
2. **Borrados y actualizaciones de la tabla padre.** Antes de borrar un vino, PostgreSQL debe comprobar si existe algún renglón que lo referencie (RESTRICT, RN-14). Sin índice en `renglon_comprobante.cod_vino`, esa comprobación recorre los 500.000 renglones. Con índice, es una búsqueda directa.
3. **Actualización en cascada.** Si se modifica un CUIT de bodega (ON UPDATE CASCADE), PostgreSQL debe encontrar todas las filas hijas que lo referencian: otra vez, sin índice, es un escaneo completo.

**Corrección a la lista anterior.** Había listado `lote_uva(id_finca, nro_parcela)` como candidato a índice. No hace falta: `UNIQUE(id_finca, nro_parcela, campania)` crea un índice B-tree cuyas primeras columnas son esas, y PostgreSQL lo usa para la FK. Lo mismo pasa con `renglon_comprobante(nro_comprobante)`, que es prefijo de la PK. Un índice que repite el prefijo de otro índice existente es redundante y sólo suma costo de escritura.

**Mapa de claves foráneas y si ya están cubiertas:**

| FK (tabla.columna) | ¿Cubierta por PK/UNIQUE? | Consultas que la usan | Decisión |
|---|---|---|---|
| `comprobante.id_sala` | No | S3, S8, S11 | Índice compuesto (ver candidatos) |
| `comprobante.id_cliente` | No | S3, S12, D1, D4, D6 | Índice candidato |
| `renglon_comprobante.cod_vino` | No (PK empieza por `nro_comprobante`) | S1, S2, S9, RESTRICT al borrar vino | Índice candidato, con INCLUDE |
| `renglon_transferencia.cod_vino` | No | S4, S6 | Índice candidato |
| `transferencia.id_sala` | No | S4, S5 | Índice parcial (ver candidatos) |
| `stock_sala.cod_vino` | No (PK empieza por `id_sala`) | S6, S9 | Índice candidato |
| `vino.cuit_bodega` | No | U3 (vinos de una bodega), RESTRICT al borrar bodega | Índice candidato |
| `empleado.id_sala` | No | D3 (empleados de una sala) | Índice candidato |
| `parcela.id_cepa` | No | D2 (cepas no usadas en parcelas) | Índice candidato |
| `vino_cepa.id_cepa` | No (PK empieza por `cod_vino`) | D2, S9 | Índice candidato |
| `vino_maridaje.id_maridaje` | No (PK empieza por `cod_vino`) | I2, consultas de maridaje | Índice candidato (baja prioridad) |
| `ingreso.cod_transportista` | No | S7 (transportista más activo) | Índice candidato |
| `analisis_calidad.id_lote` | No | Joins con lote | Índice candidato (baja prioridad) |
| `vino_lote.id_lote` | No (PK empieza por `cod_vino`) | Trazabilidad inversa (lote → vinos) | Índice candidato |
| `parcela.id_finca`, `lote_uva(id_finca, nro_parcela)` | Sí (PK y UNIQUE) | - | No requiere índice adicional |
| `renglon_comprobante.nro_comprobante`, `stock_deposito.cod_vino` | Sí (prefijo de PK) | - | No requiere índice adicional |
| `sala_venta.codigo_postal`, `cliente.codigo_postal`, `transportista_localidad.codigo_postal` | No | Poco uso | Sin índice por ahora (se revisa con EXPLAIN) |

**Candidatos a índice (lista propuesta, cumple los tipos pedidos):**

| # | Índice | Tipo | Consultas que mejora | Por qué esta forma |
|---|---|---|---|---|
| I1 | `comprobante (id_sala, fecha)` | **Compuesto** | S3, S8, S11 | La igualdad va primero (`id_sala = ?`) y el rango después (`fecha BETWEEN ...`). Ver regla de orden abajo. |
| I2 | `comprobante (id_cliente)` | Simple, FK | S12, D1, D4, D6 | Búsqueda de compras de un cliente y verificación de RESTRICT. |
| I3 | `renglon_comprobante (cod_vino) INCLUDE (cantidad, subtotal)` | **INCLUDE** | S1, S2, S9 | Con `INCLUDE`, las columnas que se suman viven en el índice. Así el motor puede responder con un *Index Only Scan* sin leer la tabla. Requiere `VACUUM` para que el visibility map sea útil. |
| I4 | `transferencia (id_sala) WHERE estado <> 'procesado'` | **Parcial** | S5 | Sólo indexa las transferencias pendientes, que son pocas. Ver advertencia sobre el predicado abajo. |
| I5 | `comprobante USING BRIN (fecha)` | **BRIN** | S8, S11 (rangos de fechas) | BRIN es muy chico, pero sólo funciona si los datos están ordenados físicamente por fecha (ver abajo). |
| I6 | `renglon_transferencia (cod_vino)` | FK simple | S4, S6 | Filtrado por vino dentro de transferencias. |
| I7 | `stock_sala (cod_vino)` | FK simple | S6, S9 | Stock de un vino en todas las salas. |
| I8 | `vino_lote (id_lote)` | FK simple | Trazabilidad inversa | La PK sólo sirve para buscar lotes por vino. |

**Candidatos descartados (requisito de la etapa 4: mostrar al menos uno):**

- **`vino (tipo)`.** El tipo tiene sólo 4 valores. Si la tabla tiene 1.000 vinos, cada valor aparece en unos 250 filas, es decir, un 25 % de la tabla. El planificador concluye que leer la tabla completa es más barato que saltar entre el índice y la tabla. Es el caso de **baja selectividad**, y es el ejemplo ideal para el punto 8 de la etapa 4 ("un caso en que el planificador no usa un índice existente"). Se puede crear el índice, correr `EXPLAIN` y mostrar que el planificador elige Seq Scan.
- **`vino (nombre)`.** Es redundante: el `UNIQUE(nombre, anada, volumen_ml)` ya crea un índice cuyo primer campo es `nombre`. Un índice extra no aporta nada y encarece los INSERT.
- **`cliente (tipo_cliente)`.** Mismo problema que `tipo` del vino: 3 valores.

**Regla del orden de las columnas en un índice compuesto** [IDX, "Índices compuestos"]:

- PostgreSQL usa un índice compuesto si la consulta filtra por las primeras columnas (regla del prefijo izquierdo).
- Conviene poner primero las columnas de **igualdad** y después las de **rango**.
- En `comprobante (id_sala, fecha)`: la consulta `WHERE id_sala = 1 AND fecha BETWEEN ...` lee un tramo contiguo del índice. Con el orden inverso `(fecha, id_sala)`, el motor recorre todo el rango de fechas y después descarta las filas de otras salas.
- Para documentarlo en la etapa 4: crear las dos variantes, medir ambas con `EXPLAIN (ANALYZE, BUFFERS)` y justificar la elección con "Rows Removed by Filter" y los buffers leídos.

**Advertencia sobre el índice parcial (I4).** El planificador sólo usa un índice parcial si puede probar que la condición de la consulta implica la del índice. `WHERE estado <> 'procesado'` en la consulta coincide con el índice, pero `WHERE estado IN ('en_confeccion', 'terminado')` no siempre se reconoce como equivalente. Hay que escribir la consulta con la misma expresión.

**Advertencia sobre BRIN (I5).** BRIN guarda, por bloques de páginas, el mínimo y el máximo de cada columna. Funciona bien sólo si el valor de `fecha` crece junto con la posición física de la fila. En la carga masiva (etapa 3), si las fechas se generan al azar y se insertan desordenadas, el BRIN no sirve. Dos acciones concretas: (a) cargar los comprobantes en orden cronológico en el script de carga; (b) verificar la correlación con `SELECT attname, correlation FROM pg_stats WHERE tablename = 'comprobante';`. Un valor cercano a 1 o a -1 indica que BRIN es útil.

**Cómo medir (protocolo para la etapa 4):**

1. Con la base cargada y sólo los índices de PK y UNIQUE, ejecutar `ANALYZE` y luego `EXPLAIN (ANALYZE, BUFFERS)` para S1, S4, S8 y S10. Guardar plan y tiempo.
2. Crear los índices de la lista y ejecutar `ANALYZE` de nuevo, porque las estadísticas del planificador deben reflejar los datos.
3. Repetir las mismas consultas. Comparar tipo de recorrido (Seq Scan, Index Scan, Bitmap Heap Scan, Index Only Scan), filas leídas y buffers (`shared hit` y `shared read`).
4. Ejecutar cada consulta dos veces, porque la primera puede estar fría en caché y distorsionar el tiempo.
5. **Costo de escritura:** medir la carga de `renglon_comprobante` con y sin los índices I3, I6 y I7. Para pruebas puntuales, `CREATE INDEX` es transaccional, así que se puede hacer `BEGIN; CREATE INDEX ...; ... ROLLBACK;`. `CREATE INDEX CONCURRENTLY` no puede ir dentro de una transacción.
6. Con `EXPLAIN` sin `ANALYZE` se ven sólo estimaciones. Para la evidencia del informe, siempre usar `ANALYZE`.

**Por qué esto conecta con la teoría de la materia.** Los índices no son un detalle de rendimiento: son la contracara física del modelo. Cada FK que no se indexa convierte una comprobación de integridad (RESTRICT o CASCADE) en un escaneo completo. Por eso las decisiones de FK de la sección 9 y los índices de esta sección tienen que revisarse juntas.

### 10.4 Tareas pendientes (para cargar en el chat de organización)

- [ ] Validar con la cátedra: numeración de comprobantes (global vs. por sala).
- [ ] Implementar trigger de regla cruzada de bodega en `vino_lote`.
- [ ] Implementar trigger de coherencia entre `cliente.tipo_cliente` y los subtipos.
- [ ] Definir la regla de obligatoriedad de `cliente.nombre` según tipo de documento (trigger o CHECK entre columnas).
- [ ] Escribir `002_constraints.sql` con las acciones referenciales de la sección 9.
- [ ] Ordenar la carga de `comprobante` por fecha en `db/seed/` (requisito de BRIN).
- [ ] Medir correlación de `comprobante.fecha` después de la carga (`pg_stats`).
- [ ] Etapa 4: ejecutar el protocolo de medición de la sección 10.3 para S1, S4, S8 y S10.
- [ ] Etapa 4: elegir un caso de planificador que no usa índice (candidato: `vino (tipo)`).
- [ ] Revisar el DBML contra este documento y aplicar cambios pendientes, si los hubiera.

---

## 11. Dónde va cada regla (resumen de decisiones)

| Tipo de regla [INT] | Mecanismo elegido | Ejemplos |
|---|---|---|
| Dominio de una fila | `NOT NULL`, `CHECK`, `ENUM`, `DOMAIN` | RN-01 (precio > 0), RN-15, tipos de vino y estados |
| Entidad | `PRIMARY KEY`, `UNIQUE` | RN-04 (una cosecha por parcela y campaña) |
| Referencial | `FOREIGN KEY` con acciones | RN-02, RN-03, RN-14 |
| Usuario, depende de otras filas, de otras tablas o de la fecha actual | Trigger o procedimiento | RN-05 (constraint trigger), RN-08, RN-09, RN-10, RN-11, RN-12, RN-13, regla de bodega en `vino_lote` |
| Cálculo reutilizable | Función | `fn_descuento_cliente`, `fn_total_comprobante`, `fn_stock_sala` |
| Operación de varios pasos | Procedimiento transaccional | `sp_procesar_ingreso`, `sp_procesar_transferencia` |