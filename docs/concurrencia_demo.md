# Demo de Concurrencia: Ultima botella de vino
## Bodegas del Atuel - Etapa 2 (Anexo A.8)

## Objetivo
Demostrar y explicar el problema de condición de carrera (race condition) al intentar vender
la última botella de vino con sesiones concurrentes. Se comparan tres escenarios:
1. **CON FOR UPDATE**: Bloqueo optimista con SELECT ... FOR UPDATE (recomendado)
2. **SIN FOR UPDATE**: Doble venta por falta de bloqueo (lost update)
3. **REPEATABLE READ**: Error de serialización (SQLSTATE 40001)

El problema central es que, en nivel READ COMMITTED (el default de PostgreSQL),
dos sesiones pueden leer el mismo valor de stock, ambas decidir que hay suficiente stock,
y ambas realicen la venta, resultando en que se "vendió" la misma botella dos veces
(lost update).

## Preparación de datos

### Datos de demo en la base de datos
Para que la demo funcione, la base debe tener configurado lo siguiente:

```sql
-- Una sala de venta (id_sala = 7)
SELECT * FROM sala_venta WHERE id_sala = 7;

-- Un vino en esa sala con stock = 1 botella
SELECT * FROM stock_sala WHERE id_sala = 7 AND cod_vino = 9;

-- El vino en sí (cod_vino = 9)
SELECT * FROM vino WHERE cod_vino = 9;
```

### Datos insertados para la demo:
- `sala_venta`: id_sala=7, calle='DemoStreet', numero='101', dia_cierre='lunes', codigo_postal='10000001'
- `vino`: cod_vino=9, nombre='Demo Wine Tinto', tipo='tinto', anada=2020, volumen_ml=750, graduacion=13.50, precio=100.00, cuit_bodega='20100000000'
- `stock_sala`: id_sala=7, cod_vino=9, cantidad=1 (última botella)

**Para restablecer el estado después de la demo:**
```sql
-- Volver a dejar stock en 1
UPDATE stock_sala SET cantidad = 1 WHERE id_sala = 7 AND cod_vino = 9;

-- Borrar datos de demo (opcional)
-- DELETE FROM stock_sala WHERE id_sala = 7 AND cod_vino = 9;
-- DELETE FROM vino WHERE cod_vino = 9;
-- DELETE FROM sala_venta WHERE id_sala = 7;
```

## Escenario 1: CON bloqueo (SELECT ... FOR UPDATE)

### Nivel de aislamiento: READ COMMITTED (por defecto de PostgreSQL)

### Flujo paso a paso:

| Paso | Sesión A | Sesión B | Qué pasa |
|------|----------|----------|----------|
| 1 | `BEGIN;` | | A inicia transacción |
| 2 | `SELECT cantidad FROM stock_sala WHERE id_sala = 7 AND cod_vino = 9 FOR UPDATE;` | | **A bloquea la fila** en modo EXCLUSIVE. PostgreSQL pone un lock de fila en `stock_sala` |
| 3 | | `SELECT cantidad FROM stock_sala WHERE id_sala = 7 AND cod_vino = 9 FOR UPDATE;` | **B ESPERA** a que A libere el lock. El driver/psql muestra el estado de espera. |
| 4 | | Consulta a `pg_stat_activity`: Se ve que B tiene `wait_event_type = 'Lock'` y `wait_event = 'LockBuffer'` o similar. Desde `pg_locks`: Se ve que la fila está bloqueada por el PID de A. | | **Evidencia para el informe** |
| 5 | `UPDATE stock_sala SET cantidad = cantidad - 1;` | | A actualiza el stock de 1 a 0 |
| 6 | `COMMIT;` | | **A confirma**: El lock se libera, B deja de esperar |
| 7 | | `SELECT cantidad ... FOR UPDATE;` | **B ahora obtiene el resultado**: `cantidad = 0` (lo que A acaba de hacer visible) |
| 8 | | `ROLLBACK;` | B deshace su transacción (no realizó cambios) |

