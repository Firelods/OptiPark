FROM node:18-alpine
WORKDIR /app

# Install app dependencies
COPY package.json package-lock.json* ./
RUN npm install --omit=dev

# Copy source
COPY . .

CMD ["node", "index.js"]
