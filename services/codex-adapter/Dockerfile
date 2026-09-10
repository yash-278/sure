FROM node:24.14.0-bookworm-slim
RUN apt-get update && apt-get install --no-install-recommends -y ca-certificates && rm -rf /var/lib/apt/lists/*
RUN npm install --global @openai/codex@0.154.0
WORKDIR /app
COPY package.json rpc.ts operations.ts server.ts ./
ENV PORT=3000 CODEX_HOME=/data/codex
EXPOSE 3000
CMD ["node", "server.ts"]
