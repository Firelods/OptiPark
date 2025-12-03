FROM node:22-alpine

# Dossier de travail dans le container
WORKDIR /usr/src/app

# Copie du package.json et installation des deps
COPY package*.json ./
RUN npm install --only=production

# Copie du code
COPY . .

# Sécurité : user non root (optionnel mais conseillé)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

CMD ["node", "index.js"]
