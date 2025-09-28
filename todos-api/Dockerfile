# Usa la versión específica de Node.js (8.17.0 con npm 6.13.4)
FROM node:8.17.0

# Directorio de trabajo dentro del contenedor
WORKDIR /usr/src/app

# Copia package.json y package-lock.json (si existe) primero
COPY package*.json ./

# Instala dependencias
RUN npm install

# Copia el resto del código
COPY . .

# Variables de entorno (se pueden sobreescribir en docker-compose o docker run -e)
ENV TODO_API_PORT=8082 \
    JWT_SECRET=myfancysecret \
    REDIS_HOST=redis \
    REDIS_PORT=6379 \
    REDIS_CHANNEL=todos-log \
    ZIPKIN_URL=http://zipkin:9411/api/v2/spans

# Expone el puerto definido
EXPOSE ${TODO_API_PORT}

# Comando de inicio
CMD ["npm", "start"]
