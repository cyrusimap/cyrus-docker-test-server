# SMTP Submission Listener (port 8587) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an authenticated SMTP submission listener on port 8587, backed by Postfix and the existing fakesaslauthd "any password accepted" daemon.

**Architecture:** Postfix is already running in the container. We add a second `smtpd` listener on `0.0.0.0:8587` (appended to `/etc/postfix/master.cf` at startup) that requires SMTP AUTH, delegates credential checks to the fakesaslauthd socket via Cyrus SASL, and relays mail through the same path as Cyrus-originated mail. `inet_interfaces` is changed from `loopback-only` to `all` so the new listener can bind to all interfaces; the existing relay restrictions prevent open relay on port 25.

**Tech Stack:** Postfix, Cyrus SASL (`libsasl2-modules`), fakesaslauthd (already running), Mojolicious (web UI), Template Toolkit (index page), bash (start-server).

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `testserver/sasl_smtpd.conf` | **Create** | SASL config: use saslauthd at fakesaslauthd socket |
| `testserver/main.cf` | **Modify** | `inet_interfaces=all`, add `smtpd_sasl_type=cyrus` |
| `testserver/start-server` | **Modify** | Export SMTPPORT, append submission stanza to master.cf, chmod SASL socket |
| `Dockerfile` | **Modify** | `usermod` postfix into saslauth group, install SASL config, EXPOSE 8587 |
| `testserver/webserver.pl` | **Modify** | Expose `smtp_port` to all templates via `_common_vars` |
| `testserver/templates/index.html.tt` | **Modify** | Add SMTP row to services grid and quick-start section |
| `README.md` | **Modify** | Document new port, env var, and docker run flag |

---

## Task 1: Create `testserver/sasl_smtpd.conf`

**Files:**
- Create: `testserver/sasl_smtpd.conf`

This file is read by the Cyrus SASL library (used by Postfix) to determine how to authenticate SMTP AUTH credentials. It points to the fakesaslauthd socket that accepts any password.

- [ ] **Step 1: Create the file**

Create `testserver/sasl_smtpd.conf` with exactly this content:

```
pwcheck_method: saslauthd
saslauthd_path: /var/run/cyrus/saslauthd.sock
mech_list: PLAIN LOGIN
```

- `pwcheck_method: saslauthd` — delegate auth to the saslauthd socket rather than checking a local password database
- `saslauthd_path` — path to the fakesaslauthd socket (created at runtime by Cyrus)
- `mech_list` — advertise only PLAIN and LOGIN (the two mechanisms mail clients universally support)

- [ ] **Step 2: Commit**

```bash
git add testserver/sasl_smtpd.conf
git commit -m "feat: add SASL config for Postfix SMTP AUTH via fakesaslauthd"
```

---

## Task 2: Update `testserver/main.cf`

**Files:**
- Modify: `testserver/main.cf`

Two changes: (1) `inet_interfaces = all` so the submission listener can bind to `0.0.0.0`. (2) `smtpd_sasl_type = cyrus` so Postfix uses the Cyrus SASL library (which reads `/etc/postfix/sasl/smtpd.conf`).

- [ ] **Step 1: Edit `testserver/main.cf`**

Replace the line:
```
inet_interfaces = loopback-only
```
with:
```
inet_interfaces = all
```

Then add this line anywhere in the file (end of file is fine):
```
smtpd_sasl_type = cyrus
```

The final file should contain both of these among its settings. The existing relay restrictions (`smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination`) already prevent open relay on port 25, so opening the interface is safe.

- [ ] **Step 2: Commit**

```bash
git add testserver/main.cf
git commit -m "feat: allow Postfix to bind all interfaces; enable Cyrus SASL for smtpd"
```

---

## Task 3: Update `testserver/start-server`

**Files:**
- Modify: `testserver/start-server`