### Resultado esperado:
- **Stock final: 0** (se vendió exactamente 1 botella)
- **Ninguna sesión falla** con error deconstraint
- **Se vendió una sola botella** gracias al bloqueo de fila

### Capturas de terminal (momento clave):

**[CAPTURA 1]**: Sesión A ejecutando `SELECT ... FOR UPDATE` - el prompt muestra que comenzó la transacción.

**[CAPTURA 2]**: Sesión B intentando el mismo `SELECT ... FOR UPDATE` - el comando se queda "esperando" (no retorna). En otra terminal:
```bash
SELECT pid, wait_event_type, wait_event FROM pg_stat_activity WHERE state = 'Active' OR state = 'Waiting';
-- Se muestra el PID de A y que espera en 'Lock'
```

**[CAPTURA 3]**: Después de que A hace COMMIT, la sesión B finalmente retorna:
```
 cantidad 
---------
        0
(1 row)
```

### Explicación técnica:
- **SELECT ... FOR UPDATE** en PostgreSQL, en nivel READ COMMITTED, bloquea la fila física en la tabla.
- Mientras A mantiene el lock en modo EXCLUSIVE, cualquier otra transacción que intente leer la misma fila con FOR UPDATE se pondrá en estado de espera (wait).
- Cuando A hace COMMIT, el lock se libera y B ve el nuevo estado de la fila (cantidad=0, porque A ya restó 1).
- Este es un patrón seguro para ventas: solo se puede vender lo que hay, y el bloqueo evita la doble venta.

## Escenario 2: SIN bloqueo (SELECT simple)

### Nivel de aislamiento: READ COMMITTED (por defecto)

### Variantes a probar y reportar:

#### Variante 2a: Doble venta "calculada en la aplicación" (lost update clásico)

| Paso | Sesión A | Sesión B | Qué pasa |
|------|----------|----------|----------|
| 1 | `BEGIN;` | | A inicia transacción |
| 2 | `SELECT cantidad FROM stock_sala WHERE id_sala = 7 AND cod_vino = 9;` | | A lee stock = 1 |
| 3 | | `BEGIN;` | B inicia transacción |
| 4 | | `SELECT cantidad FROM stock_sala WHERE id_sala = 7 AND cod_vino = 9;` | **B también lee stock = 1** (READ COMMITTED: cada sentencia ve el estado confirmado al momento de ejecutarse, pero la decisión de B se tomó con dato viejo) |
| 5 | | | **Ambas sesiones deciden que hay stock** y calculan `cantidad - 1 = 0` |
| 6 | `UPDATE stock_sala SET cantidad = 0 WHERE id_sala = 7 AND cod_vino = 9;` | | A actualiza a 0 |
| 7 | `COMMIT;` | | A confirma |
| 8 | | `UPDATE stock_sala SET cantidad = 0 WHERE id_sala = 7 AND cod_vino = 9;` | B intenta actualizar a 0 (mismo valor) |
| 9 | | `COMMIT;` | B confirma |

### Resultado:
- **Stock final: 0** (correcto por suerte, pero por la razón incorrecta)
- **2 transacciones de venta registradas** (aunque solo haya 1 botella)
- **Lost update**: Ambas transacciones leyeron el mismo valor y actualizaron al mismo valor resultante

**Evidencia en la base** (después de ambas confirmaciones):
```sql
SELECT * FROM stock_sala WHERE id_sala = 7 AND cod_vino = 9;
-- cantidad = 0 (correcto)
-- Pero 2 ventas se registraron en la aplicación cuando solo debería haber 1
```

#### Variante 2b: UPDATE relativo (`cantidad = cantidad - 1`) sin FOR UPDATE

En READ COMMITTED, cada sentencia ve lo que otras transacciones ya confirmaron, pero la decisión de B se tomó con un dato viejo.

