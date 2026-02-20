# placeholder multi-stage Dockerfile
FROM node:18-alpine AS build
WORKDIR /app
COPY . .
