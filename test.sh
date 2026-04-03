#!/bin/bash
#
# Integration tests for the Cyrus Docker Test Server.
# Expects the container to be running with standard port mappings.
#
set -euo pipefail

HOST=${TEST_HOST:-localhost}
IMAP_PORT=${TEST_IMAPPORT:-8143}
POP3_PORT=${TEST_POP3PORT:-8110}
HTTP_PORT=${TEST_HTTPPORT:-8080}
LMTP_PORT=${TEST_LMTPPORT:-8024}
SIEVE_PORT=${TEST_SIEVEPORT:-4190}
WEB_PORT=${TEST_WEBPORT:-8001}

PASS=0
FAIL=0
ERRORS=""

pass() {
  PASS=$((PASS + 1))
  echo "  PASS: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: $1"
  echo "  FAIL: $1"
}

check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

check_output() {
  local desc="$1"
  local pattern="$2"
  shift 2
  local output
  output=$("$@" 2>&1) || true
  if echo "$output" | grep -q "$pattern"; then
    pass "$desc"
  else
    fail "$desc (expected '$pattern', got: $(echo "$output" | head -3))"
  fi
}

# Helper: send raw commands to a TCP port, return output
tcp_cmd() {
  local port="$1"
  shift
  local input="$*"
  echo -e "$input" | perl -e '
    use IO::Socket::INET;
    my $sock = IO::Socket::INET->new(
      PeerAddr => "'"$HOST"'",
      PeerPort => '"$port"',
      Proto    => "tcp",
      Timeout  => 10,
    ) or die "connect failed: $!";
    $sock->autoflush(1);
    # read banner
    my $banner = <$sock>;
    print $banner;
    while (<STDIN>) {
      print $sock $_;
      while (1) {
        my $line = <$sock>;
        last unless defined $line;
        print $line;
        # match tagged responses (A001 OK, A002 NO, etc) but not untagged (* OK)
        last if $line =~ /^[A-Z]\d+\s+(OK|NO|BAD)\b/;
      }
    }
    close $sock;
  ' 2>&1
}

echo "============================================"
echo " Cyrus Docker Test Server - Integration Tests"
echo "============================================"
echo ""

# -----------------------------------------------
echo "[Web UI]"
# -----------------------------------------------

check_output "Home page loads" "Cyrus Test Server" \
  curl -sf "http://$HOST:$WEB_PORT/"

check_output "Users page loads" "Existing Users" \
  curl -sf "http://$HOST:$WEB_PORT/ui/users"

check_output "Home shows IMAP port" "Port $IMAP_PORT" \
  curl -sf "http://$HOST:$WEB_PORT/"

check_output "Home shows JMAP port" "Port $HTTP_PORT" \
  curl -sf "http://$HOST:$WEB_PORT/"

echo ""

# -----------------------------------------------
echo "[API - User Management]"
# -----------------------------------------------

# Create a test user
API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -T testserver/examples/empty.json "http://$HOST:$WEB_PORT/api/testuser_$$")
if [ "$API_STATUS" = "204" ]; then
  pass "Create user via API (PUT /api/testuser_$$)"
else
  fail "Create user via API (PUT /api/testuser_$$) - got HTTP $API_STATUS"
fi

# Get user data
API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "http://$HOST:$WEB_PORT/api/testuser_$$")
if [ "$API_STATUS" = "200" ]; then
  pass "Get user via API (GET /api/testuser_$$)"
else
  fail "Get user via API (GET /api/testuser_$$) - got HTTP $API_STATUS"
fi

check_output "User data contains INBOX" "INBOX" \
  curl -sf "http://$HOST:$WEB_PORT/api/testuser_$$"

# Get nonexistent user
API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "http://$HOST:$WEB_PORT/api/nosuchuser_$$")
if [ "$API_STATUS" = "404" ]; then
  pass "Nonexistent user returns 404"
else
  fail "Nonexistent user returns 404 - got HTTP $API_STATUS"
fi

# Delete user
API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X DELETE "http://$HOST:$WEB_PORT/api/testuser_$$")
if [ "$API_STATUS" = "204" ]; then
  pass "Delete user via API (DELETE /api/testuser_$$)"
else
  fail "Delete user via API (DELETE /api/testuser_$$) - got HTTP $API_STATUS"
fi

# Verify deleted
API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "http://$HOST:$WEB_PORT/api/testuser_$$")
if [ "$API_STATUS" = "404" ]; then
  pass "Deleted user returns 404"
else
  fail "Deleted user returns 404 - got HTTP $API_STATUS"
fi