Three changes: (1) export `SMTPPORT` with default. (2) Append the submission service stanza to `/etc/postfix/master.cf` before starting Postfix. (3) After Cyrus is ready, `chmod` the fakesaslauthd socket so the `postfix` user can connect to it.

- [ ] **Step 1: Add SMTPPORT export**

In the "port defaults" block at the top of the file, add one line after the `WEBPORT` export. The block currently ends at line 9. The new block should be:

```bash
# port defaults
export IMAPPORT=${IMAPPORT:-8143}
export POP3PORT=${POP3PORT:-8110}
export HTTPPORT=${HTTPPORT:-8080}
export LMTPPORT=${LMTPPORT:-8024}
export SIEVEPORT=${SIEVEPORT:-4190}
export WEBPORT=${WEBPORT:-8001}
export SMTPPORT=${SMTPPORT:-8587}
```

- [ ] **Step 2: Append submission stanza before `postfix start`**

The file currently has these lines in sequence (around line 22–24):

```bash
perl /srv/testserver/env-replace.pl /srv/testserver/main.cf /etc/postfix/main.cf

/etc/init.d/postfix start
```

Replace that block with:

```bash
perl /srv/testserver/env-replace.pl /srv/testserver/main.cf /etc/postfix/main.cf

cat >> /etc/postfix/master.cf << EOF

# SMTP submission
0.0.0.0:${SMTPPORT}   inet  n       -       n       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_sasl_security_options=noanonymous
  -o smtpd_relay_restrictions=permit_sasl_authenticated,defer_unauth_destination
  -o smtpd_tls_security_level=may
EOF

/etc/init.d/postfix start
```

Notes on the master.cf columns: `n - n - - smtpd` means private=no, unpriv=default, **chroot=no** (the third `n` — unchrooted so the process can reach `/var/run/cyrus/saslauthd.sock`), wakeup=default, maxproc=default.

`smtpd_sasl_security_options=noanonymous` explicitly allows PLAIN/LOGIN without TLS — appropriate for a test server.

- [ ] **Step 3: chmod the SASL socket after Cyrus is ready**

The ready-wait loop currently reads (lines 32–36):

```bash
# wait for Cyrus master to signal readiness
for i in $(seq 1 60); do
  [ -f /var/run/cyrus/ready ] && break
  sleep 1
done
```

Replace it with:

```bash
# wait for Cyrus master to signal readiness
for i in $(seq 1 60); do
  [ -f /var/run/cyrus/ready ] && break
  sleep 1
done

# allow Postfix to reach the fakesaslauthd socket
chmod 666 /var/run/cyrus/saslauthd.sock 2>/dev/null || true
```

The `|| true` makes startup silent if the socket doesn't exist (e.g., if Cyrus failed to start — other errors will surface anyway).

- [ ] **Step 4: Commit**

```bash
git add testserver/start-server
git commit -m "feat: add SMTPPORT export and submission listener setup in start-server"
```

---

## Task 4: Update `Dockerfile`

**Files:**
- Modify: `Dockerfile`

Three additions: (1) Add `postfix` to the `saslauth` group (belt-and-suspenders alongside the `chmod`). (2) Install `sasl_smtpd.conf` to `/etc/postfix/sasl/smtpd.conf`. (3) Expose port 8587.

- [ ] **Step 1: Add `usermod` after the apt-get block**

The apt-get `RUN <<END … END` block ends at line 78. After it, add one line:

```dockerfile
RUN usermod -a -G saslauth postfix
```

The resulting Dockerfile around that area should look like:

```dockerfile
apt-get clean
rm -rf /var/lib/apt/lists/*
END

RUN usermod -a -G saslauth postfix

# Copy Cyrus installation from builder (includes binaries, libs, and Perl modules)
COPY --from=builder /usr/cyrus /usr/cyrus
```

- [ ] **Step 2: Install the SASL config after `COPY testserver`**

Line 123 is `COPY testserver /srv/testserver`. After it, add:

