# Bodegas del Atuel - API REST

API backend para el sistema de gestión de Bodegas del Atuel (TPI Bases de Datos, UTN San Rafael).
Construida con Python, FastAPI y el driver nativo psycopg 3. **No se utiliza ningún ORM ni query builder** (prohibido SQLAlchemy, SQLModel, Tortoise, etc.); todas las consultas se realizan con SQL nativo parametrizado.

## Estructura del proyecto
- `app/`: Código de la aplicación (configuración, db, consultas SQL nativas, routers y schemas Pydantic).
- `tests/`: Pruebas automatizadas con pytest y httpx.

## Ejecución local
1. Crear y activar entorno virtual: `python -m venv .venv` y activarlo.
2. Instalar dependencias: `pip install -r requirements.txt`.
3. Configurar variables de entorno copiando `.env.example` de la raíz a `.env`.
4. Iniciar el servidor: `uvicorn app.main:app --reload --port 8000`.
