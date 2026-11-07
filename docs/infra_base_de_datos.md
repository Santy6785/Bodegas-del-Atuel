# Infraestructura de Base de Datos - Bodegas del Atuel

Este documento describe la configuración, ejecución, verificación y políticas de seguridad para el servicio de base de datos relacional PostgreSQL del sistema vitivinícola **Bodegas del Atuel** (UTN FRSR).

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
   > El archivo `.env` **NUNCA** debe commitearse ni subirse al repositorio. Está listado en `.gitignore`.

2. **Levantar los servicios:**
   ```bash
   docker compose up -d
   ```
   El contenedor `bodegas-db` se inicializará en segundo plano con PostgreSQL 16.

3. **Verificar la base de datos automáticamente:**
   ```bash
   ./scripts/verify_db.sh
   # O en Windows mediante Git Bash:
   bash scripts/verify_db.sh
   ```

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

## 🔄 Cómo Reiniciar la Base desde Cero

Para restablecer la base de datos a un estado limpio:
```bash
docker compose down -v
docker compose up -d
```

### ¿Por qué hace falta `down -v`?
PostgreSQL persiste sus datos en el volumen nombrado. Para recrear la base desde cero y reaplicar migraciones sobre un esquema vacío, es necesario destruir dicho volumen mediante `docker compose down -v`.

---

## 🔌 Conexión a la Base de Datos

### 1. Vía CLI con `psql` (dentro del contenedor)
```bash
docker compose exec -it db psql -U owner_bodegas -d bodegas_atuel
```

### 2. Vía Clientes Gráficos (DBeaver / pgAdmin / DataGrip)
- **Host:** `localhost` (o `127.0.0.1`)
- **Port:** Valor de `${DB_PORT:-5432}` (por defecto `5432`)
- **Database:** `bodegas_atuel`
- **Username:** `owner_bodegas`
- **Password:** El valor configurado en `POSTGRES_PASSWORD` en tu `.env`
