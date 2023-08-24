rm -fR /var/lib/postgresql/archive/* && \
rm -fR /var/lib/postgresql/backup/* && \
PGUSER=noctdb PGDATABASE=misskeydb /usr/lib/postgresql/15/bin/pg_rman init -B /var/lib/postgresql/backup -D /var/lib/postgresql/data -A /var/lib/postgresql/archive
