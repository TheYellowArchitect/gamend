# syntax=docker/dockerfile:1
# gamend-backup: a verified dump of a Postgres database once a day, kept
# daily, weekly and monthly (docker/backup/README.md). One compose service:
#
#   db_backup:
#     image: ghcr.io/appsinacup/gamend-backup:18
#     restart: always
#     depends_on: [db]
#     environment:
#       PGHOST: db
#       PGUSER: ${POSTGRES_USER:-postgres}
#       PGPASSWORD: ${POSTGRES_PASSWORD}
#       PGDATABASE: ${POSTGRES_DB}
#     volumes:
#       - ./backups:/backups
#
# The tag is the Postgres major it is built on, and has to be the database's:
# pg_dump refuses a server of a newer major. Published beside gamend-builder
# (.github/workflows/base-images.yml), weekly too, so its minor stays current.
ARG POSTGRES_IMAGE=postgres:18
FROM ${POSTGRES_IMAGE}

COPY --chmod=0755 pg_backup.sh restore.sh verify_restore.sh /usr/local/bin/

ENTRYPOINT ["/bin/bash", "/usr/local/bin/pg_backup.sh"]
# The postgres image's CMD would be passed to the loop as an argument.
CMD []
