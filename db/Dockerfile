# =====================================================================
# Dockerfile del servicio db - PostgreSQL 16
#
# Imagen base oficial postgres:16, extendida para copiar:
#   - el script de inicializacion en /docker-entrypoint-initdb.d/
#   - las migraciones de db/migrations/ en /migrations/
#
# Al iniciar el contenedor con el volumen de datos vacio, la imagen oficial
# ejecuta los scripts de /docker-entrypoint-initdb.d, que aplican las
# migraciones en orden numerico sobre la base recién creada.
# =====================================================================

FROM postgres:16

# Script que aplica las migraciones en orden numerico al crear el contenedor.
COPY init/00-apply-migrations.sh /docker-entrypoint-initdb.d/00-apply-migrations.sh

# Migraciones SQL (disponibles para el script de inicializacion)
COPY migrations/ /migrations/

# Asegurar bit de ejecucion del script de inicializacion (en cualquier SO)
RUN chmod +x /docker-entrypoint-initdb.d/00-apply-migrations.sh
