# Pruebas de Modificaciones en Transacción (Issue #103)

Todas las sentencias de modificación (INSERT, UPDATE y DELETE) se probaron en PostgreSQL 16 (bodegas_atuel_bench) siguiendo el flujo transaccional: BEGIN -> control previo -> sentencia -> control posterior -> ROLLBACK.

El uso de ROLLBACK garantiza que la base de datos quede exactamente en su estado inicial tras verificar el impacto de cada operación y sus triggers asociados.

## Resumen de filas afectadas

| ID | Script | Operación | Tabla principal | Filas afectadas (DML) | Efecto colateral / Trigger verificado |
|---|---|---|---|---:|---|
| **I1** | consultas/insert.sql | INSERT | ingreso + renglon_ingreso | 1 + 1 | Alta en en_confeccion con detalle válido (RN-12) |
| **I2** | consultas/insert.sql | INSERT | comprobante + renglon_comprobante | 1 + 1 | Calcula totales de cabecera y descuenta 6 botellas de stock_sala (43054 -> 43048) |
| **I3** | consultas/insert.sql | INSERT | permiso_exportacion | 1 | trg_permiso_u6_descuento sube porcentaje_descuento de 30.00 % a 35.00 % al pasar de 3 a 4 permisos (id_cliente = 5) |
| **U1** | consultas/update.sql | UPDATE | vino | 1 | trg_vino_auditoria inserta 1 fila en auditoria_precio (1572.28 -> 2072.28) |
| **U2** | consultas/update.sql | UPDATE | ingreso | 1 (x2 pasos) | Transición en_confeccion -> terminado -> procesado (RN-10) sin pendientes residuales |
| **U3** | consultas/update.sql | UPDATE | bodega | 1 | ON UPDATE CASCADE propaga el nuevo CUIT a los 9 vinos de Bodega Norton |
| **U4** | consultas/update.sql | UPDATE | cliente | 26 | Actualiza las 26 direcciones registradas bajo codigo_postal = 5561 |
| **U5** | consultas/update.sql | UPDATE | transferencia | 1 (x2 pasos) | Transición en_confeccion -> terminado -> procesado (RN-10) |
| **U6-R** | consultas/select.sql | SELECT | cliente_exportador | -- (lectura) | Reformulada el 2026-11-08 a consulta de lectura derivada de permiso_exportacion |
| **D1** | consultas/delete.sql | DELETE | comprobante | 1 | ON DELETE CASCADE elimina los 3 registros asociados en renglon_comprobante (nro_comprobante = 1) |
| **D2** | consultas/delete.sql | DELETE | permiso_exportacion | 1 | trg_permiso_u6_descuento baja porcentaje_descuento de 35.00 % a 30.00 % al pasar de 4 a 3 permisos (id_cliente = 3) |
| **D3** | consultas/delete.sql | DELETE | cepa | 1 | Elimina una cepa sin parcelas implantadas (las cepas con parcelas están protegidas por ON DELETE RESTRICT) |
