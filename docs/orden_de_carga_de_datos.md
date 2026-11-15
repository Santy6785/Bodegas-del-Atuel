# Orden de Carga de Datos según Dependencias de Claves Foráneas

Para garantizar la integridad referencial y evitar errores de violación de claves foráneas (Foreign Key) durante la ejecución de la carga masiva, el poblamiento de la base de datos `Bodegas del Atuel` se estructura en nueve niveles jerárquicos consecutivos, respetando exactamente las `REFERENCES` definidas en `db/migrations/001_esquema.sql` (30 tablas).

## Niveles de Dependencia y Orden de Ejecución

### Nivel 1: Entidades independientes (sin claves foráneas)
Estas tablas no poseen dependencias foráneas y constituyen el fundamento maestro del sistema:
- `departamento`: Departamentos geográficos de referencia.
- `cepa`: Catálogo de variedades de uva (tintas y blancas).
- `maridaje`: Catálogo de opciones de maridaje y temperatura de servicio.
- `transportista`: Empresas de transporte de mercadería.
- `bodega`: Bodegas productoras del grupo.

### Nivel 2: Entidades geográficas y de producción primaria base
Dependen estrictamente del Nivel 1:
- `localidad`: Depende de `departamento` (`codigo_postal`). Define también el encargado regional.
- `finca`: Depende de `departamento` (`id_departamento`).

### Nivel 3: Unidades operativas y parcelarias
Dependen del Nivel 1 y 2:
- `sala_venta`: Depende de `localidad` (`codigo_postal`).
- `parcela`: Entidad débil que depende de `finca` (`id_finca`, `nro_parcela`) y `cepa` (`id_cepa`).
- `empleado`: Depende de `sala_venta` (`id_sala`). Clave primaria `cuit`.

### Nivel 4: Cosecha y origen de uva
- `lote_uva`: Depende de `parcela` (`id_finca`, `nro_parcela`) y `bodega` (`cuit_bodega`).
- `analisis_calidad`: Depende de `lote_uva` (`id_lote`). Clave primaria compuesta (`id_lote`, `fecha`, `hora`).

### Nivel 5: Elaboración de vinos
- `vino`: Depende de `bodega` (`cuit_bodega`).

### Nivel 6: Relaciones N:M, trazabilidad y stock central
- `vino_cepa` (composición): Depende de `vino` (`cod_vino`) y `cepa` (`id_cepa`).
- `vino_maridaje`: Depende de `vino` (`cod_vino`) y `maridaje` (`id_maridaje`).
- `vino_lote` (trazabilidad): Depende de `vino` (`cod_vino`) y `lote_uva` (`id_lote`).
- `stock_deposito`: Depende de `vino` (`cod_vino`). Stock del depósito central (una fila por vino).
- `auditoria_precio`: Depende de `vino` (`cod_vino`). Registra cambios de precio.

### Nivel 7: Clientes, subtipos, permisos y cobertura de transportistas
- `cliente`: Depende de `localidad` (`codigo_postal`). Supertipo con discriminador `tipo_cliente`.
- `cliente_distribuidor`: Depende de `cliente` (`id_cliente`). Subtipo 1:1.
- `cliente_exportador`: Depende de `cliente` (`id_cliente`). Subtipo 1:1.
- `permiso_exportacion`: Depende de `cliente_exportador` (`id_cliente`). Entidad débil del exportador (no del supertipo `cliente`).
- `transportista_localidad`: Depende de `transportista` (`cod_transportista`) y `localidad` (`codigo_postal`). N:M de cobertura (nombre correcto en el esquema: `transportista_localidad`, no `transportista_cubre_localidad`).

