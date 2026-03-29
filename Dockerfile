FROM ubuntu:20.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    git \
    curl \
    build-essential \
    libsqlite3-dev \
    ca-certificates \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp
RUN git clone https://github.com/vlang/v && \
    cd v && \
    make && \
    ./v symlink && \
    v --version

WORKDIR /app
COPY v.mod ./

RUN v install && \
    v install https://github.com/ken0x0a/v-dotenv

COPY . .

RUN v version && \
    v -ldflags "-Wl,--gc-sections -march=native -ffunction-sections -fdata-sections" -gc boehm_incr_opt -d using_sqlite -d use_openssl -prod . -o TabuaMareAPI

FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    libssl1.1 \
    libsqlite3-0 \
    ca-certificates \
    curl \
    nginx \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

RUN adduser --system --no-create-home --group nginx || true

RUN set -eux; \
    mkdir -p --mode=0755 /usr/share/keyrings; \
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" > /etc/apt/sources.list.d/cloudflared.list; \
    apt-get update; \
    apt-get install -y cloudflared; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/TabuaMareAPI ./
COPY --from=builder /app/pages ./pages
COPY --from=builder /app/cache ./cache
COPY --from=builder /app/taubinha.sqlite ./taubinha.sqlite

COPY --from=builder /app/start.sh ./start.sh
COPY --from=builder /app/nginx/nginx.conf /etc/nginx/nginx.conf
COPY --from=builder /app/dockerfiles/nginx.single.conf /etc/nginx/conf.d/tabua-mare-single.conf
COPY --from=builder /app/dockerfiles/supervisord.single.conf /app/dockerfiles/supervisord.single.conf

RUN chmod +x ./start.sh && \
    mkdir -p /app/data /var/run/nginx /var/log/nginx /etc/supervisor/conf.d && \
    rm -f /etc/nginx/conf.d/default.conf /etc/nginx/sites-enabled/default

ENV DB_SQLITE_PATH=/app/data/taubinha.sqlite
ENV URL_ENV=http://localhost:9090

EXPOSE 9090

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://127.0.0.1:9090/api-health || exit 1

ENTRYPOINT ["./start.sh"]
