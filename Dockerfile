ARG           FROM_REGISTRY=ghcr.io/dubo-dubon-duponey

ARG           FROM_IMAGE_BUILDER=base:builder-bullseye-2021-10-15@sha256:1609d1af44c0048ec0f2e208e6d4e6a525c6d6b1c0afcc9d71fccf985a8b0643
ARG           FROM_IMAGE_AUDITOR=base:auditor-bullseye-2021-10-15@sha256:2c95e3bf69bc3a463b00f3f199e0dc01cab773b6a0f583904ba6766b3401cb7b
ARG           FROM_IMAGE_RUNTIME=base:runtime-bullseye-2021-10-15@sha256:5c54594a24e3dde2a82e2027edd6d04832204157e33775edc66f716fa938abba
ARG           FROM_IMAGE_TOOLS=tools:linux-bullseye-2021-10-15@sha256:4de02189b785c865257810d009e56f424d29a804cc2645efb7f67b71b785abde

FROM          $FROM_REGISTRY/$FROM_IMAGE_TOOLS                                                                          AS builder-tools

#######################
# Builder assembly
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_AUDITOR                                              AS builder

RUN           mkdir -p /dist/boot/bin

COPY          --from=builder-tools  /boot/bin/goello-server-ng  /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/http-health    /dist/boot/bin

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Running image
#######################
# https://www.digitalocean.com/community/tutorials/how-to-install-mariadb-on-debian-10
#sudo apt-get install software-properties-common dirmngr apt-transport-https
#sudo apt-key adv --fetch-keys 'https://mariadb.org/mariadb_release_signing_key.asc'
#sudo add-apt-repository 'deb [arch=amd64,arm64,ppc64el] http://mirrors.accretive-networks.net/mariadb/repo/10.6/debian bullseye main'

#deb [arch=amd64,arm64,ppc64el] http://mirrors.accretive-networks.net/mariadb/repo/10.6/debian buster main
# deb-src http://mirrors.accretive-networks.net/mariadb/repo/10.6/debian buster main


FROM          $FROM_REGISTRY/$FROM_IMAGE_RUNTIME

ARG           MARIA_MAIN=10.6

USER          root

# XXX this is hard tied to bullseye
RUN           --mount=type=secret,uid=100,id=CA \
              --mount=type=secret,uid=100,id=CERTIFICATE \
              --mount=type=secret,uid=100,id=KEY \
              --mount=type=secret,uid=100,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_CONFIG \
              --mount=type=secret,id=.curlrc \
              apt-get update -qq            && \
              apt-get install -qq --no-install-recommends \
                curl=7.74.0-1.3+b1 \
                gnupg=2.2.27-2      && \
              curl -sSfL https://mariadb.org/mariadb_release_signing_key.asc | apt-key add - && \
              echo "deb [arch=amd64,arm64,ppc64el] http://mirrors.accretive-networks.net/mariadb/repo/${MARIA_MAIN}/debian bullseye main" | tee /etc/apt/sources.list.d/mariadb.list && \
              apt-get update -qq            && \
              apt show mariadb-server && \
              apt-get install -qq --no-install-recommends \
                mariadb-server=1:10.6.4+maria~bullseye && \
              apt-get purge -qq curl gnupg  && \
              apt-get -qq autoremove        && \
              apt-get -qq clean             && \
              rm -rf /var/lib/apt/lists/*   && \
              rm -rf /tmp/*                 && \
              rm -rf /var/tmp/*

USER          dubo-dubon-duponey

COPY          --from=builder --chown=$BUILD_UID:root /dist /

#ENV           PATH=/usr/lib/postgresql/$PG_MAJOR/bin/:$PATH
#ENV           PGDATA=/data

STOPSIGNAL    SIGINT

EXPOSE        3306
VOLUME        /data
VOLUME        /tmp

ENV           _SERVICE_NICK="maria"
ENV           _SERVICE_TYPE="database"

### mDNS broadcasting
# Type to advertise
ENV           MDNS_TYPE="_$_SERVICE_TYPE._tcp"
# Name is used as a short description for the service
ENV           MDNS_NAME="$_SERVICE_NICK mDNS display name"
# The service will be annonced and reachable at $MDNS_HOST.local (set to empty string to disable mDNS announces entirely)
ENV           MDNS_HOST="$_SERVICE_NICK"
# Also announce the service as a workstation (for example for the benefit of coreDNS mDNS)
ENV           MDNS_STATION=true

# Realm in case access is authenticated
ENV           REALM="My Precious Realm"
# Provide username and password here (call the container with the "hash" command to generate a properly encrypted password, otherwise, a random one will be generated)
ENV           USERNAME=""
ENV           PASSWORD=""

# Log level and port
ENV           PORT=3306

ENV           HEALTHCHECK_URL=http://127.0.0.1:3306/
# XXX replace with nc -zv localhost 5432 or a homegrown version of it
#HEALTHCHECK   --interval=30s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1
