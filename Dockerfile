FROM alpine:3.22 AS builder

ARG V_COMMIT=45ae01d23168b6372f734eeb38a77360bbcf184a
ARG VEEMARKER_COMMIT=1510ef5a7cbf980f2e075f02baada7190748e3f7
ARG DOTENV_COMMIT=1d9477c8b1a3f5ca14b2eb042c4e6d52449b75d4
ARG V_STRIPE_COMMIT=ccc7e4151038589d97b47e3cc7d0de44abf3247c

RUN apk add --no-cache \
    build-base \
    ca-certificates \
    gc-dev \
    git \
    openssl-dev \
    pax-utils \
    pkgconf \
    postgresql-dev \
    sqlite-dev

RUN git clone https://github.com/vlang/v.git /opt/v \
    && git -C /opt/v checkout --detach "${V_COMMIT}" \
    && make -C /opt/v \
    && test "$(git -C /opt/v rev-parse HEAD)" = "${V_COMMIT}" \
    && /opt/v/v version | grep -F 'V 0.5.2'

RUN mkdir -p /root/.vmodules/leafscale /root/.vmodules/ken0x0a \
    && git clone https://github.com/leafscale/veemarker.git /root/.vmodules/leafscale/veemarker \
    && git -C /root/.vmodules/leafscale/veemarker checkout --detach "${VEEMARKER_COMMIT}" \
    && git clone https://github.com/ken0x0a/v-dotenv.git /root/.vmodules/ken0x0a/dotenv \
    && git -C /root/.vmodules/ken0x0a/dotenv checkout --detach "${DOTENV_COMMIT}" \
    && git clone https://github.com/Ddiidev/v-stripe.git /root/.vmodules/v_stripe \
    && git -C /root/.vmodules/v_stripe checkout --detach "${V_STRIPE_COMMIT}" \
    && test "$(git -C /root/.vmodules/leafscale/veemarker rev-parse HEAD)" = "${VEEMARKER_COMMIT}" \
    && test "$(git -C /root/.vmodules/ken0x0a/dotenv rev-parse HEAD)" = "${DOTENV_COMMIT}" \
    && test "$(git -C /root/.vmodules/v_stripe rev-parse HEAD)" = "${V_STRIPE_COMMIT}"

WORKDIR /src
COPY . .

RUN /opt/v/v \
    -cc gcc \
    -ldflags "-Wl,--gc-sections -ffunction-sections -fdata-sections" \
    -gc boehm_incr_opt \
    -d using_sqlite \
    -d use_openssl \
    -d new_veb \
    -prod \
    . \
    -o TabuaMareAPI \
    && sha256sum taubinha.sqlite | awk '{ print $1 }' > taubinha.sqlite.sha256 \
    && scanelf --needed --nobanner TabuaMareAPI \
    && ldd TabuaMareAPI | tee /tmp/ldd.txt \
    && ! grep -Fq 'not found' /tmp/ldd.txt

FROM alpine:3.22 AS runtime

RUN apk add --no-cache \
    ca-certificates \
    curl \
    gc \
    libcrypto3 \
    libgcc \
    libpq \
    libssl3 \
    sqlite \
    sqlite-libs \
    su-exec \
    tini \
    tzdata \
    && addgroup -S -g 10001 app \
    && adduser -S -D -H -u 10001 -G app app \
    && mkdir -p /app/data /app/seed \
    && chown app:app /app/data /app/seed \
    && chmod 0750 /app/data /app/seed

WORKDIR /app

COPY --from=builder /src/TabuaMareAPI /app/TabuaMareAPI
COPY --from=builder /src/pages /app/pages
COPY --from=builder /src/taubinha.sqlite /app/seed/taubinha.sqlite
COPY --from=builder /src/taubinha.sqlite.sha256 /app/seed/taubinha.sqlite.sha256
COPY dockerfiles/entrypoint-alpine.sh /usr/local/bin/entrypoint-alpine.sh

RUN chmod 0755 /app/TabuaMareAPI /usr/local/bin/entrypoint-alpine.sh \
    && chmod -R a=rX /app/pages /app/seed

ENV PORT=3330 \
    DB_SQLITE_PATH=/app/data/taubinha.sqlite \
    URL_ENV=https://tabuamare.api.br \
    TZ=America/Sao_Paulo

EXPOSE 3330

HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=3 \
    CMD curl -fsS -o /dev/null http://127.0.0.1:${PORT}/health/ready || exit 1

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint-alpine.sh"]
