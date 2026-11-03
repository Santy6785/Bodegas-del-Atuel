# =====================================================================
# Dockerfile del servicio front - PLANTILLA GENÉRICA (stack por definir)
#
# Stack candidato: HTML estático | React+Vite | otro
#
# TODO:
#   1. Elegir el stack y completar esta plantilla.
#   2. Reemplazar la imagen base de build por la del stack elegido
#      (ej. node:20-alpine para Vite/React).
#   3. Adaptar la instalación de dependencias y el comando de build.
#   4. Ajustar la ruta de salida del build (ej. /app/dist, /app/build).
#   5. Si es HTML estático, omitir la etapa de build y copiar directamente.
# =====================================================================

# ---------------------------------------------------------------
# Etapa 1: build de la aplicación (ej. con Vite)
# ---------------------------------------------------------------
# TODO: cambiar por la imagen base del stack elegido (esta es solo un ejemplo)
FROM node:20-alpine AS build

WORKDIR /app

# URL base de la API con valor por defecto; se sobrescribe por variable
# de entorno en docker-compose.yml (API_BASE_URL).
ENV API_BASE_URL=http://localhost:8000

# Dependencias (TODO: adaptar al stack elegido)
COPY front/package*.json ./
RUN npm ci

# Código del front y build (de otros integrantes - no modificar)
COPY front/ ./
RUN npm run build   # TODO: comando de build del stack (ej. npm run build, vite build)

# ---------------------------------------------------------------
# Etapa 2: servir archivos estáticos con nginx (imagen liviana)
# ---------------------------------------------------------------
FROM nginx:alpine

# TODO: ajustar la ruta de salida del build (dist / build / .)
COPY --from=build /app/dist /usr/share/nginx/html

# Puerto expuesto al contenedor (mapeado al host en docker-compose.yml)
EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]

# No se copia .env a la imagen: la URL base de la API se inyecta por
# variable de entorno en tiempo de ejecución (API_BASE_URL o equivalente
# del stack, ej. VITE_API_BASE_URL).
