# ---------- Etapa 1: Build ----------
FROM golang:1.18 AS build

# Crear carpeta de trabajo
WORKDIR /app

# Copiar go.mod si ya existe (si no, lo generas antes con go mod init && go mod tidy)
COPY go.mod go.sum* ./

# Descargar dependencias
RUN go mod tidy

# Copiar el resto del código fuente
COPY . .

# Compilar el binario
RUN go build -o auth-api

# ---------- Etapa 2: Runtime ----------
FROM gcr.io/distroless/base-debian11

WORKDIR /app

# Copiar binario desde la etapa de build
COPY --from=build /app/auth-api .

# Variables de entorno (puedes sobreescribirlas en docker-compose o docker run)
ENV AUTH_API_PORT=8000
ENV USERS_API_ADDRESS=http://users-api:8083
ENV JWT_SECRET=myfancysecret
ENV ZIPKIN_URL=http://zipkin:9411/api/v2/spans

# Exponer puerto del servicio
EXPOSE 8000

# Ejecutar servicio
ENTRYPOINT ["./auth-api"]
