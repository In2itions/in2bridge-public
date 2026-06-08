# Install in2bridge

This document describes the intended public installation flow.

## Ubuntu/Debian

If this node will also host the in2bridge database, run the database setup
first:

```bash
sudo ./install/setup-database.sh
```

The database setup script installs MariaDB, asks for database name, user, and
password, then creates the database and grants.

Install the application:

```bash
sudo ./install/install-in2bridge.sh
```

The installer will:

1. Install required OS client tools.
2. Install the in2bridge runtime package.
3. Install the in2bridge engine package.
4. Ask for database host, name, user, and password.
5. Test the database connection.
6. Run the in2bridge schema migrations.
7. Write `/etc/in2bridge/in2bridge.env`.
8. Enable and start `in2bridge-engine.service`.

To reconfigure database access later:

```bash
sudo /opt/in2bridge/install/configure-app-database.sh
```

For test nodes, remove the application and optionally drop the test database:

```bash
sudo /opt/in2bridge/install/cleanup-in2bridge.sh --drop-database
```

## Management HTTPS With Let's Encrypt

The in2bridge management UI/API can use the original certbot paths under
`/etc/letsencrypt/live/<domain>/`. This keeps certificate renewal automated by
Let's Encrypt. The only requirement is that the `in2bridge` service user can
traverse the Let's Encrypt directories and read the certificate chain and
private key.

After certbot has created a certificate, run:

```bash
sudo /opt/in2bridge/install/configure-letsencrypt-management-https.sh in2bridge1.example.com
```

The script:

1. Creates the `ssl-cert` group if the OS does not provide it.
2. Adds the `in2bridge` service user to that group.
3. Grants group traversal on `/etc/letsencrypt`, `live`, and `archive`.
4. Grants group read access to the selected domain certificate files.
5. Verifies that `in2bridge` can read `fullchain.pem`, `privkey.pem`, and
   `chain.pem`.
6. Prints the exact paths to use in General > Management access.

Use these values in the GUI:

```text
Certificate chain path: /etc/letsencrypt/live/<domain>/fullchain.pem
Private key path:       /etc/letsencrypt/live/<domain>/privkey.pem
CA certificate path:    /etc/letsencrypt/live/<domain>/chain.pem
```

To also save the HTTPS settings directly into the in2bridge database and
restart the service:

```bash
sudo /opt/in2bridge/install/configure-letsencrypt-management-https.sh in2bridge1.example.com --apply-db --restart
```

Expected service log after HTTPS is enabled:

```text
management API listening with HTTPS listen_address="0.0.0.0:8090"
```

Verify locally:

```bash
curl -vk https://127.0.0.1:8090/api/health
```

If the browser is opened by IP address, it may show a certificate hostname
warning. Use the DNS name from the certificate, for example:

```text
https://in2bridge1.example.com:8090
```

## Runtime policy

The installer must use in2bridge-provided FFmpeg, SRT, and RIST runtime files
under `/opt/in2bridge/runtime`. Distro versions are not used for transport or
preview behavior.

## License

Customer packages do not include a license generator. Offline licenses are
generated internally and imported through the management UI or API.