```dockerfile
RUN mkdir -p /etc/postfix/sasl
COPY testserver/sasl_smtpd.conf /etc/postfix/sasl/smtpd.conf
```

The resulting Dockerfile around that area:

```dockerfile
COPY testserver /srv/testserver
WORKDIR /srv/testserver

RUN mkdir -p /etc/postfix/sasl
COPY testserver/sasl_smtpd.conf /etc/postfix/sasl/smtpd.conf

EXPOSE 8001
```

- [ ] **Step 3: Add `EXPOSE 8587`**

The EXPOSE block currently ends with `EXPOSE 4190` (line 131). Add the new port after it:

```dockerfile
EXPOSE 8001
EXPOSE 8024
EXPOSE 8080
EXPOSE 8110
EXPOSE 8143
EXPOSE 4190
EXPOSE 8587
```

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "feat: add postfix to saslauth group, install SASL config, expose port 8587"
```

---

## Task 5: Update `testserver/webserver.pl`

**Files:**
- Modify: `testserver/webserver.pl:27-44`

Add `$SMTP_PORT` to the port variables and expose it via `_common_vars` so every template has access to it.

- [ ] **Step 1: Add the port variable**

The port variables block (lines 27–33) currently ends with:

```perl
my $SIEVE_PORT = $ENV{SIEVEPORT} // 4190;
```

Add one line after it:

```perl
my $SMTP_PORT  = $ENV{SMTPPORT}  // 8587;
```

- [ ] **Step 2: Add to `_common_vars`**

The `_common_vars` sub (lines 35–44) currently ends with:

```perl
    sieve_port => $SIEVE_PORT,
  );
```

Add one entry before the closing `);`:

```perl
    sieve_port => $SIEVE_PORT,
    smtp_port  => $SMTP_PORT,
  );
```

- [ ] **Step 3: Commit**

```bash
git add testserver/webserver.pl
git commit -m "feat: expose smtp_port to templates via _common_vars"
```

---

## Task 6: Update `testserver/templates/index.html.tt`

**Files:**
- Modify: `testserver/templates/index.html.tt`

Add SMTP Submission to the services grid, and add a quick-start example showing how to send a test message.

- [ ] **Step 1: Add SMTP to the services grid**

The services grid currently ends with:

```html
    <div class="info-item">
      <div class="label">Management</div>
      <div class="value">Port [% web_port %]</div>
    </div>
  </div>
</div>
```

Add the new entry before the closing `</div></div>`:

```html
    <div class="info-item">
      <div class="label">Management</div>
      <div class="value">Port [% web_port %]</div>
    </div>
    <div class="info-item">
      <div class="label">SMTP Submission</div>
      <div class="value">Port [% smtp_port %]</div>
    </div>
  </div>
</div>
```

- [ ] **Step 2: Add SMTP quick-start example**

The quick-start section currently ends with the JMAP example. After the JMAP `</pre>` block, add:

```html
  <h3>SMTP Submission</h3>
  <pre>openssl s_client -connect localhost:[% smtp_port %] -starttls smtp</pre>
```

- [ ] **Step 3: Commit**

```bash
git add testserver/templates/index.html.tt
git commit -m "feat: add SMTP submission to services grid and quick-start section"
```

---

## Task 7: Update `README.md`

**Files:**
- Modify: `README.md`

Three additions: port table, env var table, docker run command.

- [ ] **Step 1: Add to the ports table**

The ports table (lines 14–21) currently ends with:

```
| Sieve (ManageSieve)              | 4190 |
| Management web UI / API          | 8001 |
```

Add one row:

```
| Sieve (ManageSieve)              | 4190 |
| SMTP Submission                  | 8587 |
| Management web UI / API          | 8001 |
```

- [ ] **Step 2: Add to the env vars table**

The env vars table (lines 49–59) currently ends with:

```
| `SIEVEPORT`         | `4190`                     | ManageSieve port                                 |
| `SKIP_CREATE_USERS` | (unset)                    | If set, skip creating default users (user1–user5)|
```

Add one row before `SKIP_CREATE_USERS`:

```
| `SIEVEPORT`         | `4190`                     | ManageSieve port                                 |
| `SMTPPORT`          | `8587`                     | SMTP submission port                             |
| `SKIP_CREATE_USERS` | (unset)                    | If set, skip creating default users (user1–user5)|
```

- [ ] **Step 3: Update the docker run example**

The run command (lines 65–69) currently reads:

```
docker run -it --env-file=env.txt \
  -p 8080:8080 -p 8143:8143 -p 8110:8110 -p 8024:8024 -p 8001:8001 -p 4190:4190 \
  ghcr.io/cyrusimap/cyrus-docker-test-server:latest
