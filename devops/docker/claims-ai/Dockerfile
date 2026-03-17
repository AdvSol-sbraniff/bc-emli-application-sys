FROM node:20-bookworm-slim AS builder

WORKDIR /claims_ai_service

COPY claims_ai_service/package*.json ./
RUN npm ci

COPY claims_ai_service/ ./
RUN npm run build

FROM node:20-bookworm-slim AS runner

WORKDIR /claims_ai_service

COPY claims_ai_service/package*.json ./
RUN npm ci --omit=dev

COPY --from=builder /claims_ai_service/dist ./dist

EXPOSE 3001

CMD ["node", "dist/main"]
