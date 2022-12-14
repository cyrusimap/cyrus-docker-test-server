FROM debian:buster
MAINTAINER Cyrus IMAP <docker@role.fastmailteam.com>

# RUN echo 'Acquire::Check-Valid-Until no;' > /etc/apt/apt.conf.d/99no-check-valid-until

# RUN echo "deb http://archive.debian.org/debian/ jessie-backports main contrib" >> /etc/apt/sources.list.d/sources.list

RUN apt-get update && apt-get -y install \
    autoconf \
    automake \
    autotools-dev \
    bash-completion \
    bison \
    build-essential \
    check \
    clang \
    cmake \
    comerr-dev \
    cpanminus \
    doxygen \
    debhelper \
    flex \
    g++ \
    git \
    gperf \
    graphviz \
    groff \
    texi2html \
    texinfo \
    heimdal-dev \
    help2man \
    libanyevent-perl \
    libbsd-dev \
    libbsd-resource-perl \
    libclone-perl \
    libconfig-inifiles-perl \
    libcunit1-dev \
    libdatetime-perl \
    libdb-dev \
    libdbi-perl \
    libdigest-sha-perl \
    libencode-imaputf7-perl \
    libfile-chdir-perl \
    libfile-slurp-perl \
    libglib2.0-dev \
    libio-async-perl \
    libio-socket-inet6-perl \
    libio-stringy-perl \
    libjson-perl \
    libjson-xs-perl \
    libldap2-dev \
    libmagic-dev \
    libmilter-dev \
    default-libmysqlclient-dev \
    libnet-server-perl \
    libnews-nntpclient-perl \
    libpath-tiny-perl \
    libpam0g-dev \
    libpcre3-dev \
    libplack-perl \
    libsasl2-dev \
    libsnmp-dev \
    libsqlite3-dev \
    libssl-dev \
    libstring-crc32-perl \
    libtest-deep-perl \
    libtest-most-perl \
    libtest-unit-perl \
    libtest-tcp-perl \
    libtool \
    libunix-syslog-perl \
    liburi-perl \
    libxml-generator-perl \
    libxml-xpath-perl \
    libxml2-dev \
    libwrap0-dev \
    libwww-perl \
    libxapian-dev \
    libzephyr-dev \
    lsb-base \
    net-tools \
    pandoc \
    perl \
    php-cli \
    php-curl \
    pkg-config \
    po-debconf \
    python-docutils \
    python-sphinx \
    rsync \
    rsyslog \
    sudo \
    sphinx-common \
    tcl-dev \
    transfig \
    uuid-dev \
    vim \
    wamerican \
    wget \
    xutils-dev \
    zlib1g-dev \
    libmojolicious-perl \
    curl \
    libdigest-crc-perl \
    jq

RUN cpanm install Term::ReadLine
RUN cpanm install Mail::IMAPTalk Net::CalDAVTalk Net::CardDAVTalk
RUN cpanm install Convert::Base64 File::LibMagic;
RUN cpanm install Net::LDAP::Constant
RUN cpanm install Net::LDAP::Server
RUN cpanm install Net::LDAP::Server::Test
RUN cpanm install Math::Int64
RUN cpanm install DBD::SQLite
RUN cpanm install Mail::JMAPTalk

RUN groupadd -r saslauth ; \
    groupadd -r mail ; \
    useradd -c "Cyrus IMAP Server" -d /var/lib/imap \
    -g mail -G saslauth -s /bin/bash -r cyrus

RUN install -o cyrus -d /var/run/cyrus; install -o cyrus -d /var/imap; install -o cyrus -d /var/imap/config; install -o cyrus -d /var/imap/search; install -o cyrus -d /var/imap/spool

WORKDIR /srv

RUN git config --global http.sslverify false && \
    git clone https://github.com/cyrusimap/cyruslibs.git \
    cyruslibs.git

RUN git config --global http.sslverify false && \
    git clone https://github.com/cyrusimap/cyrus-imapd.git \
    cyrus-imapd.git

RUN git config --global http.sslverify false && \
    git clone https://github.com/cyrusimap/cyrus-docker-test-server.git \
    cyrus-docker-test-server.git

WORKDIR /srv/cyruslibs.git
RUN git submodule init: git submodule update; ./build.sh

WORKDIR /srv/cyrus-imapd.git
RUN env CFLAGS="-g -W -Wall -Wextra -Werror" CONFIGOPTS=" --enable-autocreate --enable-backup --enable-calalarmd --enable-gssapi --enable-http --enable-idled --enable-murder --enable-nntp --enable-replication --enable-shared --enable-silent-rules --enable-unit-tests --enable-xapian --enable-jmap --with-ldap=/usr" /srv/cyrus-imapd.git/tools/build-with-cyruslibs.sh

EXPOSE 8001
EXPOSE 8080
EXPOSE 8143

ENTRYPOINT [ "/srv/cyrus-docker-test-server.git/entrypoint.sh" ]

