# Conciliación de reportes API con consultas de control SQL (issue #73)

Verificación de consistencia numérica y funcional entre las respuestas HTTP de los endpoints del router `/reportes/*` y las consultas SQL de control ejecutadas directamente sobre PostgreSQL (`db/seed/sql/02_controles.sql` y consultas directas de negocio).

## 1. Entorno y bases auditadas

| Dato | Valor |
|---|---|
| Motor | PostgreSQL 16 (contenedor `bodegas-db`) |
| API | FastAPI + Uvicorn (contenedor `bodegas-api`, `http://127.0.0.1:8000`) |
| Script de auditoría | `scripts/perf/verificar_reportes_controles.py` |
| Bases evaluadas | `bodegas_atuel` (esquema inicial) y `bodegas_atuel_bench` (semilla 1234 con volumen real) |
| Volumen en `bodegas_atuel_bench` | `comprobante=170.000`, `renglon_comprobante=680.060`, `sala_venta=15`, `vino=40`, `stock_deposito=40`, `stock_sala=600`, `ingreso=40`, `transportista=6` |

## 2. Verificación de invariantes de `db/seed/sql/02_controles.sql`

Antes de contrastar los reportes, se auditaron los controles de integridad sobre `bodegas_atuel_bench`:

| Control | Descripción | Anomalías | Estado |
|---|---|---|---|
| `C1` | Triggers de usuario habilitados (`tgenabled = 'O'`) | `0` | PASS |
| `C2` | Conteo de filas base en tablas involucradas | `8/8` tablas | PASS |
| `C3` | Renglones de comprobante sin cabecera huérfana | `0` | PASS |
| `C4` | Ausencia de stock negativo en salas (`stock_sala.cantidad < 0`) | `0` | PASS |
| `C5a` | Totales de cabecera (`comprobante.total = fn_total_comprobante`) | `0` | PASS |
| `C5b` | Subtotales de renglones históricos generados por `seed.py` | `19.137` | WARN (ver nota) |
| `C6` | Porcentaje de descuento aplicado (`fn_descuento_cliente`) | `0` | PASS |
| `C10` | Composición varietal de vinos (`SUM(porcentaje) = 100`) | `0` | PASS |
| `C11` | Consistencia entre `cliente.tipo_cliente` y tablas subtipo | `0` | PASS |
| `C12` | Ingresos y transferencias procesados con renglones asociados | `0` | PASS |
| `C13` | Ausencia de documentos con fecha futura | `0` | PASS |

> **Nota sobre `C5b` en `bodegas_atuel_bench`:** El generador masivo `seed.py` produjo `19.137` renglones sobre `680.060` con diferencia de redondeo de 1 centavo en `renglon_comprobante.subtotal`, pero `comprobante.total` (`C5a`) mantiene `0` anomalías respecto de `fn_total_comprobante`. Como `S8` agrega sobre `comprobante.total`, los importes reportados no presentan desvíos.

## 3. Comparación fila por fila: Endpoints `/reportes/*` vs SQL directo

Cada endpoint se consultó vía HTTP y sus items se compararon elemento a elemento (con precisión `Decimal` exacta para importes) contra la consulta SQL independiente ejecutada vía `psql`:

| Código | Endpoint consultado | Filas (`bodegas_atuel`) | Filas (`bodegas_atuel_bench`) | Cifra de control conciliada (`bench`) | Estado |
|---|---|---|---|---|---|
| `S1` | `GET /reportes/top-vinos?limite=10` | `0` | `10` | `2.665.127` botellas vendidas en el Top 10 (orden y cantidades idénticos) | PASS |
| `S6` | `GET /reportes/vinos-sin-stock` | `0` | `0` | Coincide con `vw_stock_total_vino` (`stock_total = 0`) | PASS |
| `S6` | `GET /reportes/vinos-sin-stock?id_sala=1` | `0` | `0` | Coincide con `fn_stock_sala(1, cod_vino) = 0` y stock en depósito `> 0` | PASS |
| `S7` | `GET /reportes/transportista-activo` | `0` | `0` | Coincide con `DENSE_RANK()` sobre `ingreso` en el último mes | PASS |
| `S8` | `GET /reportes/ventas-por-sala` | `1` (`0.00`) | `15` | Suma global `$ 17.643.129.124,38` idéntica sala por sala | PASS |
| `S8` | `GET /reportes/ventas-por-sala?periodo=ultimo_trimestre` | `1` (`0.00`) | `15` | Suma trimestral `$ 4.797.486.10,13` (`479.748.610,13`) idéntica sala por sala | PASS |

### Cierre contable cruzado (`S8` vs `C5a`)

En `bodegas_atuel_bench`, la suma de `monto_total` de las 15 salas devuelta por `GET /reportes/ventas-por-sala` (`17643129124.38`) coincide **al centavo** con `SELECT COALESCE(SUM(total), 0) FROM comprobante` (`17643129124.38`), verificando simultáneamente la integridad de la carga histórica (`02_controles.sql`) y la serialización `Decimal` de FastAPI.
