# Bodegas-del-Atuel
Sistema de Gestión y Distribución de la empresa vitivinícola "Bodegas del Atuel"
#prueba de conexion 

## Cómo levantar con Docker

### Requisitos
- Docker y Docker Compose instalados en la máquina.
- Copiar `.env.example` a `.env` y completar los valores (contraseñas y puertos).
  NUNCA subir `.env` al repositorio (está excluido por `.gitignore`).

  ```sh
  cp .env.example .env
  # editar .env con los valores deseados
  ```

### Levantar todos los servicios (un solo comando)
```sh
docker compose up --build
```

Esto levanta:
- `db` — PostgreSQL 16 con volumen nombrado y healthcheck (`pg_isready`).
- `api` — API REST (depende de `db` con `condition: service_healthy`).
- `front` — Frontend (depende de `api`).

Al iniciar `db` con el volumen vacío, se aplican automáticamente las migraciones
de `db/migrations/` en orden numerico (001 → 007) mediante el script de
`docker-entrypoint-initdb.d`. La migracion 008 (indices) NO se aplica aqui;
debe ejecutarse aparte con `./scripts/aplicar_indices.sh`.

### Cargar datos de prueba (solo con el perfil "seed")
El servicio `seed` NO corre con `docker compose up` (usa `profiles: ["seed"]`).
Se conecta con el PROPIETARIO de la base (POSTGRES_USER/POSTGRES_PASSWORD),
porque la carga masiva puede ejecutar ALTER TABLE ... DISABLE TRIGGER.
Para ejecutarlo contra la base ya migrada:

```sh
docker compose --profile seed run --rm seed
```

### Aplicar indices (migracion 008, aparte del init automatico)
```sh
./scripts/aplicar_indices.sh
```

### Backups y restauraciones
```sh
# Backup comprimido (se genera en backups/dump_completo.sql.gz)
./scripts/backup.sh

# Restaurar el dump en una base NUEVA y verificar conteo de filas
./scripts/restore.sh backups/dump_completo.sql.gz bodegas_del_atuel_restaurado
```

### Restablecer todo desde cero (borra todos los datos)
```sh
./scripts/reset.sh
# o sin confirmación: ./scripts/reset.sh --yes
```

Este script ejecuta `docker compose down -v` (borra el volumen de PostgreSQL)
y vuelve a levantar los servicios. Las migraciones se aplican de nuevo sobre
la base vacía.

### Advertencia importante sobre el volumen de datos
Los scripts de inicialización (migraciones) solo se ejecutan cuando el volumen
de PostgreSQL está vacío (primera creación del contenedor). Si el volumen ya
contiene datos, las migraciones NO se vuelven a aplicar. Para rehacer todo
desde cero, usá `reset.sh`.

### Puertos expuestos al host
Solo se exponen los puertos necesarios:
- `db`: 5432 (necesario para scripts de backup/restore y acceso de desarrollo)
- `api`: 8000
- `front`: 5173

La comunicación interna entre servicios usa la red Docker interna `bodegas_net`.