### Nivel 8: Movimientos de mercadería y stock en salas
- `ingreso`: Depende de `transportista` (`cod_transportista`) y `bodega` (`cuit_bodega`).
- `renglon_ingreso`: Depende de `ingreso` (`cod_ingreso`) y `vino` (`cod_vino`).
- `transferencia`: Depende de `sala_venta` (`id_sala`).
- `renglon_transferencia`: Depende de `transferencia` (`nro_transferencia`) y `vino` (`cod_vino`).
- `stock_sala`: Depende de `sala_venta` (`id_sala`) y `vino` (`cod_vino`). N:M sala-vino con cantidad.

### Nivel 9: Transacciones de venta finales
- `comprobante`: Depende de `cliente` (`id_cliente`) y `sala_venta` (`id_sala`).
- `renglon_comprobante`: Depende de `comprobante` (`nro_comprobante`) y `vino` (`cod_vino`). N:M comprobante-vino con atributos.

## Justificación de la Estrategia

Respetar esta jerarquía permite insertar registros en orden de dependencia foránea sin requerir la desactivación de restricciones de claves foráneas. La estrategia de `seed.py` complementa esto desactivando únicamente los triggers de negocio (no las FK nativas) para los cálculos de stock y totales, como se documenta en `docs/carga-triggers.md`.

## Implementación en `db/seed/seed.py`

`db/seed/seed.py` ejecuta toda la carga en **una sola transacción** (`BEGIN` … `COMMIT`). Si cualquier paso falla (incluido el gate `02b_gate.sql`), se ejecuta `ROLLBACK` y los 15 triggers de usuario quedan intactos en `'O'`.

El orden real de inserción dentro de la transacción es:

1. **`01_pre_carga.sql`**: deshabilita los triggers críticos de stock/estado/fecha (7 triggers de usuario).
2. **Catálogos desde CSV** (`insertar_catalogos`): `departamento`, `localidad`, `bodega`, `cepa`, `maridaje` (IDs reales de los archivos CSV).
3. **Datos maestros** (`insertar_maestros`): `finca`, `parcela`, `lote_uva`, `vino`, `vino_cepa`, `vino_maridaje`, `vino_lote` (trazabilidad).
4. **Clientes** (`insertar_clientes`): `cliente` (200 filas) + subtipos `cliente_distribuidor` / `cliente_exportador` + `permiso_exportacion`.
5. **Salas y transportistas** (`insertar_salas_y_transportistas`): `sala_venta` (15), `transportista` (6), `transportista_localidad`.
6. **Stock inicial** (`poblar_stock`): `stock_deposito` (una fila por vino) y `stock_sala` (una fila por par sala-vino).
7. **Movimientos de stock** (`poblar_movimientos_stock`): `ingreso` + `renglon_ingreso` (40 ingresos) y `transferencia` + `renglon_transferencia` (600 transferencias) que justifican el stock inicial.
8. **Ventas masivas** (`generar_ventas`): `comprobante` (170000, INSERT por lotes) y `renglon_comprobante` (680046, vía `COPY`).
9. **Recálculo de totales** (`recalcular_totales_comprobante`): actualiza `subtotal`/`descuento`/`total` de `comprobante` mientras los triggers siguen deshabilitados.
10. **`03_post_carga.sql`**: habilita triggers, valida `tgenabled='O'`, ajusta secuencias con `setval`, `REFRESH MATERIALIZED VIEW`, `ANALYZE`.
11. `SET CONSTRAINTS ALL IMMEDIATE` (forza los constraint triggers diferidos `ctg_*`).
12. **`02b_gate.sql`**: gate de integridad; aborta si algún control devuelve filas.
13. **`COMMIT`** único al final.

**Tablas del esquema no cargadas por `seed.py` (pendientes para la demo):** `empleado`, `analisis_calidad` y `auditoria_precio`. Están definidas en `001_esquema.sql` con sus FKs, pero `seed.py` no las pobla; se dejan para una fase posterior de demostración.

## Volúmenes de referencia (Corrida 1 verificada)

- Comprobantes: 170000
- Renglones de comprobante: 680046
- Duración total: ~97 s (gate `02b_gate.sql`: ~31 s)
- Triggers de usuario deshabilitados al final: 0 (debe ser 0)
