# README for Cyrus test server

If you're looking to make changes, check DEVELOPER.md

This project is a docker image running an instance of the Cyrus IMAPd server
with IMAP4, POP3, JMAP, LMTP, CalDAV, CardDAV and Sieve services running.

The image uses a multi-stage build: Cyrus is compiled in the full
`cyrus-docker:bookworm` dev image, then only the runtime files are copied
into a slim `debian:bookworm-slim` base, producing a much smaller image.

Ports:

* IMAP: 8143
* POP3: 8110
* HTTP: 8080 (JMAP, CalDAV, CardDAV)
* LMTP: 8024
* SIEVE: 4190
* Management web UI / API: 8001 (configurable via `WEBPORT`)

## ENVIRONMENT (set in env.txt for the example below)

* `DEFAULTDOMAIN` - replace the default domain (default: example.com)
* `SERVERNAME` - replace the server name (default: cyrus-docker-test-server)
* `WEBPORT` - management web UI port (default: 8001)
* `RELAYHOST` - if set, send email via this relay (e.g. smtp.fastmail.com)
* `RELAYAUTH` - if set, use this auth (e.g. user:pass)
* `SKIP_CREATE_USERS` - if set, skip creating default users (user1-user5)

# Running

To run a test server with all ports forwarded through

```
sudo docker run -it --env-file=env.txt \
  -p 8080:8080 -p 8143:8143 -p 8110:8110 -p 8024:8024 -p 8001:8001 -p 4190:4190 \
  ghcr.io/cyrusimap/cyrus-docker-test-server:latest
```

To inspect / edit:

```
sudo docker run -it --entrypoint=/bin/bash ghcr.io/cyrusimap/cyrus-docker-test-server:latest
```

To connect to a running instance, use:

```
sudo docker ps
sudo docker exec -it <id> /bin/bash
```

# Web Management Interface

Open http://localhost:8001/ in a browser for a web UI to:

* View running services and connection info
* List, create, and delete users
* View user data (mailboxes, messages) as JSON
* Export/import user data

# API

The JSON API is available under `/api/` (the legacy root-level routes also
still work for backwards compatibility with existing scripts).

Get user data:

```
curl http://localhost:8001/api/username | jq --sort-keys .
```

Create an empty user:

```
curl -T examples/empty.json http://localhost:8001/api/newusername
```

Create a user with sample data:

```
curl -T examples/userdata.json http://localhost:8001/api/newusername
```

Delete a user:

```
curl -X DELETE http://localhost:8001/api/newusername
```

# Connecting

All users accept any password (fakesaslauthd). Default users are
`user1` through `user5`. Admin account: `admin` / `admin`.

IMAP:

```
telnet localhost 8143
. LOGIN user1 x
. SELECT INBOX
. LOGOUT
```

JMAP:

```
curl -u user1:x -X POST -H "Content-Type: application/json" \
  -d '{"methodCalls":[["Mailbox/get", {}, "1"]],"using":["urn:ietf:params:jmap:core","urn:ietf:params:jmap:mail"]}' \
  http://localhost:8080/jmap/
```
