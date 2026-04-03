########################################
# Stage 1: Build Cyrus using the full dev image
########################################
FROM ghcr.io/cyrusimap/cyrus-docker:bookworm AS builder

RUN <<END
set -e
cyd clone
cyd build
END

########################################
# Stage 2: Slim runtime image
########################################
FROM debian:bookworm-slim

LABEL org.opencontainers.image.authors="Cyrus IMAP <docker@role.fastmailteam.com>"
LABEL org.opencontainers.image.source="https://github.com/cyrusimap/cyrus-docker-test-server"

# Create cyrus user and groups to match the builder image
RUN <<END
set -e
groupadd -r mail 2>/dev/null || true
groupadd -r saslauth 2>/dev/null || true
useradd -r -g mail -G saslauth -d /var/imap -s /bin/bash cyrus 2>/dev/null || true
END

# Install runtime dependencies only (no -dev packages, no compilers)
RUN <<END
set -e
apt-get update
apt-get install -y --no-install-recommends \
    postfix \
    rsyslog \
    libsasl2-2 \
    libsasl2-modules \
    libssl3 \
    libjansson4 \
    libxml2 \
    libsqlite3-0 \
    libpcre2-8-0 \
    libpcre2-posix3 \
    libwrap0 \
    libcld2-0 \
    libicu72 \
    libuuid1 \
    libnsl2 \
    libcom-err2 \
    libstdc++6 \
    libgcc-s1 \
    liblzma5 \
    libtirpc3 \
    libgssapi-krb5-2 \
    libkrb5-3 \
    libk5crypto3 \
    libkeyutils1 \
    libnghttp2-14 \
    libwslay1 \
    zlib1g \
    perl \
    libmojolicious-perl \
    libmail-imaptalk-perl \
    libjson-xs-perl \
    libfile-slurp-perl \
    libdigest-crc-perl \
    libmime-base64-perl \
    libtemplate-perl \
    libjson-perl \
    libdata-uuid-perl \
    libmoo-perl \
    libtype-tiny-perl
apt-get clean
rm -rf /var/lib/apt/lists/*
END

# Copy Cyrus installation from builder (includes binaries, libs, and Perl modules)
COPY --from=builder /usr/cyrus /usr/cyrus

# Copy custom-built cyruslibs (ICU 74, Xapian, libical, timezone data, etc.)
COPY --from=builder /usr/local/cyruslibs /usr/local/cyruslibs

# Copy fakesaslauthd
COPY --from=builder /srv/cyrus-imapd/cassandane/utils/fakesaslauthd /usr/cyrus/bin/fakesaslauthd

# Tie::DataUUID: pure Perl, not packaged for Debian, needed by Cyrus::AccountSync
COPY --from=builder /usr/local/share/perl/5.36.0/Tie/DataUUID.pm /tmp/DataUUID.pm

# Ensure the dynamic linker can find cyruslibs
RUN echo "/usr/cyrus/lib" > /etc/ld.so.conf.d/cyrus.conf \
    && echo "/usr/local/cyruslibs/lib" >> /etc/ld.so.conf.d/cyrus.conf \
    && ldconfig

# Make Cyrus Perl modules findable: symlink the installed Cyrus modules
# into the runtime Perl's vendor path (works across arch and Perl version)
# Also copy Tie::DataUUID from the builder (not packaged for Debian)
RUN VENDORLIB=$(perl -MConfig -e 'print $Config{vendorlib}') \
    && mkdir -p "$VENDORLIB/Tie" \
    && for d in /usr/cyrus/lib/*/perl/*/Cyrus; do \
         [ -d "$d" ] && ln -sf "$d" "$VENDORLIB/Cyrus" && break; \
       done \
    && cp /tmp/DataUUID.pm "$VENDORLIB/Tie/" \
    && rm /tmp/DataUUID.pm

# Set up directories
RUN <<END
set -e
install -o cyrus -d /var/run/cyrus
install -o cyrus -d /var/imap
install -o cyrus -d /var/imap/config
install -o cyrus -d /var/imap/search
install -o cyrus -d /var/imap/spool
install -o cyrus -d /var/imap/sieve
END

COPY testserver /srv/testserver
WORKDIR /srv/testserver

EXPOSE 8001
EXPOSE 8024
EXPOSE 8080
EXPOSE 8110
EXPOSE 8143
EXPOSE 4190

ENV SERVERNAME=cyrus-docker-test-server
ENV DEFAULTDOMAIN=example.com

CMD [ "/srv/testserver/start-server" ]
