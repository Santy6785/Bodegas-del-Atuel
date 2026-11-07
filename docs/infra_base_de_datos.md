# Infraestructura de Base de Datos - Bodegas del Atuel

Este documento describe la configuración, ejecución, verificación, migración y políticas de seguridad para el servicio de base de datos relacional PostgreSQL del sistema vitivinícola **Bodegas del Atuel** (UTN FRSR).

---

## 📋 Requisitos Previos

- **Docker**: versión 20.10 o superior (compatible con Linux Engine en Docker Desktop / Docker Engine).
- **Docker Compose**: versión v2 o superior (comando `docker compose`).
- Entorno bash (Git Bash, WSL o terminal Linux/macOS) para la ejecución de scripts.

---

## 🚀 Pasos para Levantar el Entorno Local

1. **Configurar las variables de entorno:**
   Copiar la plantilla de variables de entorno y editar los valores requeridos (especialmente `POSTGRES_PASSWORD` y `DB_PASSWORD`):
   ```bash
   cp .env.example .env
   ```
   > [!IMPORTANT]
   > El archivo `.env` **NUNCA** debe commitearse ni subirse al repositorio. Está expresamente excluido en `.gitignore`.

2. **Levantar el contenedor de PostgreSQL:**
   ```bash
   docker compose up -d
   ```
   El contenedor `bodegas-db` se descargará e inicializará en segundo plano con una base de datos vacía lista para recibir las migraciones.

3. **Aplicar las migraciones:**
   ```bash
   ./scripts/migrate.sh
   # O en Windows mediante Git Bash:
   bash scripts/migrate.sh
   ```
   Aplica en orden estricto (alfabético/numérico) todos los scripts de `db/migrations/`, deteniéndose de inmediato ante cualquier error (`ON_ERROR_STOP=1`) y garantizando atomicidad por archivo (`--single-transaction`).

4. **Verificar la base de datos:**
   ```bash
   ./scripts/verify_db.sh
   # O en Windows mediante Git Bash:
   bash scripts/verify_db.sh
   ```
   El script revisará que el contenedor reporte estado `healthy`, confirmará que los logs no contengan líneas de `ERROR`, y listará las tablas, tipos y restricciones creadas.

---

## ⚙️ Aplicar Migraciones (`scripts/migrate.sh`)

El script `scripts/migrate.sh` es la herramienta centralizada y determinística para aplicar cambios estructurales en la base de datos de manera uniforme tanto en local como en entornos remotos.

### Modos de Conexión

#### 1. Modo Docker (Local por defecto)
Al ejecutarse sin argumentos o sin la variable `DATABASE_URL`, el script interactúa directamente con el contenedor PostgreSQL definido en `docker-compose.yml`:
```bash
./scripts/migrate.sh
```
Lee automáticamente las variables `POSTGRES_USER` y `POSTGRES_DB` desde `.env` y canaliza cada archivo SQL por stdin al comando `psql` dentro del contenedor.

#### 2. Modo Directo (Nube o Servidor Remoto)
Pensado para bases de datos administradas en la nube (AWS RDS, Neon, Supabase, Railway, Render, etc.):
```bash
# Vía parámetro --url:
./scripts/migrate.sh --url "postgresql://<DB_USER>:<DB_PASSWORD>@<DB_HOST>:<DB_PORT>/<DB_NAME>?sslmode=require"

# O mediante variable de entorno:
export DATABASE_URL="postgresql://<DB_USER>:<DB_PASSWORD>@<DB_HOST>:<DB_PORT>/<DB_NAME>?sslmode=require"
./scripts/migrate.sh
```
* **Enmascaramiento de seguridad:** La consola **nunca** imprime contraseñas ni la URL completa; en la salida sólo se visualizan el host y el nombre de la base de datos (`Host: <DB_HOST>:<DB_PORT> | Base: <DB_NAME>`).

### Opciones Disponibles
- `--dir <carpeta>`: Permite indicar un directorio alternativo de migraciones (por defecto `db/migrations`, muy útil para suites de pruebas o migraciones parciales).
- `--url <cadena>`: Define la cadena de conexión para el modo directo.
- `-h, --help`: Muestra la ayuda y opciones disponibles.

### Comportamiento ante Fallos y Lectura de Errores
- Cada migración se ejecuta con `-v ON_ERROR_STOP=1` y `--single-transaction` (`-1`).
- Si un archivo contiene un fallo de sintaxis, referencia inválida o violación de restricción:
  1. PostgreSQL aborta inmediatamente la transacción de ese archivo, evitando cambios a medias o esquemas corruptos.
  2. `migrate.sh` muestra en pantalla el error exacto arrojado por PostgreSQL.
  3. La ejecución se detiene de forma tajante: **ninguna migración posterior es procesada**.
  4. El script finaliza con código de salida distinto de cero (`exit 1`).

### Limitación de Idempotencia y Reinicio
> [!WARNING]
> **El script no es idempotente.** Correrlo dos veces sobre la misma base fallará en `001_esquema.sql` porque los objetos (tablas, secuencias, tipos) ya existen.
>
> Para reiniciar la base de datos local desde cero:
> ```bash
> docker compose down -v
> docker compose up -d
> ./scripts/migrate.sh
> ./scripts/verify_db.sh
> ```

### 💡 Mejora Futura Identificada
Actualmente no se mantiene una tabla de control tipo `schema_migrations` ni cálculo de checksums. Se deja asentado como mejora técnica para etapas futuras incorporar seguimiento histórico de migraciones para permitir ejecuciones idempotentes e incrementales.

---

## 🔐 Manejo de Secretos y Variables de Entorno (Issue #34)

