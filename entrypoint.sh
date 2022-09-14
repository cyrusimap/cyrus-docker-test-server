#!/bin/bash

service rsyslog start
/usr/cyrus/bin/master -p /var/run/cyrus/master.pid -d -L /var/run/cyrus/log
perl -I /srv/cyrus-imapd.git/perl/imap /srv/cyrus-docker-test-server.git/webserver.pl prefork -l http://*:8001
