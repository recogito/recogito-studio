# Temporary fix to get up-to-date Node 22 onto supabase-meta
FROM supabase/postgres-meta:v0.100.0 AS upstream

FROM node:22.23.4-slim
RUN apt-get update && apt-get install -y \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /usr/src/app
COPY --from=upstream /usr/src/app ./
ENV PG_META_PORT=8080
CMD ["node", "dist/server/server.js"]
EXPOSE 8080
HEALTHCHECK --interval=5s --timeout=5s --retries=3 CMD node -e "fetch('http://localhost:8080/health').then((r) => {if (r.status !== 200) throw new Error(r.status)})"
