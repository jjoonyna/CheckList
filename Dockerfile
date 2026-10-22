FROM eclipse-temurin:21-jre
WORKDIR /app
COPY backend/build/libs/*.jar /app/checklist.jar
EXPOSE 8383
ENTRYPOINT ["java", "-jar", "/app/checklist.jar"]
