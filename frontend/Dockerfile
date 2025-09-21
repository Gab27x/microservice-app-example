FROM node:8.17.0
WORKDIR /app

# Variables de entorno para que Vue dev-server las use
ENV HOST=0.0.0.0
ENV PORT=3000
ENV AUTH_API_ADDRESS=http://auth-api:8080
ENV TODOS_API_ADDRESS=http://todos-api:8082
ENV ZIPKIN_URL=http://zipkin:9411/api/v2/spans

# Instalar dependencias
COPY package*.json ./
RUN npm install

# Copiar el resto del código
COPY . .

EXPOSE 3000

# Iniciar el servidor respetando las variables
CMD ["npm", "start"]
