# ---- Dockerfile ----
    FROM alpine:3.19

    # tools the script needs: bash, pg_dump/pg_restore, gzip & curl
    RUN apk add --no-cache bash postgresql-client gzip curl
    
    WORKDIR /app
    COPY script/ ./script/
    
    # the template’s logic lives in script/migrate.sh
    ENTRYPOINT ["bash", "/script/migrate.sh"]
    