# Verificación de Conexión Exclusiva como `app_rw` bajo Carga (Issue #72)

## 1. Resumen de Prueba
- **Base de datos evaluada:** `bodegas_atuel_bench` (`20.000` clientes cargados, con permisos mínimos aplicados desde `db/migrations/007_roles.sql`).
- **Servicio auditado:** Contenedor `bodegas-api` (`uvicorn`, pool `psycopg_pool` con `application_name = 'bodegas-api'`).
- **Script:** `scripts/perf/verificar_app_rw_carga.py` (**4/4 comprobaciones PASS**).
- **Carga generada:** `320` peticiones HTTP `GET` distribuidas en `16` hilos concurrentes (`21,45 s`, `14,9 req/s`) sobre `/salud`, `/clientes`, `/vinos`, `/reportes/top-vinos`, `/reportes/vinos-sin-stock`, `/reportes/transportista-activo` y `/reportes/ventas-por-sala`.

## 2. Resultados HTTP bajo Concurrencia
| Métrica | Valor observado |
| :--- | :--- |
| Peticiones totales | `320` |
| Respuestas `200 OK` | `320` (`100%`) |
| Errores de permisos (`42501` / `500`) | `0` |
| Latencia `p50` | `626,8 ms` |
| Latencia `p95` | `3020,8 ms` |
| Latencia máxima | `7064,6 ms` |

## 3. Auditoría de `pg_stat_activity` durante la Carga
| Indicador | Resultado |
| :--- | :--- |
| Muestras tomadas en paralelo | `16` |
| Observaciones totales de sesiones (`bodegas-api`) | `179` (`142 active`, `34 idle`, `3 idle in transaction`) |
| PIDs distintos observados en el pool | `38` |
| Pico de conexiones simultáneas | `17` |
| Roles (`usename`) detectados | `{'app_rw': 179}` (**100% `app_rw`**) |
| Conexiones como `owner_bodegas` o `postgres` | `0` |

## 4. Hallazgos y Resolución
- **Alineación de permisos por base de datos:** Al ejecutar la prueba inicialmente contra `bodegas_atuel_bench`, se detectaron errores `SQLSTATE 42501` (`insufficient_privilege`) porque los privilegios de `db/migrations/007_roles.sql` (que en PostgreSQL tienen alcance por base de datos) solo habían sido aplicados en `bodegas_atuel`.
- **Confirmación de mínimo privilegio:** Tras aplicar `007_roles.sql` en `bodegas_atuel_bench`, el 100% de las peticiones a tablas, vistas (`vw_stock_total_vino`), funciones (`fn_descuento_cliente`) y endpoints de reporte respondieron `200 OK` operando exclusivamente bajo el rol restringido `app_rw`.