# Legacy route compatibility
curl -s -T testserver/examples/empty.json "http://$HOST:$WEB_PORT/legacyuser_$$" >/dev/null 2>&1
API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "http://$HOST:$WEB_PORT/legacyuser_$$")
if [ "$API_STATUS" = "200" ]; then
  pass "Legacy route GET /legacyuser works"
else
  fail "Legacy route GET /legacyuser works - got HTTP $API_STATUS"
fi
curl -s -X DELETE "http://$HOST:$WEB_PORT/legacyuser_$$" >/dev/null 2>&1

echo ""

# -----------------------------------------------
echo "[IMAP]"
# -----------------------------------------------

# Create a user for IMAP tests
curl -s -T testserver/examples/empty.json "http://$HOST:$WEB_PORT/api/imaptest_$$" >/dev/null 2>&1

# Good login
IMAP_OUT=$(tcp_cmd "$IMAP_PORT" "A001 LOGIN imaptest_$$ anypassword\nA002 LOGOUT")
if echo "$IMAP_OUT" | grep -q "A001 OK"; then
  pass "IMAP login with valid user succeeds"
else
  fail "IMAP login with valid user succeeds"
fi

# Check we get the banner
if echo "$IMAP_OUT" | grep -qi "Cyrus IMAP"; then
  pass "IMAP banner contains Cyrus"
else
  fail "IMAP banner contains Cyrus"
fi

# SELECT INBOX
IMAP_OUT=$(tcp_cmd "$IMAP_PORT" "A001 LOGIN imaptest_$$ x\nA002 SELECT INBOX\nA003 LOGOUT")
if echo "$IMAP_OUT" | grep -q "A002 OK"; then
  pass "IMAP SELECT INBOX succeeds"
else
  fail "IMAP SELECT INBOX succeeds"
fi

# LIST mailboxes
IMAP_OUT=$(tcp_cmd "$IMAP_PORT" "A001 LOGIN imaptest_$$ x\nA002 LIST \"\" *\nA003 LOGOUT")
if echo "$IMAP_OUT" | grep -q "INBOX"; then
  pass "IMAP LIST shows INBOX"
else
  fail "IMAP LIST shows INBOX"
fi

# Admin login
IMAP_OUT=$(tcp_cmd "$IMAP_PORT" "A001 LOGIN admin admin\nA002 LOGOUT")
if echo "$IMAP_OUT" | grep -q "A001 OK"; then
  pass "IMAP admin login succeeds"
else
  fail "IMAP admin login succeeds"
fi

# JMAPACCESS capability and URL
IMAP_OUT=$(tcp_cmd "$IMAP_PORT" "A001 LOGIN imaptest_$$ x\nA002 LOGOUT")
if echo "$IMAP_OUT" | grep -q "JMAPACCESS"; then
  pass "IMAP CAPABILITY includes JMAPACCESS"
else
  fail "IMAP CAPABILITY includes JMAPACCESS"
fi

IMAP_OUT=$(tcp_cmd "$IMAP_PORT" "A001 LOGIN imaptest_$$ x\nA002 GETJMAPACCESS\nA003 LOGOUT")
JMAP_URL=$(echo "$IMAP_OUT" | grep '^\* JMAPACCESS' | sed 's/^\* JMAPACCESS //' | tr -d '\r"')
if [ -n "$JMAP_URL" ]; then
  pass "GETJMAPACCESS returns URL ($JMAP_URL)"
  JMAP_ACCESS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u "imaptest_$$:x" "$JMAP_URL" 2>&1)
  if [ "$JMAP_ACCESS_STATUS" = "200" ]; then
    pass "JMAPACCESS URL is reachable"
  else
    fail "JMAPACCESS URL is reachable - got HTTP $JMAP_ACCESS_STATUS"
  fi
else
  fail "GETJMAPACCESS returns URL"
fi

# Clean up
curl -s -X DELETE "http://$HOST:$WEB_PORT/api/imaptest_$$" >/dev/null 2>&1

echo ""

# -----------------------------------------------
echo "[POP3]"
# -----------------------------------------------

# Create user for POP3
curl -s -T testserver/examples/empty.json "http://$HOST:$WEB_PORT/api/poptest_$$" >/dev/null 2>&1

