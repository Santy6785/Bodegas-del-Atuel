# Infraestructura de Base de Datos - Bodegas del Atuel (Issue #31)

Este documento describe la configuración, ejecución y verificación del servicio de base de datos relacional PostgreSQL para el sistema vitivinícola **Bodegas del Atuel** (UTN FRSR).

---

## 📋 Requisitos Previos

- **Docker**: versión 20.10 o superior (compatible con Linux Engine en Docker Desktop / Docker Engine).
- **Docker Compose**: versión v2 o superior (comando `docker compose`).
- Entorno bash (Git Bash, WSL o terminal Linux/macOS) para la ejecución de scripts.

---

## 🚀 Pasos para Levantar el Entorno Local

1. **Configurar las variables de entorno:**
   Copiar la plantilla de variables de entorno y editar los valores requeridos (especialmente `POSTGRES_PASSWORD`):
   ```bash
   cp .env.example .env
   ```
   *Nota:* El archivo `.env` nunca debe commitearse ni subirse al repositorio. Está listado en `.gitignore`.

2. **Levantar el contenedor de PostgreSQL:**
   ```bash
   docker compose up -d
   ```
   El contenedor `bodegas-db` se descargará e inicializará en segundo plano.

3. **Verificar la base de datos automáticamente:**
   ```bash
   ./scripts/verify_db.sh
   # O en Windows mediante Git Bash:
   bash scripts/verify_db.sh
   ```
   El script esperará a que el contenedor alcance el estado `healthy`, revisará que los logs no contengan líneas de `ERROR`, y listará las tablas, tipos y restricciones creadas.

---

## 🔄 Cómo Reiniciar la Base desde Cero (y por qué hace falta)

Para restablecer la base de datos a un estado limpio:
```bash
docker compose down -v
docker compose up -d
```

### ¿Por qué hace falta `down -v`?
La imagen oficial de PostgreSQL ejecuta los scripts situados en `/docker-entrypoint-initdb.d` en orden alfabético (`001_esquema.sql`, `002_constraints.sql`, etc.) **únicamente cuando el directorio de datos (`/var/lib/postgresql/data`) está completamente vacío**.

Si el volumen de datos nombrado (`pgdata`) ya existe y contiene datos, PostgreSQL muestra en los logs:
```text
PostgreSQL Database directory appears to contain a database; Skipping initialization
```
y **no vuelve a ejecutar las migraciones**. Por lo tanto, cualquier cambio o prueba que requiera recrear el esquema desde cero debe destruir el volumen previo mediante `docker compose down -v`.

---

## 🔌 Conexión a la Base de Datos

### 1. Vía CLI con `psql` (dentro del contenedor)
```bash
docker compose exec -it db psql -U owner_bodegas -d bodegas_atuel
```
*(O utilizando las variables definidas en tu archivo `.env`).*

### 2. Vía Clientes Gráficos (DBeaver / pgAdmin / DataGrip)
- **Host:** `localhost` (o `127.0.0.1`)
- **Port:** Valor de `${DB_PORT:-5432}` (por defecto `5432`)
- **Database:** `bodegas_atuel`
- **Username:** `owner_bodegas`
- **Password:** El valor configurado en `POSTGRES_PASSWORD` en tu `.env`

---

## ⚠️ Problemas Comunes y Soluciones

### 1. Puerto 5432 ocupado
- **Causa:** Hay un servicio de PostgreSQL local corriendo en la máquina host.
- **Solución:** En el archivo `.env`, cambiar la variable `DB_PORT` por otro puerto disponible (ej. `DB_PORT=5433`). La sintaxis `${DB_PORT:-5432}:5432` mapeará el puerto externo sin alterar el puerto interno del contenedor.

### 2. Las migraciones no se re-ejecutan al modificar archivos `.sql`
- **Causa:** El volumen nombrado `pgdata` ya contiene una base inicializada.
- **Solución:** Destruir el volumen y reiniciar: `docker compose down -v && docker compose up -d`.

### 3. Error de finales de línea CRLF en scripts `.sh` en Windows
- **Causa:** Windows suele clonar o editar archivos con terminación de línea `CRLF` (`\r\n`), lo que provoca fallos como `/bin/bash^M: bad interpreter` dentro de entornos UNIX o contenedores.
- **Solución:** El repositorio cuenta con `.gitattributes` con la regla `*.sh text eol=lf`. Asegurate de que tu editor (VS Code, Notepad++, etc.) guarde los archivos `.sh` con terminación `LF`.

---

## 📊 Resultado de la Verificación

Resultados obtenidos tras aplicar secuencialmente `001_esquema.sql` y `002_constraints.sql` sobre un volumen vacío:

| Objeto / Categoría | Cantidad Encontrada | Detalle / Observaciones |
|---|---|---|
| **Tablas en esquema `public`** | **30** | Todas las tablas de negocio, dimensiones, transacciones y auditoría. |
| **Tipos y Dominios (`\dT`)** | **7** | `cuit_dom` (dominio CUIT 11 dígitos), `tipo_cepa`, `tipo_vino`, `dia_semana`, `tipo_cliente`, `tipo_documento`, `estado_documento`. |
| **PRIMARY KEY (`p`)** | **30** | Una clave primaria definida por cada una de las 30 tablas. |
| **FOREIGN KEY (`f`)** | **36** | Integridad referencial con acciones `ON DELETE` / `ON UPDATE` según RN. |
| **CHECK (`c`)** | **21** | Reglas de negocio sobre montos, porcentajes, saldos y rangos válidos. |
| **UNIQUE (`u`)** | **9** | Restricciones de unicidad para claves alternativas de negocio. |
