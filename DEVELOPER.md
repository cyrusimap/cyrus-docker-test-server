## Building and testing

A `Makefile` is provided with common targets:

```sh
make build    # Build the Docker image
make run      # Run the server with all ports forwarded
make test     # Run the integration test suite (test.sh)
make stop     # Stop the running container
make clean    # Remove stopped containers
make publish  # Push the image to ghcr.io
```

### Manual build and publish

```sh
docker build --platform linux/amd64 -t ghcr.io/cyrusimap/cyrus-docker-test-server:latest .
docker push ghcr.io/cyrusimap/cyrus-docker-test-server:latest
```

### Running tests manually

```sh
bash test.sh
```

The test suite checks:
- IMAP login (good and bad authentication)
- User creation and deletion via the web API
- IMAP SELECT, LIST, FETCH
- LMTP message delivery
- Sieve script upload
- JMAP Mailbox/get, Email/get, Email/set
- CalDAV Calendar/set
- CardDAV AddressBook/set
- JMAPACCESS capability and URL

### Architecture

Multi-stage Docker build:
1. **Builder** (`cyrus-docker:bookworm`) — clones and builds Cyrus from source
   using `cyd clone && cyd build`, producing `/usr/cyrus` and
   `/usr/local/cyruslibs`
2. **Runtime** (`debian:bookworm-slim`) — copies only the compiled output and
   installs runtime `.so` libraries via `apt-get`

This keeps the image size small (no compilers, no -dev packages).

### Port templating

`env-replace.pl` substitutes `{{VARNAME}}` placeholders in `imapd.conf` and
`cyrus.conf` at container startup, allowing all ports to be configured via
environment variables.

### Perl modules

Cyrus Perl modules are installed by `cyd build` into
`/usr/cyrus/lib/<arch>/perl/<version>/Cyrus/`. The Dockerfile symlinks this
path into the runtime system's `vendorlib` directory so they are importable
without setting `PERL5LIB`.

`Tie::DataUUID` is not packaged for Debian; it is copied from the builder
as a pure-Perl file.
