# README for Cyrus test server

If you're looking to make changes, check DEVELOPER.txt

This project is a docker image running an instance of the Cyrus IMAPd server with
IMAP4, POP3, JMAP, LMTP, CalDAV and CardDAV services running.

Ports:
 * IMAP: 8143
 * POP3: 8110
 * HTTP: 8080 (jmap, *dav)
 * LMTP: 8024

There's also a management service running on port 8001 which can be used to export,
import and delete users from the service, using HTTP: GET, PUT and DELETE.

## ENVIRONMENT (set in env.txt for the example below)

* REFRESH - if set, fetch the latest cyrus-docker-test-server code (useful for development)
* CYRUS_VERSION - if set, build a new cyrus with the named branch
* DEFAULTDOMAIN - replace the default domain (default: example.com)
* SERVERNAME - replace the server name (default: cyrus-docker-test-server)
* RELAYHOST - if set, send email via this relay (e.g. smtp.fastmail.com)
* RELAYAUTH - if set, use this auth (e.g. user:pass)

# Running

To run a test server with all ports forwarded through

sudo docker run -it --env-file=env.txt \
  -p 8080:8080 -p 8143:8143 -p 8110:8110 -p 8024:8024 -p 8001:8001 \
  ghcr.io/cyrusimap/cyrus-docker-test-server:latest

To inspect / edit:

sudo docker run -it --entrypoint=/bin/bash ghcr.io/cyrusimap/cyrus-docker-test-server:latest

and then you need to run;

/srv/cyrus-docker-test-server.git/entrypoint.sh

To connect to a running instance, use:

sudo docker ps

And once you have the process - to look inside:

sudo docker exec -it <id> /bin/bash


# To create or manage users (from outside)

get:

curl http://localhost:8001/username | jq --sort-keys . > userdata.json

create an empty user:

curl -T examples/empty.json http://localhost:8001/newusername

create a user with a couple of sample emails and saved uidvalidity:

curl -T examples/userdata.json http://localhost:8001/newusername

delete:
curl -X DELETE http://localhost:8001/newusername

login with IMAP:

```
% telnet localhost 8143
. LOGIN newusername x
. SELECT INBOX
...
. LOGOUT
```

raw JMAP commands:

```
curl -u username:x -X POST -H "Content-Type: application/json" -d '{"methodCalls":[["Mailbox/get", {}, "1"]],"using":["urn:ietf:params:jmap:core","urn:ietf:params:jmap:mail"]}' http://localhost:8080/jmap/
```

