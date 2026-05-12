# SMTP Submission Listener on Port 8587

**Date:** 2026-05-12  
**Status:** Approved

## Goal

Add an SMTP submission listener (port 8587) to the cyrus-docker-test-server, so mail clients can be configured against this test server end-to-end — submitting outbound mail over the standard submission port, authenticated with any credentials (matching the existing IMAP/POP3/JMAP "any password works" behaviour).

Submitted mail follows the same relay path as Cyrus-originated mail: Postfix receives it and forwards via the configured `RELAYHOST` (or drops it locally if no relay is configured).

## Architecture

Postfix is already installed and running. It currently listens only on `127.0.0.1:25` (loopback) for mail from Cyrus. This feature adds a second Postfix listener on `0.0.0.0:8587` that accepts authenticated SMTP submission from Docker clients.

Authentication uses Cyrus SASL (`smtpd_sasl_type = cyrus`) backed by the already-running `fakesaslauthd` daemon (which accepts any password). The submission smtpd runs unchrooted so it can reach the fakesaslauthd socket at `/var/run/cyrus/saslauthd.sock`.

### New env var

| Variable    | Default | Description                         |
|-------------|---------|-------------------------------------|
| `SMTPPORT`  | `8587`  | SMTP submission port                |

## Files Changed

### `testserver/main.cf`

Two additions:

1. `smtpd_sasl_type = cyrus` — tells Postfix to use the Cyrus SASL library for SMTP AUTH.
2. `inet_interfaces = all` (replaces `loopback-only`) — required so Postfix can bind the submission listener to `0.0.0.0`. The existing relay restrictions prevent open relay on port 25 regardless.

### `testserver/start-server`

Before calling `postfix start`:

1. Export `SMTPPORT=${SMTPPORT:-8587}`.
2. Append the submission service stanza to `/etc/postfix/master.cf`:

```
0.0.0.0:${SMTPPORT}   inet    n       -       n       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_relay_restrictions=permit_sasl_authenticated,defer_unauth_destination
  -o smtpd_tls_security_level=may
```

The `n` in the chroot column disables chroot for this service so it can access the SASL socket directly.

After the Cyrus ready-wait loop:

4. `chmod 666 /var/run/cyrus/saslauthd.sock` — ensures Postfix (user `postfix`) can connect to the socket even if the group ownership isn't set up perfectly.

### `testserver/sasl_smtpd.conf` (new)

```
pwcheck_method: saslauthd
saslauthd_path: /var/run/cyrus/saslauthd.sock
mech_list: PLAIN LOGIN
```

Placed at `/etc/postfix/sasl/smtpd.conf` at container start. Tells Cyrus SASL (used by Postfix) to delegate password checks to the fakesaslauthd socket.

### `Dockerfile`

- After `apt-get install postfix …`, add `usermod -a -G saslauth postfix` so the postfix user has group access to the SASL socket (belt-and-suspenders alongside the chmod in start-server).
- `RUN mkdir -p /etc/postfix/sasl` and `COPY testserver/sasl_smtpd.conf /etc/postfix/sasl/smtpd.conf` — baked into the image at build time since it has no template variables; start-server does not need to handle it.
- Add `EXPOSE 8587`.

### `webserver.pl`

- Add `my $SMTP_PORT = $ENV{SMTPPORT} // 8587;`
- Add `smtp_port => $SMTP_PORT` to `_common_vars()`.

### `templates/index.html.tt`

- Add SMTP Submission entry to the services grid.
- Add a quick-start `telnet` / `openssl s_client` example for SMTP AUTH PLAIN.

### `README.md`

- Add SMTP Submission row to the ports table.
- Add `SMTPPORT` to the env vars table.
- Add `-p 8587:8587` to the example `docker run` command.

## Data Flow

```
Mail client
  │  AUTH PLAIN user password
  │  MAIL FROM / RCPT TO / DATA
  ▼
Postfix smtpd on 0.0.0.0:8587
  │  Cyrus SASL → fakesaslauthd socket (any password accepted)
  │  smtpd_relay_restrictions: permit_sasl_authenticated
  ▼
Postfix relay (same path as Cyrus-originated mail)
  │  → RELAYHOST if configured
  │  → local delivery if recipient is in virtual_mailbox_domains
  ▼
Cyrus LMTP (port 8024) for local delivery
```

## Error Handling

- If Cyrus hasn't started yet and a client connects on 8587, Postfix will accept the connection but SASL auth will fail (socket not yet available). This is acceptable — the container's ready signal (the web UI on port 8001) only becomes available after Cyrus is ready and the socket chmod has been applied.
- The chmod in start-server is idempotent and silent (`|| true`) so it doesn't break startup if the socket doesn't exist yet.

## Testing

1. Start the container with `-p 8587:8587`.
2. Connect: `openssl s_client -connect localhost:8587 -starttls smtp`
3. Send `EHLO test` — should see `250-AUTH PLAIN LOGIN` in the capability list.
4. Send `AUTH PLAIN` with any base64-encoded credentials — should return `235 2.7.0 Authentication successful`.
5. Submit a message to a local recipient — verify it appears in their Cyrus INBOX.
6. Submit a message to an external address with `RELAYHOST` set — verify it is forwarded.
