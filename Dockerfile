# Dockerfile
# Stage 1 - build
FROM eclipse-temurin:17-jdk-alpine AS builder

WORKDIR /app

# Copy Maven wrapper and pom.xml separately.
# Until pom.xml is not changed, the dependencies are not downloaded again.
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
RUN ./mvnw dependency:go-offline -B

# Copy source code and build
COPY src ./src
RUN ./mvnw package -DskipTests -B

# JRE is enough to just start an app, no need for JDK (used for build on the first stage)
FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

RUN addgroup -S spring && adduser -S spring -G spring
USER spring:spring

COPY --from=builder /app/target/*.jar app.jar

# port
EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]