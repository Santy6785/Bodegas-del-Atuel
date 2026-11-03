# =====================================================================
# Dockerfile del servicio api - PLANTILLA GENÉRICA (stack por definir)
#
# Stack candidato: Python/FastAPI | Node/Express | otro
#
# TODO:
#   1. Elegir el stack y completar esta plantilla.
#   2. Reemplazar la imagen base por la del stack elegido
#      (ej. python:3.11-slim, node:20-alpine, etc.).
#   3. Adaptar la instalación de dependencias (requirements.txt / package.json).
#   4. Definir el puerto real y el comando de arranque del stack.
#   5. Revisar que la API se conecte a la base con el rol app_rw
#      (DB_USER/DB_PASSWORD), NUNCA con el propietario ni superusuario.
# =====================================================================

# TODO: cambiar por la imagen base del stack elegido (esta es solo un ejemplo)
FROM python:3.11-slim AS base

# Evitar archivos .pyc y forzar logs sin buffer (ajustar al stack)
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Instalar dependencias (TODO: adaptar al stack elegido)
COPY api/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Código de la API (de otros integrantes - no modificar)
COPY api/ ./

# Usuario no-root (principio de mínimo privilegio)
RUN useradd -m -u 10000 appuser && chown -R appuser:appuser /app
USER appuser

# TODO: definir el puerto real expuesto por el stack (ej. 8000 uvicorn / 3000 express)
EXPOSE 8000

# TODO: comando de arranque del stack, descomentar el que corresponda:
#   CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
#   CMD ["node", "src/index.js"]
# (Mientras no se complete, el contenedor imprime un mensaje y termina con error)
CMD ["sh", "-c", "echo 'TODO: configurar el comando de arranque de la API en api/Dockerfile' && exit 1"]

# Configuración SOLO por variables de entorno (nunca se copia .env a la imagen):
#   DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD
# La API debe conectarse con el rol app_rw (lectura/escritura),
# NUNCA con el propietario ni con un superusuario.