POP_OUT=$(echo -e "USER poptest_$$\nPASS x\nSTAT\nQUIT" | perl -e '
  use IO::Socket::INET;
  my $sock = IO::Socket::INET->new(
    PeerAddr => "'"$HOST"'", PeerPort => '"$POP3_PORT"',
    Proto => "tcp", Timeout => 10,
  ) or die "connect: $!";
  $sock->autoflush(1);
  my $banner = <$sock>; print $banner;
  while (<STDIN>) {
    print $sock $_;
    my $resp = <$sock>;
    print $resp if defined $resp;
  }
  close $sock;
' 2>&1)

if echo "$POP_OUT" | grep -q "+OK"; then
  pass "POP3 connection and login"
else
  fail "POP3 connection and login"
fi

curl -s -X DELETE "http://$HOST:$WEB_PORT/api/poptest_$$" >/dev/null 2>&1

echo ""

# -----------------------------------------------
echo "[HTTP/JMAP]"
# -----------------------------------------------

# Create user for JMAP
curl -s -T testserver/examples/empty.json "http://$HOST:$WEB_PORT/api/jmaptest_$$" >/dev/null 2>&1

# JMAP Mailbox/get
JMAP_OUT=$(curl -sf -u "jmaptest_$$:x" -X POST \
  -H "Content-Type: application/json" \
  -d '{"methodCalls":[["Mailbox/get",{},"1"]],"using":["urn:ietf:params:jmap:core","urn:ietf:params:jmap:mail"]}' \
  "http://$HOST:$HTTP_PORT/jmap/" 2>&1) || true

if echo "$JMAP_OUT" | grep -q "Mailbox/get"; then
  pass "JMAP Mailbox/get returns results"
else
  fail "JMAP Mailbox/get returns results"
fi

if echo "$JMAP_OUT" | grep -qi "inbox"; then
  pass "JMAP response contains Inbox"
else
  fail "JMAP response contains Inbox"
fi

# JMAP without auth
JMAP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"methodCalls":[["Mailbox/get",{},"1"]],"using":["urn:ietf:params:jmap:core","urn:ietf:params:jmap:mail"]}' \
  "http://$HOST:$HTTP_PORT/jmap/" 2>&1)
if [ "$JMAP_STATUS" = "401" ]; then
  pass "JMAP without credentials returns 401"
else
  fail "JMAP without credentials returns 401 - got HTTP $JMAP_STATUS"
fi

# CalDAV well-known
CALDAV_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "http://$HOST:$HTTP_PORT/.well-known/caldav" 2>&1)
if [ "$CALDAV_STATUS" = "301" ] || [ "$CALDAV_STATUS" = "302" ] || [ "$CALDAV_STATUS" = "200" ]; then
  pass "CalDAV well-known endpoint responds ($CALDAV_STATUS)"
else
  fail "CalDAV well-known endpoint responds - got HTTP $CALDAV_STATUS"
fi

# CardDAV well-known
CARDDAV_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "http://$HOST:$HTTP_PORT/.well-known/carddav" 2>&1)
if [ "$CARDDAV_STATUS" = "301" ] || [ "$CARDDAV_STATUS" = "302" ] || [ "$CARDDAV_STATUS" = "200" ]; then
  pass "CardDAV well-known endpoint responds ($CARDDAV_STATUS)"
else
  fail "CardDAV well-known endpoint responds - got HTTP $CARDDAV_STATUS"
fi

# Calendar/set - create a calendar (issue #4 regression test)
CAL_OUT=$(curl -sf -u "jmaptest_$$:x" -X POST \
  -H "Content-Type: application/json" \
  -d '{"using":["urn:ietf:params:jmap:core","urn:ietf:params:jmap:calendars"],"methodCalls":[["Calendar/set",{"create":{"new0":{"name":"TestCal"}}},"0"]]}' \
  "http://$HOST:$HTTP_PORT/jmap/" 2>&1) || true

if echo "$CAL_OUT" | grep -q '"created"' && ! echo "$CAL_OUT" | grep -q '"created":null'; then
  pass "Calendar/set creates a calendar"
else
  fail "Calendar/set creates a calendar"
fi

# AddressBook/set - create an address book (issue #4 regression test)
AB_OUT=$(curl -sf -u "jmaptest_$$:x" -X POST \
  -H "Content-Type: application/json" \
  -d '{"using":["urn:ietf:params:jmap:core","urn:ietf:params:jmap:contacts"],"methodCalls":[["AddressBook/set",{"create":{"new0":{"name":"TestAB"}}},"0"]]}' \
  "http://$HOST:$HTTP_PORT/jmap/" 2>&1) || true

if echo "$AB_OUT" | grep -q '"created"' && ! echo "$AB_OUT" | grep -q '"created":null'; then
  pass "AddressBook/set creates an address book"
else
  fail "AddressBook/set creates an address book"
fi

curl -s -X DELETE "http://$HOST:$WEB_PORT/api/jmaptest_$$" >/dev/null 2>&1

echo ""

# -----------------------------------------------
echo "[Sieve]"
# -----------------------------------------------