| Paso | Sesión A | Sesión B | Qué pasa |
|------|----------|----------|----------|
| 1 | `BEGIN;` | | A inicia |
| 2 | `UPDATE stock_sala SET cantidad = cantidad - 1 WHERE id_sala = 7 AND cod_vino = 9;` | | A actualiza de 1 a 0, confirma después |
| 3 | `COMMIT;` | | A confirma, stock pasa a 0 |
| 4 | | `BEGIN;` | B inicia |
| 5 | | `UPDATE stock_sala SET cantidad = cantidad - 1 WHERE id_sala = 7 AND cod_vino = 9;` | **B actualiza: cantidad - 1 = 0 - 1 = -1** |
| 6 | | Error: `check constraint "ck_stock_sala_cantidad" violated` (SQLSTATE 23514) |
| 7 | | El CHECK `cantidad >= 0` actúa como última barrera | |

### Resultado:
- **Error 23514** en la sesión B: "check constraint violated"
- El constraint `ck_stock_sala_cantidad` (cantidad >= 0) actúa como barrera final
- **Pero el usuario recibe un error técnico genérico**, no un mensaje de negocio claro como "stock insuficiente"
- **Riesgo**: Si el CHECK no existiera, se permitiría stock negativo (ventasfantasma)

## Escenario 3: Nivel de aislamiento REPEATABLE READ

### Configuración:
```sql
-- En la sesión A:
BEGIN;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SELECT cantidad FROM stock_sala WHERE id_sala = 7 AND cod_vino = 9 FOR UPDATE;

-- En la sesión B:
BEGIN;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SELECT cantidad FROM stock_sala WHERE id_sala = 7 AND cod_vino = 9 FOR UPDATE;
```

### Comportamiento:
| Paso | Sesión A | Sesión B | Qué pasa |
|------|----------|----------|----------|
| 1 | `BEGIN; SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;` | | A inicia con nivel REPEATABLE READ |
| 2 | `SELECT cantidad ... FOR UPDATE;` | | A lee stock=1 y bloquea la fila |
| 3 | | `BEGIN; SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;` | B inicia con mismo nivel |
| 4 | | `SELECT cantidad ... FOR UPDATE;` | **B ESPERA** a que A confirme (igual que en READ COMMITTED con FOR UPDATE) |
| 5 | `COMMIT;` | | A confirma |
| 6 | | `SELECT ... FOR UPDATE;` | **B obtiene el resultado** (cantidad=0), igual que en READ COMMITTED |
| **O si A hace UPDATE sin COMMIR primero**: | | | |
| 5' | `UPDATE stock_sala SET cantidad = 0;` | | A actualiza en silencio (visible solo al propio A dentro de la transacción REPEATABLE READ, ya que vio el estado al BEGIN) |
| 6' | | `SELECT ... FOR UPDATE;` | **B recibe ERROR: could not serialize access due to concurrent update** (SQLSTATE 40001) |
| 7' | | `ROLLBACK;` | B revierte su transacción |

### SQLSTATE: 40001 (serialization_failure)

### Explicación:
- En REPEATABLE READ, PostgreSQL detecta al COMMIT que la transacción B modificó datos que ya fueron leídos/Modificados por A dentro de su ventana de tiempo (desde su BEGIN).
- PostgreSQL revierte la transacción B con error 40001 en lugar de permitir una anomalía de serialización.
- La API debe traducir este error a **503 Service Unavailable** con mensaje de reintento sugerido (según tabla de errores del enunciado).

### Comparación de niveles:

| Nivel | Comportamiento con 2 sesiones concurrentes | SQLSTATE | Aplicación |
|-------|-------------------------------------------|----------|------------|
| READ COMMITTED (default) | Sin FOR UPDATE: lost update (2 ventas) <br> Con FOR UPDATE: una sola venta correcta | - / 23514 | El proyecto usa este nivel por defecto |
| REPEATABLE READ | Error 40001 (serialization failure) <br> Forza reintento en la API | 40001 | Opcional, requiere manejo de errores en API |
| SERIALIZABLE | Igual que REPEATABLE READ, pero más restrictivo | 40001 | No recomendado por overhead |

## Recomendación del proyecto: Usar FOR UPDATE, no subir el nivel de aislamiento

### Por qué FOR UPDATE en lugar de REPEATABLE/SERIALIZABLE:

