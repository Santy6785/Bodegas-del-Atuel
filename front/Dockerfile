# =====================================================================
# Dockerfile del servicio front - Bodegas del Atuel
#
# Frontend en Vanilla HTML5, CSS3 y JavaScript ES Modules.
# Servido directamente mediante un contenedor ligero Nginx Alpine.
# =====================================================================

FROM nginx:alpine

# Copiar todos los archivos estáticos del frontend al directorio raíz de Nginx
COPY . /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