SIEVE_OUT=$(echo "" | perl -e '
  use IO::Socket::INET;
  my $sock = IO::Socket::INET->new(
    PeerAddr => "'"$HOST"'", PeerPort => '"$SIEVE_PORT"',
    Proto => "tcp", Timeout => 10,
  ) or die "connect: $!";
  my $banner = "";
  while (my $line = <$sock>) {
    $banner .= $line;
    last if $line =~ /^OK/;
  }
  print $banner;
  close $sock;
' 2>&1)

if echo "$SIEVE_OUT" | grep -qi "Cyrus timsieved"; then
  pass "Sieve banner present"
else
  fail "Sieve banner present"
fi

echo ""

# -----------------------------------------------
echo "[LMTP - Delivery]"
# -----------------------------------------------

# Create user for delivery test
curl -s -T testserver/examples/empty.json "http://$HOST:$WEB_PORT/api/lmtptest_$$" >/dev/null 2>&1

LMTP_OUT=$(perl -e '
  use IO::Socket::INET;
  my $sock = IO::Socket::INET->new(
    PeerAddr => "'"$HOST"'", PeerPort => '"$LMTP_PORT"',
    Proto => "tcp", Timeout => 15,
  ) or die "connect: $!";
  $sock->autoflush(1);
  sub rd { my $r = ""; while (my $l = <$sock>) { $r .= $l; last if $l =~ /^\d{3}\s/; } return $r; }
  print rd();  # banner
  print $sock "LHLO test\r\n"; print rd();
  print $sock "MAIL FROM:<test\@example.com>\r\n"; print rd();
  print $sock "RCPT TO:<lmtptest_'"$$"'\@example.com>\r\n"; print rd();
  print $sock "DATA\r\n"; print rd();
  print $sock "From: test\@example.com\r\nTo: lmtptest_'"$$"'\@example.com\r\nSubject: Test $$\r\n\r\nTest body.\r\n.\r\n";
  print rd();  # delivery response
  print $sock "QUIT\r\n"; print rd();
  close $sock;
' 2>&1)

if echo "$LMTP_OUT" | grep -q "^250 "; then
  pass "LMTP delivery accepted"
else
  fail "LMTP delivery accepted"
fi

# Verify message arrived via IMAP (poll until delivered or timeout)
DELIVERY_OK=0
for i in $(seq 1 30); do
  IMAP_OUT=$(tcp_cmd "$IMAP_PORT" "A001 LOGIN lmtptest_$$ x\nA002 SELECT INBOX\nA003 LOGOUT")
  if echo "$IMAP_OUT" | grep -q "[0-9]* EXISTS" && ! echo "$IMAP_OUT" | grep -q "0 EXISTS"; then
    DELIVERY_OK=1
    break
  fi
  sleep 1
done
if [ "$DELIVERY_OK" = "1" ]; then
  pass "Delivered message visible in INBOX"
else
  fail "Delivered message visible in INBOX"
fi

curl -s -X DELETE "http://$HOST:$WEB_PORT/api/lmtptest_$$" >/dev/null 2>&1

echo ""

# -----------------------------------------------
echo "[Web UI - User Management]"
# -----------------------------------------------

# Create user via web form
WEB_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST -d "userid=webtest_$$" "http://$HOST:$WEB_PORT/ui/users")
if [ "$WEB_STATUS" = "302" ]; then
  pass "Create user via web form redirects (302)"
else
  fail "Create user via web form redirects - got HTTP $WEB_STATUS"
fi

check_output "Created user appears in user list" "webtest_$$" \
  curl -sf "http://$HOST:$WEB_PORT/ui/users"

check_output "User detail page loads" "webtest_$$" \
  curl -sf "http://$HOST:$WEB_PORT/ui/users/webtest_$$"

# Delete via web
WEB_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "http://$HOST:$WEB_PORT/ui/users/webtest_$$/delete")
if [ "$WEB_STATUS" = "302" ]; then
  pass "Delete user via web form redirects (302)"
else
  fail "Delete user via web form redirects - got HTTP $WEB_STATUS"
fi

# Invalid username
WEB_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST -d "userid=bad%20user!" "http://$HOST:$WEB_PORT/ui/users")
if [ "$WEB_STATUS" = "302" ]; then
  pass "Invalid username rejected with redirect"
else
  fail "Invalid username rejected - got HTTP $WEB_STATUS"
fi

echo ""

# -----------------------------------------------
# Summary
# -----------------------------------------------
echo "============================================"
echo " Results: $PASS passed, $FAIL failed"
echo "============================================"
if [ "$FAIL" -gt 0 ]; then
  echo -e "\nFailures:$ERRORS"
  exit 1
fi
