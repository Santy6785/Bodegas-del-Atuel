# Capa de Acceso a Datos (DAL) - Bodegas del Atuel

Este directorio contiene la Capa de Acceso a Datos (Data Access Layer) de la API REST para el Trabajo Práctico Integrador de Bases de Datos (UTN FRSR).

Cada módulo implementa funciones independientes usando exclusivamente el driver nativo **psycopg 3** con SQL parametrizado, sin recurrir a ORMs ni query builders.

---

## 1. Convenciones Generales

1. **SQL Parametrizado Estricto (R1, R2):**
   - Ningún valor provisto por el usuario se interpola, concatena ni formatea dentro de las cadenas SQL.
   - Todos los valores se envían como parámetros `%s` en `cursor.execute(query, params)`.
   - La composición dinámica de SQL se limita exclusivamente a fragmentos de texto fijos (`WHERE ... AND ...`) definidos en el código fuente.

2. **Sin Aritmética de Negocio en Python (R4):**
   - Los subtotales, totales, porcentajes de descuento y existencias de stock son calculados y administrados íntegramente por los objetos de PostgreSQL:
     - `fn_descuento_cliente(id_cliente)`: Devuelve el porcentaje de descuento comercial.
     - `fn_total_comprobante(nro)`: Totaliza el comprobante a partir de sus renglones.
     - `fn_stock_sala(id_sala, cod_vino)`: Obtiene el stock disponible en una sala de venta.
     - `vw_stock_total_vino`: Vista que consolida stock en depósito y en salas.
     - `sp_crear_comprobante`: Procedimiento de venta que valida stock, aplica precios y descuentos y totaliza.
     - `sp_procesar_transferencia` y `sp_procesar_ingreso`: Procedimientos que actualizan stocks y estados.
     - Triggers en base: snapshots de precio unitario, cálculo de subtotales, auditoría de precios y validaciones diferidas.

3. **Manejo de Transacciones (R5):**
   - Las conexiones del pool operan sin autocommit.
   - Las consultas de solo lectura (`SELECT`) se ejecutan directamente en la conexión.
   - Toda operación de modificación (`INSERT`, `UPDATE`, `DELETE`, `CALL`) se ejecuta dentro de un bloque explícito `with conn.transaction():`.
   - Los triggers diferidos (por ejemplo, `RN-05` suma de corte de cepas = 100 y coherencia de subtipos de cliente) se evalúan al hacer `COMMIT`.

4. **Propagación de Excepciones (R7):**
   - La DAL no captura excepciones de base de datos (`psycopg.Error`, `RaiseException`, `UniqueViolation`, etc.).
   - Los errores se propagan limpios a la capa superior (FastAPI / routers / error handlers) para su correspondiente traducción a códigos HTTP según la tabla de SQLSTATE.

5. **Precisión Numérica y Moneda (R6):**
   - Las columnas `NUMERIC` son leídas y devueltas como instancias nativas de `decimal.Decimal`, sin conversiones a `float` que degraden la precisión.

6. **Principio de Mínimo Privilegio (R9, R10):**
   - Todas las consultas se ejecutan con el rol `app_rw`.
   - No se imprimen ni se registran contraseñas ni cadenas de conexión.

---

## 2. Paginación y Filtros

Los listados que admiten paginación (`listar_vinos`, `listar_clientes`, `listar_transferencias`, `listar_ingresos`) siguen el estándar:
- **Parámetros:** `page` (default `1`, mínimo `1`), `page_size` (default `20`, rango `1` a `100`). Si los parámetros están fuera de rango, se lanza `ValueError`.
- **Cálculo de Total:** Se utiliza la función de ventana `count(*) OVER() AS total` en la misma consulta.
- **Páginas vacías:** Si la página solicitada se encuentra fuera de rango (sin filas), se realiza una consulta auxiliar `COUNT(*)` para obtener el total exacto.
- **Retorno:** Tupla tipada `tuple[list[dict], int]` con el formato `(items, total)`.

---

## 2.5. Descuentos por tipo de cliente

Los descuentos son un atributo derivado que la base de datos determina mediante
`fn_descuento_cliente(id_cliente)` y nunca los envía ni los calcula la API:

- **socio:** 10 %
- **distribuidor:** 20 %
- **exportador:** 30 %, o **35 %** si tiene **más de 3** permisos de exportación
  cargados (se cuentan todos, sin filtrar por vigencia).

Ninguna función de escritura recibe un porcentaje de descuento. El campo
`descuento_pct` se lee exclusivamente con `fn_descuento_cliente` y se congela
por renglón al momento de la venta mediante el trigger `trg_renglon_comprobante_antes`
(snapshot, D4).

---

## 3. Catálogo de Funciones por Módulo

