# README for Cyrus test server

This project builds a docker image running an instance of the Cyrus IMAPd server with
IMAP, JMAP, CalDAV and CardDAV services running.  The IMAP service is on port 8143
while the other services are on port 8080.

There's also a management service running on port 8001 which can be used to export,
import and delete users from the service, using HTTP: GET, PUT and DELETE.

## Building

To update docker image, check out the git repository and run:

sudo docker build . -t ghcr.io/cyrusimap/cyrus-docker-test-server:latest
sudo docker push       ghcr.io/cyrusimap/cyrus-docker-test-server:latest

# Running

To run with port forwarding enabled

sudo docker run -it -p 8080:8080 -p 8143:8143 -p 8001:8001 ghcr.io/cyrusimap/cyrus-docker-test-server:latest

To inspect / edit:

sudo docker run -it -p 8080:8080 -p 8143:8143 -p 8001:8001 --entrypoint=/bin/bash ghcr.io/cyrusimap/cyrus-docker-test-server:latest

Then to spin up the server while in:

/srv/cyrus-docker-test-server.git/entrypoint.sh

# To create or manage users (from outside)

get:

curl http://localhost:8001/username | jq --sort-keys . > userdata.json

create:

curl -T userdata.json http://localhost:8001/newusername

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

