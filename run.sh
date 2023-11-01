#!/bin/bash

# set up Postfix
if [ "X$RELAYHOST" != "" ]; then
  echo "$RELAYHOST $RELAYAUTH" >> /etc/postfix/sasl_passwd
  postmap /etc/postfix/sasl_passwd
fi

perl /srv/cyrus-docker-test-server.git/env-replace.pl /srv/cyrus-docker-test-server.git/main.cf /etc/postfix/main.cf

# set up Cyrus
perl /srv/cyrus-docker-test-server.git/env-replace.pl /srv/cyrus-docker-test-server.git/imapd.conf /etc/imapd.conf
perl /srv/cyrus-docker-test-server.git/env-replace.pl /srv/cyrus-docker-test-server.git/cyrus.conf /etc/cyrus.conf
/usr/cyrus/bin/master -p /var/run/cyrus/master.pid -d -L /var/run/cyrus/log

# create users
perl -I /srv/cyrus-imapd.git/perl/imap /srv/cyrus-docker-test-server.git/make5.pl

# run the webserver
perl -I /srv/cyrus-imapd.git/perl/imap /srv/cyrus-docker-test-server.git/webserver.pl prefork -l http://*:8001
