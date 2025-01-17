FROM ghcr.io/cyrusimap/cyrus-docker:bookworm

LABEL org.opencontainers.image.authors="Cyrus IMAP <docker@role.fastmailteam.com>"
LABEL org.opencontainers.image.source="https://github.com/cyrusimap/cyrus-docker-test-server"

RUN <<END
# set up user and ownership for Cyrus & Postfix
#
# The "mail" and "saslauth" groups will already exist from the upstream image,
# and the "cyrus" user will already be in them.
set -e

install -o cyrus -d /var/run/cyrus
install -o cyrus -d /var/imap
install -o cyrus -d /var/imap/config
install -o cyrus -d /var/imap/search
install -o cyrus -d /var/imap/spool

apt-get -y install postfix
END

RUN <<END
# build and install Cyrus
set -e
cyd clone
cyd build
END

COPY testserver /srv/testserver
WORKDIR /srv/testserver

EXPOSE 8001
EXPOSE 8024
EXPOSE 8080
EXPOSE 8110
EXPOSE 8143

ENV SERVERNAME=cyrus-docker-test-server
ENV DEFAULTDOMAIN=example.com

RUN apt-get install -y libmojolicious-perl

CMD [ "/srv/testserver/start-server" ]
