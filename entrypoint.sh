#!/bin/bash

install -m 755 /srv/cyrus-docker-test-server.git/cyrus.conf /etc/cyrus.conf
install -m 755 /srv/cyrus-docker-test-server.git/imapd.conf /etc/imapd.conf
service rsyslog start
/usr/cyrus/bin/master -p /var/run/cyrus/master.pid -d -L /var/run/cyrus/log
sleep 1;
perl -I /srv/cyrus-imapd.git/perl/imap /srv/cyrus-docker-test-server.git/make5.pl
perl -I /srv/cyrus-imapd.git/perl/imap /srv/cyrus-docker-test-server.git/webserver.pl prefork -l http://*:8001