1. **Bloqueo acotado a las filas necesarias**: FOR UPDATE bloquea solo las filas que se van a modificar, no toda la transacción.
2. **Menos reintentos**: En REPEATABLE READ/SERIALIZABLE, cualquier modificación concurrenta obliga a reintentar toda la operación de venta.
3. **Mensajes de negocio claros**: El bloqueo con FOR UPDATE produce un wait natural que la API puede detectar y traducir a un mensaje "stock temporalmente no disponible, por favor reintente".
4. **Rendimiento**: Los niveles de serialización tienen overhead mayor en sistemas concurridos.

### Capas de defensa del proyecto (orden de importancia):

1. **FOR UPDATE (SELECT ... FOR UPDATE)** - Capa principal: Evita que dos sesiones compitan por la misma fila. Es la solución elegida por el enunciado.
2. **CHECK `cantidad >= 0`** - Capa secundaria: Actúa como última barrera si somehow el bloqueo falla o se omite. Devuelve error 23514 con mensaje claro.
3. **Trigger de validación RN-09** - Capa de negocio: El trigger `trg_renglon_comprobante_antes` lee el stock actual con su propio lógica. **Ojo**: si el trigger lee stock **sin FOR UPDATE**, podría permitir la doble venta. La solución es que el trigger o el procedimiento usen `SELECT ... FOR UPDATE` interno.
4. **Manejo de 40001 en API** - Capa de infraestructura: Si se usa REPEATABLE READ, la API debe capturar SQLSTATE 40001 y traducirlo a 503 con mensaje de reintento.

## Cómo repetirlo a mano con dos terminales

### Paso a paso (usando dos terminales o sesiones psql):

**Terminal 1 (Sesión A):**
```bash
docker compose exec -T db psql -U owner_bodegas -d bodegas_atuel <<'EOSQL'
BEGIN;
SELECT cantidad FROM stock_sala WHERE id_sala = 7 AND cod_vino = 9 FOR UPDATE;
-- El comando se queda esperando si la sesión B ya comenzó su bloqueo, o prosigue si B aún no empezó
PERFORM pg_sleep(5);
UPDATE stock_sala SET cantidad = cantidad - 1 WHERE id_sala = 7 AND cod_vino = 9;
COMMIT;
EOSQL
```

**Terminal 2 (Sesión B - inmediatamente después):**
```bash
docker compose exec -T db psql -U owner_bodegas -d bodegas_atuel <<'EOSQL'
BEGIN;
SELECT cantidad FROM stock_sala WHERE id_sala = 7 AND cod_vino = 9 FOR UPDATE;
-- Este comando se quedará ESPERANDO a que la Terminal 1 haga COMMIT
-- Si la Terminal 1 ya confirmó, este comando retornará inmediatamente con el valor actual
PERFORM pg_sleep(1);
ROLLBACK;
EOSQL
```

### Marcadores de captura recomendados:

| Marca | Qué capturar | Cuándo |
|-------|--------------|--------|
| **[CAPTURA 1]** | Terminal 1: `BEGIN;` + `SELECT ... FOR UPDATE` iniciado | Inmediatamente después de ejecutar el comando en la Terminal 1 |
| **[CAPTURA 2]** | Terminal 2: `SELECT ... FOR UPDATE` bloqueado (cursor parpadeando, sin retorno) | Inmediatamente después de ejecutar el comando en la Terminal 2 (mientras A aún no ha hecho COMMIT) |
| **[CAPTURA 3]** | Terminal 1: `COMMIT;` + el retorno de la Terminal 2 que muestra `cantidad = 0` | Después de que la Terminal 1 confirme y la Terminal 2 retorne |
| **[CAPTURA 4]** (opcional) | Query a `pg_stat_activity` mostrando el lock: `SELECT pid, state, wait_event_type, wait_event FROM pg_stat_activity WHERE wait_event_type = 'Lock';` | Durante el estado de espera de la Terminal 2 |

## Evidencia en pg_stat_activity y pg_locks

### Consultas para el informe:

**Desde una tercera conexión (o después de que A confirme):**

```sql
-- Ver sesiones activas y esperas
SELECT pid, state, wait_event_type, wait_event, client_addr 
FROM pg_stat_activity 
WHERE state != 'Idle' 
ORDER BY wait_event_type;
```

