# DER conceptual (MER-E): Bodegas del Atuel

Modelo entidad-relación extendido del TPI "Bodegas del Atuel" (UTN FRSR, Bases de Datos 2026). Es el **nivel conceptual**: describe entidades, atributos, relaciones, cardinalidades y especializaciones, sin claves técnicas ni tipos de datos. Los identificadores son los del enunciado (ID de sala, CUIT, código postal, código de vino, etc.).

- **Diagrama editable:** https://lucid.app/lucidchart/2ebb3b6d-0f8f-457b-ad7c-d3d8d568913a/edit?invitationId=inv_489aa44e-0a72-49de-86cd-81f49a8dbe56&page=p1#
- **Decisiones que lo sustentan:** [`../decisiones.md`](../decisiones.md), Parte 1.
- **Nivel siguiente:** [`../modelo_relacional/readme.md`](../modelo_relacional/readme.md).

## Notación

| Elemento | Representación | Ejemplo |
|---|---|---|
| Entidad | Rectángulo | `VINO` |
| Entidad débil | Rectángulo con doble contorno; depende de otra entidad para existir | `PARCELA`, `ANALISIS_CALIDAD`, `PERMISO_EXPORTACION` |
| Atributo | Óvalo unido a su entidad o relación | `precio` |
| Clave | Atributo subrayado | `cod_vino` |
| Atributo derivado | Óvalo con contorno punteado | `total` de `COMPROBANTE` |
| Atributo compuesto | Óvalo que se abre en sub-óvalos | `direccion` → `calle`, `numero` |
| Relación | Rombo con nombre verbal | `compuesto por` |
| Atributo de relación (N:M) | Óvalo unido al rombo | `porcentaje` en `compuesto por` |
| Especialización (IS-A) | Triángulo invertido entre superclase y subclases | `CLIENTE` → `SOCIO`, `DISTRIBUIDOR`, `EXPORTADOR` |

**Cardinalidad (min,max).** Se indica en el extremo de cada entidad y expresa cuántas veces esa entidad participa en la relación. En el diagrama aparece como terminación tipo pata de gallo, con esta equivalencia:

| Terminación | (min,max) |
|---|---|
| una línea | (1,1) |
| círculo + línea | (0,1) |
| línea + pata | (1,N) |
| círculo + pata | (0,N) |

Ejemplo: `VINO (1,N) — (0,N) CEPA` en *compuesto por*: un vino tiene entre 1 y N cepas, y una cepa aparece en 0 a N vinos.

**Especialización.** Se marca *total* (todo cliente pertenece a una subclase) y *exclusiva* (un cliente pertenece a una sola). Así lo describe el apunte ERE para total/parcial y solapada/exclusiva.

## Entidades (23)

| Entidad | Tipo | Clave | Atributos |
|---|---|---|---|
| LOCALIDAD | Fuerte | `codigo_postal` | nombre, provincia, encargado_regional |
| SALA_VENTA | Fuerte | `id_sala` | dia_cierre, direccion (calle, numero) |
| EMPLEADO | Fuerte | `cuit` | nombre, fecha_ingreso, salario, antigüedad (derivado) |
| DEPARTAMENTO | Fuerte | `nombre` + `provincia` | |
| FINCA | Fuerte | `id_finca` | nombre, superficie_ha |
| PARCELA | **Débil** de FINCA | `nro_parcela` (parcial) | superficie_ha, anio_plantacion |
| CEPA | Fuerte | `id_cepa` | nombre, tipo (tinta / blanca) |
| LOTE_UVA | Fuerte | `nro_lote` | campania, fecha_cosecha, kilos |
| ANALISIS_CALIDAD | **Débil** de LOTE_UVA | `fecha` + `hora` (parcial) | brix, ph, acidez_total |
| BODEGA | Fuerte | `cuit` | razon_social, domicilio |
| VINO | Fuerte | `cod_vino` | nombre_comercial, tipo, anada, volumen_ml, graduacion, precio |
| MARIDAJE | Fuerte | `nombre` | temperatura_servicio |
| CLIENTE | Fuerte (superclase) | `id_cliente` | apellido_razon_social, nombre (opcional), tipo_documento, nro_documento, direccion, fecha_alta, descuento (derivado) |
| SOCIO | Subclase de CLIENTE | | (sin atributos propios) |
| DISTRIBUIDOR | Subclase de CLIENTE | | zona_cobertura, nro_habilitacion |
| EXPORTADOR | Subclase de CLIENTE | | pais_destino_principal |
| PERMISO_EXPORTACION | **Débil** de EXPORTADOR | `codigo` (parcial) | fecha_emision, fecha_vencimiento |
| COMPROBANTE | Fuerte | `nro_comprobante` | fecha, subtotal, descuento, total (derivados) |
| TRANSPORTISTA | Fuerte | `cod_transportista` | razon_social, cuit, email, telefono, domicilio |
| INGRESO | Fuerte | `cod_ingreso` | fecha, estado |
| TRANSFERENCIA | Fuerte | `nro_solicitud` | fecha_confeccion, estado |
| AUDITORIA_PRECIO | Fuerte | `id_auditoria` | precio_anterior, precio_nuevo, fecha_hora, usuario |
| DEPOSITO_CENTRAL | Fuerte, **instancia única** | `nombre` | |

## Relaciones

Las cardinalidades son propuestas y están pendientes de validación (ver "Pendientes").

