# README for Cyrus test server

If you're looking to make changes, check DEVELOPER.md

This project is a docker image running an instance of the Cyrus IMAPd server
with IMAP4, POP3, JMAP, LMTP, CalDAV, CardDAV and Sieve services running.

The image uses a multi-stage build: Cyrus is compiled in the full
`cyrus-docker:bookworm` dev image, then only the runtime files are copied
into a slim `debian:bookworm-slim` base, producing a much smaller image.

## Ports

| Service                          | Port |
|----------------------------------|------|
| IMAP                             | 8143 |
| POP3                             | 8110 |
| HTTP (JMAP, CalDAV, CardDAV)     | 8080 |
| LMTP                             | 8024 |
| Sieve (ManageSieve)              | 4190 |
| Management web UI / API          | 8001 |

All ports are configurable via environment variables (see below).

## Configuration

The server is configured for a modern IMAP layout:

- **`altnamespace: yes`** — Folders appear at the top level alongside INBOX,
  rather than nested beneath it (e.g., `Archive` not `INBOX/Archive`).
  This matches the behaviour of Gmail, Fastmail, and most modern mail clients.

- **`unixhierarchysep: yes`** — The folder hierarchy separator is `/` instead
  of the traditional Cyrus `.`. Sub-folders are named `Work/Projects` rather
  than `Work.Projects`.

- **`sharedprefix: Other Folders`** / **`userprefix: Other Users`** — The
  shared and other-users namespaces appear under descriptive names in clients
  that support multiple IMAP namespaces.

- **`virtdomains: userid`** — Users are identified by their full email address
  (e.g., `user1@example.com`) though the short form `user1` also works.

- **`fakesaslauthd`** — Any password is accepted. Useful for testing without
  managing real credentials.

## Environment variables

| Variable            | Default                    | Description                                      |
|---------------------|----------------------------|--------------------------------------------------|
| `DEFAULTDOMAIN`     | `example.com`              | Default email domain                             |
| `SERVERNAME`        | `cyrus-docker-test-server` | Cyrus server name (used in protocol banners)     |
| `WEBPORT`           | `8001`                     | Management web UI port                           |
| `IMAPPORT`          | `8143`                     | IMAP port                                        |
| `POP3PORT`          | `8110`                     | POP3 port                                        |
| `HTTPPORT`          | `8080`                     | HTTP port (JMAP, CalDAV, CardDAV)                |
| `LMTPPORT`          | `8024`                     | LMTP port                                        |
| `SIEVEPORT`         | `4190`                     | ManageSieve port                                 |
| `SKIP_CREATE_USERS` | (unset)                    | If set, skip creating default users (user1–user5)|

# Running

To run with all ports forwarded (create `env.txt` for any custom variables):

```
docker run -it --env-file=env.txt \
  -p 8080:8080 -p 8143:8143 -p 8110:8110 -p 8024:8024 -p 8001:8001 -p 4190:4190 \
  ghcr.io/cyrusimap/cyrus-docker-test-server:latest
```

To inspect / edit a running container:

```
docker ps
docker exec -it <id> /bin/bash
```

To start a shell directly (skipping the server startup):

```
docker run -it --entrypoint=/bin/bash ghcr.io/cyrusimap/cyrus-docker-test-server:latest
```

# Web Management Interface

Open http://localhost:8001/ in a browser for a web UI to:

* View running services and connection info
* List, create, and delete users
* View user data (mailboxes, messages) as JSON
* Export/import user data

# API

The JSON API is available under `/api/`:

```sh
# Get a user's mailbox and message data
curl http://localhost:8001/api/username | jq --sort-keys .

# Create or replace a user from a JSON file
curl -T testserver/examples/empty.json http://localhost:8001/api/newusername

# Delete a user
curl -X DELETE http://localhost:8001/api/newusername
```

Legacy root-level routes (e.g. `GET /username`) still work for backwards
compatibility with existing scripts.

## Example account files

The `testserver/examples/` directory contains JSON files for seeding new accounts:

| File                    | Description                                                            |
|-------------------------|------------------------------------------------------------------------|
| `inbox-only.json`       | Minimal account: INBOX only                                            |
| `empty.json`            | Standard folders: INBOX, Archive, Drafts, Sent, Spam, Trash           |
| `standard-folders.json` | Extended set: adds Work, Personal, Lists folders                       |
| `welcome.json`          | Standard folders + two welcome emails explaining the server            |
| `userdata.json`         | Full example with a large set of sample email messages                 |

Use them with the API or via the web UI:

```sh
# Minimal account
curl -T testserver/examples/inbox-only.json http://localhost:8001/api/alice

# Standard mailbox layout
curl -T testserver/examples/empty.json http://localhost:8001/api/bob

# Extended folder layout
curl -T testserver/examples/standard-folders.json http://localhost:8001/api/carol

# Standard folders + two welcome emails
curl -T testserver/examples/welcome.json http://localhost:8001/api/dave

# Account with a large set of sample email data
curl -T testserver/examples/userdata.json http://localhost:8001/api/eve
```

You can also export an existing account and use it as a template:

```sh
curl http://localhost:8001/api/user1 > my-template.json
# edit my-template.json as needed
curl -T my-template.json http://localhost:8001/api/newuser
```

# Connecting

All users accept **any password** (fakesaslauthd). The five default users are
`user1` through `user5`. The admin account is `admin` / `admin`.

## IMAP

```
telnet localhost 8143
a LOGIN user1 anypassword
a SELECT INBOX
a LIST "" "*"
a LOGOUT
```

## JMAP

```sh
curl -u user1:x -X POST -H "Content-Type: application/json" \
  -d '{"methodCalls":[["Mailbox/get",{},"1"]],"using":["urn:ietf:params:jmap:core","urn:ietf:params:jmap:mail"]}' \
  http://localhost:8080/jmap/
```

The JMAP access URL can be discovered via the `JMAPACCESS` IMAP capability:

```
telnet localhost 8143
a LOGIN user1 x
a GETJMAPACCESS
a LOGOUT
```

## CalDAV / CardDAV

```
curl -u user1:x http://localhost:8080/dav/principals/user/user1/
```

## LMTP (injecting mail)

```sh
# Deliver a message to user1@example.com
curl smtp://localhost:8024 --mail-from sender@example.com \
  --mail-rcpt user1@example.com --upload-file /path/to/message.eml
```

## ManageSieve

```
telnet localhost 4190
```

# Caveats

- This server is **for testing only**. It accepts any password and stores data
  only while the container is running (no persistent volumes by default).
- The `delete_mode: delayed` and `expunge_mode: delayed` settings mean deleted
  messages and mailboxes are not immediately removed from disk; this is normal.
