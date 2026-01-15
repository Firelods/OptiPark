# Build stage
FROM node:22-alpine AS build

WORKDIR /app


# Copie des fichiers de dépendances
COPY package*.json ./

# Installation des dépendances
RUN npm install

# Copie du code source
COPY . .

RUN npm run build

# Production stage
FROM nginx:alpine

# Copie du build depuis le stage précédent
COPY --from=build /app/dist /usr/share/nginx/html

# Copie de la configuration nginx personnalisée (si nécessaire pour SPA)
RUN echo 'server { \
    listen 80; \
    server_name localhost; \
    location / { \
        root /usr/share/nginx/html; \
        index index.html; \
        try_files $uri $uri/ /index.html; \
    } \
}' > /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]