| Relación | Entidad A (min,max) | Entidad B (min,max) | Atributos de la relación |
|---|---|---|---|
| ubica | LOCALIDAD (0,N) | SALA_VENTA (1,1) | |
| trabaja en | SALA_VENTA (1,N) | EMPLEADO (1,1) | |
| se ubica en | FINCA (1,1) | DEPARTAMENTO (0,N) | |
| se divide en | FINCA (1,N) | PARCELA (1,1) | Identificadora (débil) |
| tiene plantada | PARCELA (1,1) | CEPA (0,N) | |
| se cosecha en | PARCELA (0,N) | LOTE_UVA (1,1) | |
| se practica | LOTE_UVA (1,N) | ANALISIS_CALIDAD (1,1) | Identificadora (débil) |
| se entrega a | LOTE_UVA (1,1) | BODEGA (0,N) | |
| elabora | BODEGA (1,N) | VINO (1,1) | |
| compuesto por | VINO (1,N) | CEPA (0,N) | **porcentaje** |
| se recomienda con | VINO (1,N) | MARIDAJE (0,N) | |
| se elabora con | VINO (1,N) | LOTE_UVA (0,N) | Trazabilidad |
| realiza | CLIENTE (0,N) | COMPROBANTE (1,1) | |
| se emite en | SALA_VENTA (0,N) | COMPROBANTE (1,1) | |
| incluye | COMPROBANTE (1,N) | VINO (0,N) | **cantidad, precio_unitario, descuento_pct, subtotal** |
| de origen | BODEGA (0,N) | INGRESO (1,1) | |
| traslada | TRANSPORTISTA (0,N) | INGRESO (1,1) | |
| contiene (ingreso) | INGRESO (1,N) | VINO (0,N) | **cantidad** |
| solicita | SALA_VENTA (0,N) | TRANSFERENCIA (1,1) | |
| contiene (transferencia) | TRANSFERENCIA (1,N) | VINO (0,N) | **cantidad** |
| tiene stock | SALA_VENTA (1,N) | VINO (0,N) | **cantidad** |
| almacena | DEPOSITO_CENTRAL (1,N) | VINO (0,N) | **cantidad** |
| registra precio | VINO (0,N) | AUDITORIA_PRECIO (1,1) | |
| cubre | LOCALIDAD (0,N) | TRANSPORTISTA (1,N) | |
| posee | EXPORTADOR (0,N) | PERMISO_EXPORTACION (1,1) | Identificadora (débil) |

**Total: 26 relaciones.**

## Decisiones de diseño conceptual

1. **Renglones como relaciones con atributos, no como entidades.** Comprobante–vino, ingreso–vino y transferencia–vino son N:M con atributos en el rombo. La combinación documento-vino identifica el renglón y no hay atributos propios que justifiquen una entidad aparte. El apunte MER permite esta representación.
2. **Stock como relación.** `tiene stock` (sala–vino) y `almacena` (depósito–vino) llevan `cantidad`. No hay entidad de stock.
3. **Departamento como entidad.** `provincia` depende del departamento y no de la finca. Si estuviera en la finca, habría una dependencia transitiva [NORM, 3FN].
4. **Cliente–sala a través del comprobante.** No hay relación directa. La compra tiene atributos (fecha, total), y el comprobante es el lugar donde se registran [MER].
5. **Transferencia sin relación con el stock.** `TRANSFERENCIA` se relaciona con la sala (`solicita`) y con los vinos (`contiene`). El stock se actualiza por procedimiento, no por una relación directa.
6. **Depósito como instancia única.** El enunciado define un solo depósito central. Se modela como entidad sin atributos propios, con una única instancia.
7. **Vino–lote.** La relación `se elabora con` existe para la trazabilidad que pide el TPI (`GET /reportes/trazabilidad/{cod}`). No estaba en la lista de entidades mínimas.

## Cambios frente a las entidades mínimas (TPI, página 7)

| Cambio | Motivo |
|---|---|
| Se agrega `DEPARTAMENTO` | Evita la dependencia transitiva en finca (3FN). |
| `PARCELA` pasa a entidad débil de `FINCA` | Una parcela no existe sin su finca (enunciado). |
| `COMPOSICION` (vino–cepa) queda como relación con atributo `porcentaje` | Decisión 1 de arriba. |
| Se agrega la relación `se elabora con` (vino–lote) | Trazabilidad. |
| `PERMISO_EXPORTACION` pasa a entidad débil de `EXPORTADOR` | Dependencia de existencia. |
| Clientes como superclase con tres subclases, total y exclusiva | El enunciado dice "existen tres tipos de cliente". |
| Renglones y stock como relaciones con atributos | Decisiones 1 y 2. |
| `DEPOSITO_CENTRAL` como instancia única | Enunciado: un solo depósito. |
| Atributos derivados marcados (antigüedad, descuento, subtotal, total) | Se calculan con funciones, salvo lo que se decide almacenar en el nivel relacional. |

## Pendientes

1. **Validar las cardinalidades propuestas:**
   - SALA_VENTA (1,N) con EMPLEADO: cada sala tiene al menos un empleado.
   - BODEGA (1,N) con VINO: cada bodega elabora al menos un vino.
   - VINO (1,N) con LOTE_UVA: cada vino usa al menos un lote.
   - LOCALIDAD (0,N) con SALA_VENTA: una localidad puede no tener salas.
   - TRANSPORTISTA (1,N) con LOCALIDAD: cada transportista cubre al menos una localidad.
   - EXPORTADOR (0,N) con PERMISO_EXPORTACION: un exportador puede no tener permisos.
   - VINO (0,N) con DEPOSITO_CENTRAL: un vino puede no tener stock en depósito.
2. **Reacomodar el layout.** El preflight de Lucid marcó superposiciones entre formas (por ejemplo, `PERMISO_EXPORTACION` con atributos de `VINO`) y textos que no entran en las formas. Son de presentación.
3. **Verificar el triángulo de especialización.** Está armado con líneas, porque Lucid no tiene triángulo invertido. Si se mueve alguna forma, hay que volver a unirlo.
