#!/bin/bash

cd /srv/cyrus-docker-test-server.git

if [ "X$REFRESH" != "X" ]; then
  git fetch
  git checkout origin/master
fi

if [ "X$CYRUS_VERSION" != "X" ]; then
  (cd /srv/cyrus-imapd.git; \
   git fetch; \
   git checkout $CYRUS_VERSION; \
   env CFLAGS="-g -W -Wall -Wextra -Werror" CONFIGOPTS=" --enable-autocreate --enable-backup --enable-calalarmd --enable-gssapi --enable-http --enable-idled --enable-murder --enable-nntp --enable-replication --enable-shared --enable-silent-rules --enable-unit-tests --enable-xapian --enable-jmap --with-ldap=/usr" /srv/cyrus-imapd.git/tools/build-with-cyruslibs.sh
  )
fi

bash run.sh
