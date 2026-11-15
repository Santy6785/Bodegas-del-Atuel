db/seed/README.md

# seed.py - Carga masiva deterministica de Bodegas del Atuel

## Que hace seed.py

Ejecuta EXCLUSIVAMENTE sobre la base descartable `bodegas_atuel_bench` (nunca sobre `bodegas_atuel`).

Toda la carga corre en UNA SOLA transaccion:
1. Verifica migraciones y usuario owner_bodegas.
2. Ejecuta 01_pre_carga.sql (deshabilita solo los triggers críticos de negocio de stock/estado/fecha; las FK y CHECK nativas quedan activas).
3. Carga catálogos reales desde CSV (departamento, localidad, bodega, cepa, maridaje).
4. Carga datos maestros: fincas, parcelas, lotes de uva, vinos, composición, maridaje, trazabilidad.
5. Carga clientes (20000) con subtipos y permisos de exportación.
6. Carga salas y transportistas.
7. Carga empleados (150) y análisis de calidad.
8. Aplica cambios de precio en los primeros 5 vinos (trigger auditoria_precio activo).
9. Poblado de stock inicial (depósito + salas).
10. Movimientos de stock que justifican el stock inicial (ingresos y transferencias de 2018).
11. Movimientos recientes con estados mixtos para poblar S4, S5, S7 e I1.
12. Ventas masivas: 170000 comprobantes + 680366 renglones (COPY para renglones).
13. Recalcula totales de comprobante.
14. Ejecuta 03_post_carga.sql (habilita triggers, valida tgenabled='O', setval de secuencias, REFRESH MATERIALIZED VIEW, ANALYZE).
15. SET CONSTRAINTS ALL IMMEDIATE.
16. Ejecuta 02b_gate.sql (gate de integridad; aborta si algún control devuelve filas).
17. COMMIT único al final.

Si cualquier paso falla (incluido 02b_gate.sql), se ejecuta ROLLBACK automático y los 15 triggers de usuario quedan intactos en 'O'.

## Como ejecutarlo

```powershell
docker compose run --rm -e PGDATABASE=bodegas_atuel_bench seed python -u seed.py
```

## Variables de entorno

- PGDATABASE: nombre de la base de datos (por defecto bodegas_atuel_bench).
- FECHA_REF_ISO: fecha de referencia determinística en ISO (por defecto 2026-11-14). Nunca usa date.today().
- PGUSER: usuario de conexión (por defecto owner_bodegas).
- PGHOST: host de conexión (vacío => socket local de Unix).
- PGPORT: puerto (por defecto 5433).
- PGPASSWORD: contraseña (si aplica).

## Tiempos y volúmenes medidos

- Duración total: 244 s (versión con 20000 clientes y empleados/analistas).
- Versión base (200 clientes): 97 s.
- Comprobantes: 170000.
- Renglones de comprobante: 680366 (versión 20000 clientes) / 680046 (versión 200 clientes).
- Clientes: 20000.
- Empleados: 150.
- Gate 02b_gate.sql: 37 s (versión 20000 clientes) / 31 s (versión base).

## Como correr los controles

```powershell
docker exec bodegas-db sh -c "rm -rf /tmp/sql"
docker cp db\seed\sql bodegas-db:/tmp/sql
docker exec -w /tmp bodegas-db psql -U owner_bodegas -d bodegas_atuel_bench -f /tmp/sql/02_controles.sql 2>&1 | Out-File C:\Users\lauta\controles.txt -Encoding utf8
Select-String -Path C:\Users\lauta\controles.txt -Pattern "^\(\d+ rows?\)"
```

Todos los controles deben devolver `(0 rows)` salvo C2 (`(30 rows)`).

## Como generar y restaurar el volcado completo

Generar el volcado (dentro del contenedor, rutas /tmp/):

```powershell
docker exec bodegas-db sh -c "pg_dump -U owner_bodegas -d bodegas_atuel_bench | gzip > /tmp/dump_completo.sql.gz"
docker cp bodegas-db:/tmp/dump_completo.sql.gz C:\Users\lauta\dump_completo.sql.gz
```

Restaurar en una base nueva:

```powershell
docker exec bodegas-db psql -U owner_bodegas -d postgres -c "CREATE DATABASE bodegas_atuel_restore;"
docker exec bodegas-db sh -c "gunzip -c /tmp/dump_completo.sql.gz | psql -U owner_bodegas -d bodegas_atuel_restore -v ON_ERROR_STOP=1 -q"
docker exec bodegas-db psql -U owner_bodegas -d bodegas_atuel_restore -c "SELECT count(*) FROM comprobante;"
docker exec bodegas-db psql -U owner_bodegas -d postgres -c "DROP DATABASE bodegas_atuel_restore;"
```

## Aclaración sobre dump_completo.sql.gz

El archivo dump_completo.sql.gz no se sube al repositorio. Si supera los 20 MB, se ignora en .gitignore y se regenera con los comandos anteriores cada vez que sea necesario.

## Limitacion conocida
- En `db/seed/catalogos/localidad.csv`, General Alvear figura con codigo postal `5505` (su codigo postal real es `5620`). Toda la carga (`cliente` y `transportista_localidad`) es internamente consistente con `5505` y las consultas que filtran por nombre de localidad funcionan sin inconvenientes.