| Módulo | Función | Tipo | Transacción | Objeto de Base Utilizado | Retorno |
|---|---|---|---|---|---|
| **vinos.py** | `listar_vinos` | Lectura | No | `vino`, `bodega`, `vino_cepa` | `tuple[list[dict], int]` |
| | `obtener_vino` | Lectura | No | `vino`, `bodega`, `vw_stock_total_vino` | `dict \| None` |
| | `obtener_composicion_vino` | Lectura | No | `vino_cepa`, `cepa` | `list[dict]` |
| | `obtener_maridajes_vino` | Lectura | No | `vino_maridaje`, `maridaje` | `list[dict]` |
| | `crear_vino` | Escritura | Sí | `vino`, `vino_cepa`, `vino_maridaje`, `ctg_vino_composicion` | `int` (cod_vino) |
| | `actualizar_vino` | Escritura | Sí | `vino`, `vino_cepa`, `vino_maridaje`, `trg_vino_auditoria` | `int` (filas afectadas) |
| | `eliminar_vino` | Escritura | Sí | `vino` (restricciones FK `RN-14`) | `int` (filas afectadas) |
| **clientes.py** | `listar_clientes` | Lectura | No | `cliente`, `fn_descuento_cliente` | `tuple[list[dict], int]` |
| | `obtener_cliente` | Lectura | No | `cliente`, `cliente_distribuidor`, `cliente_exportador`, `fn_descuento_cliente` | `dict \| None` |
| | `obtener_permisos_exportacion` | Lectura | No | `permiso_exportacion` | `list[dict]` |
| | `crear_cliente` | Escritura | Sí | `cliente`, `cliente_distribuidor`, `cliente_exportador`, `permiso_exportacion` | `int` (id_cliente) |
| | `actualizar_cliente` | Escritura | Sí | `cliente`, `cliente_distribuidor`, `cliente_exportador`, `permiso_exportacion` | `int` (filas afectadas) |
| | `eliminar_cliente` | Escritura | Sí | `cliente` (restricciones FK `RN-14`) | `int` (filas afectadas) |
| **comprobantes.py** | `crear_comprobante` | Escritura | Sí | `CALL sp_crear_comprobante(...)` | `int` (nro_comprobante) |
| | `obtener_comprobante` | Lectura | No | `comprobante`, `renglon_comprobante` | `dict \| None` |
| **transferencias.py** | `listar_transferencias` | Lectura | No | `transferencia` | `tuple[list[dict], int]` |
| | `obtener_transferencia` | Lectura | No | `transferencia`, `renglon_transferencia` | `dict \| None` |
| | `crear_transferencia` | Escritura | Sí | `transferencia` | `dict` |
| | `agregar_renglon_transferencia` | Escritura | Sí | `renglon_transferencia`, `trg_renglon_transferencia_confeccion` | `dict` |
| | `terminar_transferencia` | Escritura | Sí | `transferencia`, `trg_transferencia_estados` | `dict \| None` |
| | `procesar_transferencia` | Escritura | Sí | `CALL sp_procesar_transferencia(...)` | `None` |
| **ingresos.py** | `listar_ingresos` | Lectura | No | `ingreso` | `tuple[list[dict], int]` |
| | `obtener_ingreso` | Lectura | No | `ingreso`, `renglon_ingreso` | `dict \| None` |
| | `crear_ingreso` | Escritura | Sí | `ingreso` | `dict` |
| | `agregar_renglon_ingreso` | Escritura | Sí | `renglon_ingreso`, `trg_renglon_ingreso_confeccion` | `dict` |
| | `terminar_ingreso` | Escritura | Sí | `ingreso`, `trg_ingreso_estados` | `dict \| None` |
| | `procesar_ingreso` | Escritura | Sí | `CALL sp_procesar_ingreso(...)` | `None` |
| **reportes.py** | `top_vinos` | Lectura | No | `renglon_comprobante`, `vino` | `list[dict]` |
| | `ventas_por_sala` | Lectura | No | `sala_venta`, `comprobante` | `list[dict]` |
| | `vinos_sin_stock` | Lectura | No | `vino`, `stock_deposito`, `fn_stock_sala`, `vw_stock_total_vino` | `list[dict]` |
| | `transportista_activo` | Lectura | No | `transportista`, `ingreso` | `list[dict]` |
| | `trazabilidad_vino` | Lectura | No | `vino_lote`, `lote_uva`, `parcela`, `finca`, `cepa` | `list[dict]` |
| | `exportadores_con_descuento_extendido` | Lectura | No | `cliente`, `cliente_exportador`, `permiso_exportacion`, `fn_descuento_cliente` | `list[dict]` |
| **catalogos.py** | `listar_salas` | Lectura | No | `sala_venta` | `list[dict]` |
| | `listar_cepas` | Lectura | No | `cepa` | `list[dict]` |
| | `listar_bodegas` | Lectura | No | `bodega` | `list[dict]` |
| | `listar_maridajes` | Lectura | No | `maridaje` | `list[dict]` |
| | `listar_transportistas` | Lectura | No | `transportista` | `list[dict]` |
| | `listar_localidades` | Lectura | No | `localidad` | `list[dict]` |
| **salud.py** | `verificar_conexion` | Lectura | No | `SELECT 1` | `bool` |