**Resultado esperado cuando B espera:**
```
 pid | state   | wait_event_type | wait_event       | client_addr
-----+---------+-----------------+------------------+-------------
 1001 | active  | Lock            | LockBuffer       | <host>
```
*(El PID 1001 correspondería a la sesión B, esperando el lock sostenido por la sesión A)*

**Desde `pg_locks`:**

```sql
SELECT locktype, databaseid, relation, page, tuple, virtualxid, transactionid, mode, granted 
FROM pg_locks 
WHERE NOT granted = true 
ORDER BY mode;
```

**Resultado esperado:**
```
 locktype | databaseid | relation | page | tuple | virtualxid | transactionid | mode      | granted
----------+------------+----------+------+-------+------------+---------------+-----------+--------
 relation | ...        | ...      | ...  | ...   | ...        | ...           | ExclusiveLock | false
```
*(Un lock Exclusive no otorgado, correspondiente a la fila de stock_sala sostenido por la sesión A)*

## Resumen comparativo

| Escenario | Bloqueo | Aislamiento | Resultado stock | Ventas registradas | SQLSTATE | ¿Se vendió de más? |
|-----------|---------|-------------|-----------------|-------------------|----------|-------------------|
| 1. CON FOR UPDATE | Sí (fila) | READ COMMITTED | 0 (correcto) | 1 | - | No |
| 2a. SIN FOR UPDATE (lost update) | No | READ COMMITTED | 0 (por suerte) | 2 | - | Sí (lógicamente) |
| 2b. SIN FOR UPDATE (UPDATE relativo) | No | READ COMMITTED | Error 23514 (constraint) | 0 o 1 dependiendo | 23514 | No (por constraint) |
| 3. REPEATABLE READ | Sí (fila) | REPEATABLE READ | 0 o error | 0 o reintento | 40001 | No (o error forzado) |

## Observaciones para los roles

### Rol Datos:
- El trigger `trg_renglon_comprobante_antes` (RN-09) lee el stock con `fn_stock_sala()`. **Si este trigger lee el stock sin hacer `SELECT ... FOR UPDATE` interno, podría permitir la doble venta.** Se recomienda agregar `SELECT ... FOR UPDATE` dentro del trigger o el procedimiento que valida el stock antes de permitir el INSERT de renglón de comprobante.
- El procedimiento `sp_procesar_transferencia` ya usa `SELECT ... FOR UPDATE` en la cabecera de transferencia, lo cual es consistente con el patrón de bloqueo necesario.

### Rol API:
- La API debe estar preparada para manejar el caso donde `SELECT ... FOR UPDATE` hace que la sesión espere.
- Si se usa REPEATABLE READ, la API debe capturar SQLSTATE 40001 y traducirlo a error 503 con mensaje: "Stock concurrente, por favor intente de nuevo en instantes".
- La capa de CHECK `cantidad >= 0` en `stock_sala` es esencial como última barrera de seguridad, pero su mensaje técnico ("check constraint violated") no es amigable para el usuario final; el frontend debe traducirlo.

## Archivos de esta entrega

| Archivo | Descripción |
|---------|-------------|
| `scripts/concurrency_demo/sesion_a.sql` | Script de la sesión A (bloqueo FOR UPDATE) |
| `scripts/concurrency_demo/sesion_b.sql` | Script de la sesión B (intento de bloqueo después) |
| `scripts/concurrency_demo/run_demo.sh` | Script runner que lanza ambas sesiones en paralelo |
| `docs/concurrencia_demo.md` | Este documento con toda la documentación detallada |

## Cómo repetir la demo completa:

```bash
# 1. Asegurarse de que los datos de demo estén en la base
# 2. Ejecutar: bash scripts/concurrency_demo/run_demo.sh
# 3. Revisar los outputs en consola y las capturas en [CAPTURA 1]-[CAPTURA 3]
# 4. Restablecer el estado: UPDATE stock_sala SET cantidad = 1 WHERE id_sala = 7 AND cod_vino = 9;
```