```

Replace with:

```
docker run -it --env-file=env.txt \
  -p 8080:8080 -p 8143:8143 -p 8110:8110 -p 8024:8024 -p 8001:8001 -p 4190:4190 -p 8587:8587 \
  ghcr.io/cyrusimap/cyrus-docker-test-server:latest
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document SMTP submission port 8587"
```

---

## Task 8: Build and smoke-test

**Files:** None (verification only)

- [ ] **Step 1: Build the Docker image**

```bash
docker build -t cyrus-test-smtp .
```

Expected: build completes without errors. The `usermod` step and SASL config copy should appear in the output.

- [ ] **Step 2: Run the container**

```bash
docker run -d --name cyrus-smtp-test \
  -p 8001:8001 -p 8143:8143 -p 8587:8587 \
  cyrus-test-smtp
```

Wait ~10 seconds for startup, then check the web UI is up:

```bash
curl -s http://localhost:8001/ | grep -o 'SMTP Submission'
```

Expected output: `SMTP Submission`

- [ ] **Step 3: Verify EHLO advertises AUTH**

```bash
(printf "EHLO test\r\nQUIT\r\n"; sleep 2) | nc localhost 8587
```

Expected: response includes `250-AUTH PLAIN LOGIN` in the EHLO reply. Also check `250-STARTTLS` is present.

- [ ] **Step 4: Test AUTH PLAIN succeeds with any password**

The AUTH PLAIN credential string is a base64-encoded `\0username\0password`. Compute it:

```bash
printf '\0user1\0anything' | base64
# Output: AHVzZXIxAGFueXRoaW5n
```

Then authenticate:

```bash
(printf "EHLO test\r\nAUTH PLAIN AHVzZXIxAGFueXRoaW5n\r\nQUIT\r\n"; sleep 3) | nc localhost 8587
```

Expected: `235 2.7.0 Authentication successful`

If you see `535 5.7.8 Error: authentication failed`, check the container logs for SASL errors:

```bash
docker exec cyrus-smtp-test cat /var/log/syslog | grep -i sasl
```

Common causes: socket permission issue (chmod didn't run), socket not yet created (Cyrus still starting up).

- [ ] **Step 5: Submit a test message to a local user**

```bash
# AUTH LOGIN base64 encoding
printf 'user1' | base64   # dXNlcjE=
printf 'anything' | base64  # YW55dGhpbmc=

(printf "EHLO test\r\nAUTH LOGIN\r\ndXNlcjE=\r\nYW55dGhpbmc=\r\nMAIL FROM:<test@example.com>\r\nRCPT TO:<user1@example.com>\r\nDATA\r\nFrom: test@example.com\r\nTo: user1@example.com\r\nSubject: SMTP test\r\n\r\nSMTP submission test body\r\n.\r\nQUIT\r\n"; sleep 5) | nc localhost 8587
```

Expected: `250 2.0.0 Ok: queued as ...`

Then check user1's inbox:

```bash
curl -s http://localhost:8001/api/user1 | jq '.mailboxes[] | select(.name == "INBOX")'
```

Expected: INBOX message count increases by 1.

- [ ] **Step 6: Clean up**

```bash
docker stop cyrus-smtp-test && docker rm cyrus-smtp-test
```