---

## 4. Reglas de escritura y campos prohibidos

### Campos calculados prohibidos en escritura (regla de oro)

La API nunca envía ni calcula los siguientes campos; su valor lo aporta siempre
el objeto de base indicado:

| Campo calculado | Objeto de base que lo aporta |
|---|---|
| `descuento`, `subtotal`, `total` | `comprobante` (trigger RN-08) |
| `descuento_pct` | `fn_descuento_cliente(id_cliente)` / trigger `trg_renglon_comprobante_antes` |
| `porcentaje_descuento` | (eliminado; se deriva de `fn_descuento_cliente`) |
| `precio_unitario` | Snapshot en `renglon_comprobante` al insertar (trigger) |
| `stock`, `stock_deposito`, `stock_salas`, `stock_total` | `vw_stock_total_vino`, `fn_stock_sala`, `stock_deposito` |
| `fecha_alta`, `fecha_confeccion`, `estado` | DEFAULT / triggers de transición de estado |

### Formatos de entrada

- **Maridajes:** `list[int]` (solo identificadores enteros).
- **Fechas:** `date` o string ISO (`YYYY-MM-DD`), normalizadas con `validar_fecha`.
- **periodo (reportes):** solo admite `None` o `"ultimo_trimestre"`; cualquier otro valor lanza `ValueError`.

### Justificación de decisiones

La justificación de las decisiones D1 a D5 (descuentos derivados de permisos,
reformulación U6-R, regla de oro, snapshot de descuento, ubicación de la
justificación) se encuentra en `docs/decisiones.md` y no se repite en este
README.

---

## 5. Ejecución de Pruebas

### Pruebas Unitarias (sin base de datos):
```bash
pytest -m "not integration"
```

### Pruebas de Integración (con base de datos PostgreSQL 16 activa):
Asegúrese de contar con el contenedor `db` activo y las migraciones aplicadas:
```bash
# Desde la carpeta api/
cd api
pytest -m integration -v
```

La ruta a la carpeta `consultas/` (usada por las pruebas U12 y U13) se resuelve así:
1. Variable de entorno `BODEGAS_CONSULTAS_DIR` si existe.
2. Si no, `Path(__file__).resolve().parents[2] / "consultas"` (desde `api/tests/`).

Si la ruta no existe, las pruebas correspondientes se saltan con el motivo:
"carpeta consultas/ no encontrada; definir BODEGAS_CONSULTAS_DIR".

Si la base de datos no se encuentra accesible o configurada en las variables de entorno, los tests de integración se saltarán automáticamente (`pytest.skip`) indicando la razón.

---

## 6. Estado de verificación

### a) Resultado de pruebas unitarias
- Ejecución: `cd api && pytest -m "not integration" -v`
- Resultado: **41 pasan, 0 fallan, 0 se saltan** (incluye `test__reglas.py` y `test_salud.py`).

### b) Resultado de pruebas de integración
- Ejecución: `cd api && pytest -m integration -v`
- Resultado: **todas se saltan**.
- Motivo de cada salteada: la base de datos PostgreSQL no es alcanzable en este entorno (no hay Docker Desktop disponible y el PostgreSQL local requiere credenciales desconocidas). El conftest salta con: "Base de datos PostgreSQL no disponible para pruebas de integración".

### c) Estado de los prerequisitos de base
- `fn_descuento_cliente` derivada de la cantidad de permisos: **no verificado: base no alcanzable**.
- Columna `cliente_exportador.porcentaje_descuento` eliminada: **no verificado: base no alcanzable**.

Consultas de verificación (no ejecutadas por falta de base):
```sql
SELECT pg_get_functiondef('fn_descuento_cliente'::regproc);
SELECT column_name FROM information_schema.columns
WHERE table_name = 'cliente_exportador';
```

### d) Salida de las verificaciones de regla de oro
**1. `porcentaje_descuento` solo en `_reglas.py` (rechazo) y `README.md` (documentación):**
```
api/app/db/queries/README.md:130: | `porcentaje_descuento` | (eliminado; se deriva de `fn_descuento_cliente`) |
api/app/db/queries/_reglas.py:17:         "porcentaje_descuento",
```

**2. Sin aritmética de importes, descuentos ni stock:**
(sin resultados)

**3. Solo fragmentos fijos de WHERE (f-strings solo en mensajes o fragmentos fijos):**
Todos los f-strings en archivos `.py` de `queries/` corresponden a:
- Mensajes de `ValueError` (no son SQL).
- Fragmentos fijos de SQL como `{where_sql}` (construido con cadenas fijas `" WHERE "` y `" AND "`).
No hay interpolación de valores de usuario en el texto SQL.