El repositorio es de acceso público. Por exigencias académicas y de seguridad en software, **está estrictamente prohibido commitear contraseñas, credenciales o cadenas de conexión en el repositorio, incluyendo su historial**.

### 1. ¿Qué va en `.env` y qué va en `.env.example`?

| Archivo | Contenido Permitido | Control de Versiones | Propósito |
|---|---|:---:|---|
| **`.env.example`** | **Únicamente placeholders** (`cambiar_por_un_secreto`, `localhost`, nombres genéricos). | **Trackeado en Git** | Sirve como plantilla documentada de todas las variables que requiere el sistema. |
| **`.env`** | **Valores reales de desarrollo local** (contraseñas locales, puertos específicos). | **Ignorado por Git** | Contiene la configuración efectiva de ejecución del desarrollador en su máquina. |

### 2. Cómo configurar el entorno local
1. Generar el archivo `.env` a partir del ejemplo:
   ```bash
   cp .env.example .env
   ```
2. Editar `.env` y definir contraseñas seguras para desarrollo local (`POSTGRES_PASSWORD` y `DB_PASSWORD`).

### 3. Políticas de Seguridad en Entornos Nube
- **Nunca commitear contraseñas ni archivos `.env`:** En entornos de staging, testing o producción en la nube (ej. Render, Railway, AWS RDS, Neon, Supabase), las credenciales **nunca** se envían en archivos dentro del código.
- **Inyección por plataforma:** Las credenciales se configuran directamente en el panel de variables de entorno del proveedor (*Environment Variables / Secrets*).
- **Modo SSL:** En la nube es obligatorio utilizar `DB_SSLMODE=require` o incluir `sslmode=require` en la URI de conexión `DATABASE_URL`.

### 4. Protocolo ante Exposición Accidental de un Secreto
Si por error humano se llega a commitear un secreto real (contraseña, token, clave API):
1. **ROTAR EL SECRETO INMEDIATAMENTE (Paso 1 prioritario):**
   Cambiar la contraseña o revocar el token comprometido en el servicio de base de datos o proveedor inmediatamente. Eliminar el archivo del repositorio no repara el compromiso si el secreto sigue activo.
2. **Avisar al equipo:** Informar al grupo del incidente para coordinar que nadie utilice la credencial revocada.
3. **Limpieza del historial (solo con acuerdo explícito):** La reescritura del árbol de Git (`git filter-repo` / BFG) solo debe aplicarse con coordinación y respaldo previo del equipo para evitar desincronizaciones masivas.

### 5. Resultado de la Auditoría de Seguridad (Issue #34)

Se realizó un escaneo exhaustivo sobre los archivos actuales y sobre **la totalidad del historial de commits** utilizando herramientas especializadas (`gitleaks detect --log-opts="--all"` y búsquedas manuales con expresiones regulares):

| Componente / Archivo Revisado | Resultado de la Auditoría | Acción Realizada |
|---|---|---|
| **`.gitignore` (raíz)** | Faltaban reglas para `*.env`, `.env.*`, certificados (`*.pem`, `*.key`) y credenciales cloud. | **Reforzado:** Se agregaron reglas exhaustivas y ordenadas por categorías con excepción estricta para `!.env.example`. |
| **`.env.example` (raíz)** | Contenía placeholders válidos pero requería comentarios explicativos y ejemplo seguro de `DATABASE_URL`. | **Actualizado:** Documentadas todas las variables requeridas por Docker Compose, API y Frontend con placeholders seguros. |
| **Archivos `.env` trackeados** | `git ls-files` confirmó que ningún archivo `.env` real está ni estuvo trackeado en el repositorio. | **Conforme:** Únicamente `.env.example` está bajo seguimiento de Git. |
| **`docker-compose.yml`** | Todas las contraseñas utilizan interpolación obligatoria `${VAR:?mensaje}` sin valores hardcodeados. | **Conforme:** No contiene secretos en texto plano. |
| **`db/migrations/007_roles.sql`** | Archivo placeholder vacío (0 bytes). | **Conforme:** No contiene contraseñas en texto plano. |
| **`db/init/00-apply-migrations.sh`** | Utiliza la variable inyectada `-v app_password="$APP_DB_PASSWORD"`. | **Conforme:** No contiene contraseñas en texto plano. |
| **`front/config.js`** | Contiene solo la URL pública del backend (`http://localhost:8000`). | **Conforme:** No contiene tokens ni secretos. |
| **`api/app/config.py`** | Exige `db_password` desde el entorno sin valor por defecto. | **Conforme:** Diseñado bajo el principio de menor privilegio. |
| **Historial Git completo (`39 commits`)** | Gitleaks y `git log -S` verificaron 0 fugas de contraseñas reales o claves privadas. | **Conforme:** Todo el historial se encuentra limpio de secretos reales. |

---

## 🔄 Cómo Reiniciar la Base desde Cero (y por qué hace falta)

Para restablecer la base de datos a un estado limpio:
```bash
docker compose down -v
docker compose up -d
./scripts/migrate.sh
./scripts/verify_db.sh
```

### ¿Por qué hace falta `down -v`?
PostgreSQL persiste sus datos en el volumen nombrado `pgdata`. Para realizar pruebas limpias o volver a aplicar la totalidad de las migraciones sin conflictos de objetos existentes, es necesario destruir dicho volumen mediante `docker compose down -v` y levantar nuevamente el servicio antes de ejecutar `./scripts/migrate.sh`.

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
- **Solución:** Destruir el volumen y reiniciar: `docker compose down -v && docker compose up -d && ./scripts/migrate.sh`.

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
