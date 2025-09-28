# ---------- Etapa 1: Construcción ----------
FROM maven:3.8.7-eclipse-temurin-8 AS build
WORKDIR /app

# Copiar pom.xml y descargar dependencias primero (cacheo eficiente)
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copiar el código fuente y compilar
COPY src ./src
RUN mvn clean package -DskipTests

# ---------- Etapa 2: Ejecución ----------
FROM eclipse-temurin:8-jre
WORKDIR /app

# Copiar el jar construido desde la etapa anterior
COPY --from=build /app/target/users-api-0.0.1-SNAPSHOT.jar app.jar

# Variables de entorno para Spring Boot
ENV JWT_SECRET=myfancysecret
ENV SERVER_PORT=8083
ENV SPRING_APPLICATION_NAME=users-api
ENV SPRING_ZIPKIN_BASEURL=http://zipkin:9411/api/v2/spans
ENV SPRING_SLEUTH_SAMPLER_PERCENTAGE=100.0

# Exponer el puerto configurado
EXPOSE 8083

# Comando de arranque
ENTRYPOINT ["java", "-jar", "app.jar"]
